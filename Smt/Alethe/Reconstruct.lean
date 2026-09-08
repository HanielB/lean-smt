/-
Copyright (c) 2021-2026 by the authors listed in the file AUTHORS and their
institutional affiliations. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Haniel Barbosa
-/

module

public import Smt.Alethe.Basic
public meta import Smt.Alethe.Basic
public import Smt.Reconstruct.Builtin.Lemmas
public meta import Smt.Reconstruct.Builtin.Lemmas
public import Smt.Reconstruct.Util
public meta import Smt.Reconstruct.Util

public meta section

/-!
# The Alethe proof driver

Walks the commands of a realized proof in order, dispatching each step to the registered
`RuleReconstructor`s.

Every top-level step is checked by the kernel on its own: its reconstructed proof is checked
(`Kernel.check`) in a local context in which the earlier steps are hypotheses, and the step then
becomes a new hypothesis for the steps after it. No proof term of the whole derivation is ever
built, so the kernel's work is proportional to the sum of the step sizes and never to the depth of
the derivation. The derivation is valid when every step was checked and the empty clause was
derived. Steps that no reconstructor handles, whose reconstruction fails, or that the kernel
rejects are *trusted*: they still become hypotheses, and are counted per rule.

Steps inside a subproof are reconstructed as metavariables and inlined into the proof of the step
that closes the subproof, which is what the kernel checks.
-/

namespace Smt.Alethe

open Lean Qq
open Smt.Reconstruct

register_option smt.alethe.kernel : Bool := {
  defValue := true
  descr := "check every reconstructed Alethe step in the kernel (disable only to measure)"
}

register_option smt.alethe.checkInner : Bool := {
  defValue := false
  descr := "also type-check (with the elaborator) the steps inside subproofs, to attribute failures"
}

structure Stats where
  /-- Steps proved by a reconstructor and accepted by the kernel. -/
  checked : Nat := 0
  /-- Trusted steps, per rule. -/
  trusted : Std.HashMap String Nat := {}
  holes : Nat := 0
  /-- Step id, rule, and message of every step that was trusted. -/
  failures : Array (String × String × String) := #[]
  /-- Whether the empty clause was derived. -/
  emptyClause : Bool := false
  /-- Milliseconds spent in the kernel. -/
  kernelMs : Nat := 0
deriving Inhabited

def Stats.numTrusted (st : Stats) : Nat :=
  st.trusted.fold (fun n _ k => n + k) 0

def Stats.valid (st : Stats) : Bool :=
  st.emptyClause && st.numTrusted == 0 && st.holes == 0

/-- A stable one-line summary: rules sorted by name. -/
def Stats.summary (st : Stats) : String := Id.run do
  let mut s := s!"checked {st.checked} steps, trusted {st.numTrusted}"
  if st.numTrusted > 0 then
    let rules := st.trusted.toArray.qsort (fun a b => a.1 < b.1)
    s := s ++ " (" ++ ", ".intercalate (rules.toList.map fun (r, n) => s!"{r}: {n}") ++ ")"
  s := s ++ s!", holes {st.holes}"
  if !st.emptyClause then
    s := s ++ ", empty clause not derived"
  return s

structure DState where
  steps : Std.HashMap String Premise := {}
  stats : Stats := {}
  /-- The problem's assertions with their propositions and hypotheses. -/
  asserts : Array (cvc5.Term × Expr × Expr) := #[]
  reconstructors : List (RuleReconstructor × Name) := []
  /-- The local context of the top level: the problem's symbols and assertions, then one
      hypothesis per checked step. -/
  lctx : LocalContext := {}
  /-- The local context of the problem's symbols and assertions alone. -/
  baseLctx : LocalContext := {}
  localInsts : LocalInstances := {}
  /-- Nesting depth of subproofs (0 at the top level). -/
  depth : Nat := 0
  /-- Build a proof term instead of checking step by step: top-level steps keep their proofs
      (inlined into later steps) and trusted steps become goals, as in the cvc5 path. Used by the
      `alethe` tactic, where the kernel checks the closed goal once. -/
  term : Bool := false
  /-- In term mode, the proof of the top-level empty clause. -/
  refutation : Option Expr := none

abbrev AletheM := ReaderT (IO.Ref DState) ReconstructM

def getD : AletheM DState := do (← read).get
def modifyD (f : DState → DState) : AletheM Unit := do (← read).modify f

/-- Run a `ReconstructM` scoping combinator around an `AletheM` action. -/
def withScope (f : ∀ {α}, ReconstructM α → ReconstructM α) (k : AletheM α) : AletheM α :=
  fun ref => f (k ref)

def getPremise (id : String) : AletheM Premise := do
  match (← getD).steps[id]? with
  | some p => return p
  | none => throwError "unknown step or assumption '{id}'"

def registerPremise (p : Premise) : AletheM Unit := do
  if (← getD).steps.contains p.id then throwError "duplicate step id '{p.id}'"
  modifyD fun st => { st with steps := st.steps.insert p.id p }

def recordTrust (s : Step) (msg : String) : AletheM Unit := do
  trace[smt.alethe.step] "trusting {s.id} ({s.rule}): {msg}"
  -- `rare_rewrite` steps are counted per RARE rule
  let rule := match s.rule, s.args[0]? with
    | "rare_rewrite", some (Arg.str name) => s!"rare_rewrite:{name}"
    | rule, _ => rule
  modifyD fun st => { st with stats := { st.stats with
    trusted := st.stats.trusted.insert rule (st.stats.trusted.getD rule 0 + 1),
    failures := st.stats.failures.push (s.id, rule, msg) } }

def countChecked : AletheM Unit :=
  modifyD fun st => { st with stats := { st.stats with checked := st.stats.checked + 1 } }

def traceStep (s : Step) (r : Except Exception (Option Expr)) : AletheM MessageData :=
  return m!"{s.id} {s.rule} : {s.concl} " ++ match r with
    | .ok (some _) => m!"{checkEmoji}"
    | _ => m!"{bombEmoji}"

/-- Try the registered reconstructors on a step. `none` when no reconstructor handled it or the
    reconstruction failed (recorded as trusted). -/
def reconstructStep (s : Step) : AletheM (Option Expr) := withTraceNode `smt.alethe.step (traceStep s) do
  if s.rule == "hole" then
    modifyD fun st => { st with stats := { st.stats with holes := st.stats.holes + 1 } }
    recordTrust s "hole"
    return none
  let st ← getD
  let r ← try
      let mut r := none
      for (rc, _) in st.reconstructors do
        if let some e ← rc s then
          r := some e
          break
      pure (Except.ok r)
    catch ex => pure (Except.error (← ex.toMessageData.toString))
  match r with
  | .ok (some e) => return some e
  | .ok none => recordTrust s "no reconstructor"; return none
  | .error msg => recordTrust s msg; return none

/-- Check `v : s.concl` in the kernel. The local context handed to the kernel holds the problem's
    symbols and assertions plus only the step hypotheses `v` mentions: the kernel's cost per call
    must not grow with the number of steps checked so far. -/
def kernelCheck (s : Step) (v : Expr) : AletheM Bool := do
  if !smt.alethe.kernel.get (← getOptions) then return true
  let st ← getD
  let t₀ ← IO.monoMsNow
  let v ← instantiateMVars v
  let e := mkApp2 (mkConst ``id [.zero]) s.concl v
  let mut lctx := st.baseLctx
  let mut n : Nat := 0
  for fvarId in (collectFVars {} e).fvarSet.toList do
    if !lctx.contains fvarId then
      if let some d := st.lctx.find? fvarId then
        lctx := lctx.addDecl d
        n := n + 1
  let env ← getEnv
  let r ← IO.lazyPure fun _ => Kernel.check env lctx e
  let t₁ ← IO.monoMsNow
  trace[smt.alethe.step] "kernel {s.id}: size {e.sizeWithoutSharing} depth {e.approxDepth} hyps {n} ms {t₁ - t₀}"
  modifyD fun st => { st with stats := { st.stats with kernelMs := st.stats.kernelMs + (t₁ - t₀) } }
  match r with
  | .ok _ => return true
  | .error ex =>
    recordTrust s s!"kernel: {← (ex.toMessageData (← getOptions)).toString}"
    return false

/-- Add a top-level step as a hypothesis of the local context. -/
def addHypothesis (s : Step) : AletheM Expr := do
  let fvarId ← mkFreshFVarId
  modifyD fun st => { st with
    lctx := st.lctx.mkLocalDecl fvarId (Name.mkSimple s.id) s.concl .default }
  return .fvar fvarId

/-- Turn the outcome of `reconstructStep` into the step's proof. At the top level the proof is
    checked by the kernel and the step becomes a hypothesis; inside a subproof the proof is kept
    (a trusted step becomes `sorry`). -/
def concludeStep (s : Step) (e? : Option Expr) : AletheM Expr := do
  let st ← getD
  if st.depth == 0 && st.term then
    if s.lits.isEmpty then
      modifyD fun st => { st with stats := { st.stats with emptyClause := true } }
    match e? with
    | some e =>
      -- the proof must be closed over the base context: a local hypothesis of a subproof or of a
      -- reconstructor that escaped would make the final term ill-formed
      let e ← instantiateMVars e
      let escaped := (collectFVars {} e).fvarSet.toList.filter fun fv => !st.baseLctx.contains fv
      if !escaped.isEmpty then
        let lctx ← getLCtx
        let names := escaped.map fun fv => match lctx.find? fv with
          | some d => d.userName.toString
          | none => toString fv.name
        recordTrust s s!"proof mentions local variables outside the problem's context: {names}"
        let e ← addTrustWith s.concl m!"Alethe step {s.id} ({s.rule})"
        if s.lits.isEmpty then modifyD fun st => { st with refutation := some e }
        return e
      else
        countChecked
        if s.lits.isEmpty then modifyD fun st => { st with refutation := some e }
        return e
    | none =>
      let e ← addTrustWith s.concl m!"Alethe step {s.id} ({s.rule})"
      if s.lits.isEmpty then modifyD fun st => { st with refutation := some e }
      return e
  else if st.depth == 0 then
    if let some e := e? then
      if ← kernelCheck s e then
        countChecked
    if s.lits.isEmpty then
      modifyD fun st => { st with stats := { st.stats with emptyClause := true } }
    addHypothesis s
  else
    match e? with
    | some e =>
      if smt.alethe.checkInner.get (← getOptions) then
        let ok ← try
            let e ← instantiateMVars e
            Meta.check e
            Meta.isDefEq (← Meta.inferType e) s.concl
          catch ex =>
            recordTrust s s!"inner check: {← ex.toMessageData.toString}"
            pure true
        if !ok then recordTrust s "inner check: type mismatch"
      countChecked
      return e
    | none => Meta.mkSorry s.concl false

def mkStep (d : StepData cvc5.Term) (anchor : Option AnchorCtx := none) : AletheM Step := do
  let premises ← d.premises.mapM getPremise
  let discharge ← d.discharge.mapM getPremise
  let concl ← mkClause d.cl
  return { id := d.id, rule := d.rule, lits := d.cl, concl, premises, args := d.args, discharge,
           anchor }

/-- Reconstruct a step command and register it. -/
def runStepData (d : StepData cvc5.Term) : AletheM Unit := do
  let every := smt.alethe.progress.get (← getOptions)
  if every > 0 then
    let n := (← getD).steps.size
    if n % every == 0 then
      progressLine s!"[alethe] step {n}: {d.id} ({d.rule}, {d.cl.size} literals) at {← IO.monoMsNow} ms"
  let t₀ ← IO.monoMsNow
  let s ← mkStep d
  let e ← concludeStep s (← reconstructStep s)
  registerPremise { id := d.id, lits := d.cl, concl := s.concl, proof := e }
  if every > 0 then
    let dt := (← IO.monoMsNow) - t₀
    if dt ≥ 200 then
      progressLine s!"[alethe] slow step {d.id} ({d.rule}, {d.cl.size} literals, {d.premises.size} premises): {dt} ms"

/-- A top-level `assume`: bind it to the assertion with the same term. A reflexive equality is
    accepted without an assertion: it is how a `define-fun` of the problem surfaces once the
    defined symbol has been expanded on both sides (cvc5 asserts definitions as equations). -/
def runAssume (id : String) (t : cvc5.Term) : AletheM Unit := do
  if smt.alethe.progress.get (← getOptions) > 0 then
    progressLine s!"[alethe] assume {id}"
  let st ← getD
  match st.asserts.find? (·.1 == t) with
  | some (_, p, h) => registerPremise { id, lits := #[t], concl := p, proof := h }
  | none =>
    let p ← reconstructTerm t
    if t.getKind! == .EQUAL && t[0]! == t[1]! then
      let h ← mkEqRefl t[0]!
      registerPremise { id, lits := #[t], concl := p, proof := h }
      return
    match ← findAssumWithType? p with
    | some h => registerPremise { id, lits := #[t], concl := p, proof := h }
    | none =>
      -- the same assertion up to representation (e.g. `(to_real 0)` in the problem, `0.0` in the
      -- proof): keep the proof's view of the term, the kernel unfolds the difference
      for (_, ap, h) in st.asserts do
        if ← Meta.isDefEq p ap then
          registerPremise { id, lits := #[t], concl := p, proof := h }
          return
      throwError "assumption '{id}' is not an assertion of the problem:\n  {t}"

/-- Run `k` in the top-level local context (the problem's symbols and the steps so far). -/
def withTopContext (k : AletheM α) : AletheM α := do
  let st ← getD
  withScope (Meta.withLCtx st.lctx st.localInsts) k

mutual

/-- Run the commands of a (sub)proof in order. At the top level each command runs in the local
    context extended with the steps checked so far. -/
partial def runCommands (cmds : Array (Command cvc5.Term)) : AletheM Unit := do
  for c in cmds do
    let top := (← getD).depth == 0
    let run (k : AletheM Unit) : AletheM Unit := if top then withTopContext k else k
    match c with
    | .assume id t => run (runAssume id t)
    | .step d => run (runStepData d)
    | .anchor id args body close => run (runAnchor id args body close)
    | .raw _ => pure ()

/-- Run a subproof: introduce its variables and assumptions as local hypotheses, run its body,
    then reconstruct the closing step with the subproof's context. -/
partial def runAnchor (_id : String) (args : Array (Arg cvc5.Term)) (body : Array (Command cvc5.Term))
    (close : StepData cvc5.Term) : AletheM Unit := do
  -- leading assumptions of the block
  let isAssume : Command cvc5.Term → Bool | .assume .. => true | _ => false
  let assumes := body.takeWhile isAssume
  let rest := body.extract assumes.size body.size
  let (s, e?) ← withScope (fun k => withNewTermCache (withNewProofCache k)) do
    withVars args 0 {} fun ctx => do
      let ds ← assumes.mapM fun
        | .assume aid t => do
          let p : Expr ← reconstructTerm t
          return (aid, t, p)
        | _ => unreachable!
      let decls := ds.map fun (aid, _, p) => (Name.mkSimple aid, fun (_ : Array Expr) => pure p)
      Meta.withLocalDeclsD decls fun hs => do
        let mut assums := #[]
        for (aid, t, p) in ds, h in hs do
          let pr : Premise := { id := aid, lits := #[t], concl := p, proof := h }
          registerPremise pr
          assums := assums.push pr
        withScope (withAssums hs) do
          modifyD fun st => { st with depth := st.depth + 1 }
          runCommands rest
          let last ← match rest.back? with
            | some (.step d) => some <$> getPremise d.id
            | some (.anchor cid ..) => some <$> getPremise cid
            | _ => pure none
          modifyD fun st => { st with depth := st.depth - 1 }
          -- the closing step is reconstructed inside the subproof's context (its proof abstracts
          -- over the local hypotheses) but concluded at the enclosing level
          let s ← mkStep close (anchor := some { ctx with assums, last })
          let e? ← reconstructStep s
          return (s, e?)
  let e ← concludeStep s e?
  registerPremise { id := close.id, lits := close.cl, concl := s.concl, proof := e }
where
  /-- Introduce the anchor's variables one by one, extending `userNames` with their cvc5 symbols. -/
  withVars {α} [Inhabited α] (args : Array (Arg cvc5.Term)) (i : Nat) (ctx : AnchorCtx)
      (k : AnchorCtx → AletheM α) : AletheM α := do
    if h : i < args.size then
      match args[i] with
      | .binder x _ c =>
        let ty ← reconstructSort c.getSort!
        Meta.withLocalDeclD (Name.mkSimple x) ty fun fv =>
          withScope (fun k => withReader (fun r => { r with userNames := r.userNames.insert c.getSymbol! fv }) (withAssums #[fv] k)) do
            withVars args (i + 1) { ctx with vars := ctx.vars.push (x, c, fv) } k
      | .assign x c t =>
        -- `x := t`: inside the subproof `x` is definitionally `t`, so `refl` steps relating them and
        -- the closing step's substitution are justified by unfolding
        let ty ← reconstructSort c.getSort!
        let te ← reconstructTerm t
        Meta.withLetDecl (Name.mkSimple x) ty te fun fv =>
          withScope (fun k => withReader (fun r => { r with userNames := r.userNames.insert c.getSymbol! fv }) k) do
            withVars args (i + 1) { ctx with assigns := ctx.assigns.push (x, c, fv, t, te) } k
      | _ => withVars args (i + 1) ctx k
    else
      k ctx

end

structure ProofResult where
  /-- The statement `¬ andN [a₁, …, aₙ]` over the problem's assertions. -/
  type : Expr
  /-- The assertions `a₁, …, aₙ`. -/
  asserts : List Expr
  /-- In term mode, the proof of `type` (with the trusted steps as metavariables). -/
  proof : Option Expr
  stats : Stats
deriving Inhabited

/-- Check a realized proof step by step. Returns the statement `¬ andN [a₁, …, aₙ]` over the
    problem's assertions (for reporting; it is established iff `stats.valid`) and the statistics.
    With `term`, no step is checked on its own; instead the proof term of the statement is
    returned (its trusted steps are the `skippedGoals` of the state). -/
def reconstructProof (r : Realized) (term := false) : ReconstructM ProofResult := do
  let asserts := r.problem.asserts
  let as ← asserts.mapM fun t => do
    let p : Q(Prop) ← reconstructTerm t
    return p
  if smt.alethe.progress.get (← getOptions) > 0 then
    progressLine s!"[alethe] {as.size} assertions reconstructed"
  let decls := as.mapIdx fun i p => (Name.num `a i, fun (_ : Array Expr) => pure p)
  let rs ← getReconstructors ``RuleReconstructor RuleReconstructor
  Meta.withLocalDeclsD decls fun hs => withAssums hs do
    let lctx ← getLCtx
    let ref ← IO.mkRef { asserts := asserts.zip (as.zip hs) |>.map fun (t, p, h) => (t, p, h),
                         reconstructors := rs, lctx, baseLctx := lctx,
                         localInsts := ← Meta.getLocalInstances, term : DState }
    runCommands r.proof.cmds ref
    let st ← ref.get
    let ps := listExpr as.toList (mkSort .zero)
    let type := mkApp (mkConst ``Not) (mkApp (mkConst ``andN) ps)
    let mut proof := none
    if term then
      -- the top-level empty clause's proof, `False` under the assertion hypotheses (an empty
      -- clause inside a subproof depends on that subproof's assumptions and is not it)
      if let some r := st.refutation then
        let f ← Meta.mkLambdaFVars hs (← instantiateMVars r)   -- impliesN as False
        let hp ← Meta.withLocalDeclD `h (mkApp (mkConst ``andN) ps) fun h =>
          Meta.mkLambdaFVars #[h] (mkAppN (mkConst ``Builtin.scopes) #[ps, mkConst ``False, f, h])
        proof := some hp
    return { type, asserts := as.toList, proof, stats := st.stats }

end Smt.Alethe
