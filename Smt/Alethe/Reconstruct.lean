/-
Copyright (c) 2021-2026 by the authors listed in the file AUTHORS and their
institutional affiliations. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Haniel Barbosa
-/

module

public import Smt.Alethe.Basic
public meta import Smt.Alethe.Basic
public import Smt.Alethe.Polyeq
public meta import Smt.Alethe.Polyeq
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

register_option smt.alethe.batch : Nat := {
  defValue := 1
  descr := "top-level steps per kernel call (1: one call per step; 0: no bound on the number of \
steps, so the whole proof unless a size budget applies)"
}

register_option smt.alethe.batchSize : Nat := {
  defValue := 0
  descr := "send a batch to the kernel once the proofs it holds reach this many term nodes \
(0: no size budget)"
}

register_option smt.alethe.jobs : Nat := {
  defValue := 1
  descr := "kernel calls to run concurrently (1: sequential); each call in flight holds its \
proofs in memory"
}

register_option smt.alethe.stats : Bool := {
  defValue := false
  descr := "record what every step cost, as carcara's `bench --dump-to-csv` does (one row per \
step); `#check_alethe … csv \"<dir>\"` turns it on and writes the files"
}

/-- What one step cost, in nanoseconds: a row of `steps.csv`. -/
structure StepTiming where
  id : String
  /-- The rule the step is counted under (`Step.countedRule`). -/
  rule : String
  /-- Nesting depth of the step (0 at the top level). -/
  depth : Nat := 0
  /-- Building the clause, running the reconstructors and concluding the step, with the kernel's
      time taken out. -/
  reconstructNs : Nat := 0
  /-- The kernel's time for the step. Exact under the default `smt.alethe.batch 1`, one call per
      step; a larger batch's time is split evenly over the steps the call covers. -/
  kernelNs : Nat := 0
  /-- Whether the step was trusted rather than checked. -/
  trusted : Bool := false
deriving Inhabited

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
  /-- Nanoseconds spent in the kernel, summed over the calls: with `smt.alethe.jobs > 1` they run
      concurrently and the sum exceeds the time the checker spent waiting for them. -/
  kernelNs : Nat := 0
  /-- Nanoseconds spent binding the proof's assumptions to the problem's assertions, and the part
      of that spent comparing terms with `polyeq` (carcara's `assume` and `polyeq` columns). -/
  assumeNs : Nat := 0
  polyeqNs : Nat := 0
  /-- Nanoseconds spent before the first command: reconstructing the problem's assertions and
      opening the context they are hypotheses of. Belongs to no step, and on a problem with many
      assertions it is the bulk of what the per-step records do not account for. -/
  setupNs : Nat := 0
  /-- One record per step, in proof order; empty unless `smt.alethe.stats` is set. -/
  steps : Array StepTiming := #[]
  /-- Whether some kernel call covered more than one step, so that the per-step kernel times in
      `steps` are a batch's time split evenly rather than the step's own. -/
  kernelSplit : Bool := false
deriving Inhabited

/-- Milliseconds spent in the kernel. -/
def Stats.kernelMs (st : Stats) : Nat := st.kernelNs / 1000000

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

/-- A checked-by-the-kernel-later step: the hypothesis later steps use for it, its conclusion and
    proof, and its id and rule for reporting. -/
structure PendingStep where
  fvar : FVarId
  concl : Expr
  proof : Expr
  id : String
  rule : String
deriving Inhabited

/-- A kernel call in flight: the steps it covers, the context it runs in, and its task (the
    inferred type or the kernel's exception, and the nanoseconds it took). -/
structure KernelJob where
  steps : Array PendingStep
  lctx : LocalContext
  task : Task (Except Kernel.Exception Expr × Nat)

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
  /-- Top-level steps whose proofs have not been sent to the kernel yet (see `flushBatch`). -/
  pending : Array PendingStep := #[]
  /-- Term nodes held by `pending`, when a size budget is set. -/
  pendingSize : Nat := 0
  /-- The nodes already counted for the batch: a step's proof shares most of its formulas with the
      steps around it, so the budget must count each node once and traverse it once. -/
  pendingSeen : ExprSet := {}
  /-- Kernel calls running concurrently, oldest first. -/
  inflight : Array KernelJob := #[]
  /-- Whether to record `Stats.steps` (`smt.alethe.stats`), read once at the start of the run. -/
  collectSteps : Bool := false
  /-- Step id to its index in `Stats.steps`, so that a kernel call and a trust decision — both of
      which happen after the step was recorded — can find its record. -/
  timingIndex : Std.HashMap String Nat := {}

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

/-- The rule a step is counted under: `rare_rewrite` steps are counted per RARE rule. -/
def countedRule (rule : String) (args : Array (Arg cvc5.Term)) : String :=
  match rule, args[0]? with
  | "rare_rewrite", some (Arg.str name) => s!"rare_rewrite:{name}"
  | rule, _ => rule

def Step.countedRule (s : Step) : String := _root_.Smt.Alethe.countedRule s.rule s.args

/-- Open the record of a step about to be reconstructed, returning its index in `Stats.steps`
    (meaningless, and unused, when the records are not being collected). -/
def beginStepTiming (id rule : String) : AletheM Nat := do
  let st ← getD
  if !st.collectSteps then return 0
  let i := st.stats.steps.size
  modifyD fun st => { st with
    stats := { st.stats with steps := st.stats.steps.push { id, rule, depth := st.depth } },
    timingIndex := st.timingIndex.insert id i }
  return i

/-- Close the record opened by `beginStepTiming`: `totalNs` is the wall time of the whole step and
    `kernel₀` the kernel counter as it stood when the step began, so that a kernel call made while
    concluding the step (a batch flush) is not counted twice. -/
def endStepTiming (i totalNs kernel₀ : Nat) : AletheM Unit := do
  let st ← getD
  if !st.collectSteps then return
  let ownNs := totalNs - (st.stats.kernelNs - kernel₀)
  modifyD fun st => { st with stats := { st.stats with
    steps := st.stats.steps.modify i fun t => { t with reconstructNs := ownNs } } }

/-- Attribute a kernel call's time to the steps it covered, evenly. -/
def attributeKernel (steps : Array PendingStep) (ns : Nat) : AletheM Unit := do
  let st ← getD
  if !st.collectSteps || steps.isEmpty then return
  let share := ns / steps.size
  modifyD fun st => Id.run do
    let mut ts := st.stats.steps
    for p in steps do
      if let some i := st.timingIndex[p.id]? then
        ts := ts.modify i fun t => { t with kernelNs := t.kernelNs + share }
    return { st with stats := { st.stats with
      steps := ts, kernelSplit := st.stats.kernelSplit || steps.size > 1 } }

def recordTrustRule (id rule : String) (msg : String) : AletheM Unit := do
  trace[smt.alethe.step] "trusting {id} ({rule}): {msg}"
  modifyD fun st => { st with stats := { st.stats with
    trusted := st.stats.trusted.insert rule (st.stats.trusted.getD rule 0 + 1),
    failures := st.stats.failures.push (id, rule, msg) } }
  let st ← getD
  if st.collectSteps then
    if let some i := st.timingIndex[id]? then
      modifyD fun st => { st with stats := { st.stats with
        steps := st.stats.steps.modify i fun t => { t with trusted := true } } }

def recordTrust (s : Step) (msg : String) : AletheM Unit :=
  recordTrustRule s.id s.countedRule msg

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
      let every := smt.alethe.progress.get (← getOptions)
      for (rc, name) in st.reconstructors do
        let t₀ ← IO.monoMsNow
        let e? ← rc s
        if every > 0 then
          let dt := (← IO.monoMsNow) - t₀
          if dt ≥ 200 then
            progressLine s!"[alethe] slow reconstructor {name} on {s.id} ({s.rule}): {dt} ms"
        if let some e := e? then
          r := some e
          break
      pure (Except.ok r)
    catch ex => pure (Except.error (← ex.toMessageData.toString))
  match r with
  | .ok (some e) => return some e
  | .ok none => recordTrust s "no reconstructor"; return none
  | .error msg => recordTrust s msg; return none

/-- The number of distinct nodes of `e`: what a pending proof costs in memory, up to sharing. -/
private partial def sharedSizeAux (e : Expr) : StateM ExprSet Nat := do
  if (← get).contains e then return 0
  modify (·.insert e)
  match e with
  | .app f a => return 1 + (← sharedSizeAux f) + (← sharedSizeAux a)
  | .lam _ d b _ | .forallE _ d b _ => return 1 + (← sharedSizeAux d) + (← sharedSizeAux b)
  | .letE _ t v b _ => return 1 + (← sharedSizeAux t) + (← sharedSizeAux v) + (← sharedSizeAux b)
  | .mdata _ b => return 1 + (← sharedSizeAux b)
  | .proj _ _ b => return 1 + (← sharedSizeAux b)
  | _ => return 1

/-- The nodes of `e` that `seen` does not already have, and `seen` extended with them. -/
def sharedSizeIncr (e : Expr) (seen : ExprSet) : Nat × ExprSet := (sharedSizeAux e).run seen

/-- The local context for a kernel call: the problem's symbols and assertions plus only the step
    hypotheses `e` mentions, so that the cost of a call does not grow with the number of steps
    checked so far. -/
def kernelLCtx (e : Expr) : AletheM LocalContext := do
  let st ← getD
  let mut lctx := st.baseLctx
  for fvarId in (collectFVars {} e).fvarSet.toList do
    if !lctx.contains fvarId then
      if let some d := st.lctx.find? fvarId then
        lctx := lctx.addDecl d
  return lctx

/-- The term of a batch of steps: `(fun h₁ : c₁ => … (fun hₙ : cₙ => trivial) eₙ …) e₁`. The
    kernel accepts it exactly when every `eᵢ` proves `cᵢ` under the hypotheses of the steps before
    it, which is what checking the steps one by one asks; the binders keep those hypotheses opaque,
    and one call shares its inference cache over the whole batch. -/
def batchTerm (ps : Array PendingStep) : Expr := Id.run do
  -- each proof is abstracted once, over the hypotheses of the steps before it in the batch
  -- (abstracting the partial term instead would rebuild it at every step); `Expr.abstract` scans
  -- its array once per occurrence, so a batch is best bounded by its number of steps as well
  let mut abstracted : Array Expr := #[]
  let mut earlier : Array Expr := #[]
  for p in ps do
    abstracted := abstracted.push (p.proof.abstract earlier)
    earlier := earlier.push (.fvar p.fvar)
  -- the loose bound variables of an abstracted proof are exactly the binders it sits under
  let mut body := mkConst ``True.intro
  for i in [0:ps.size] do
    let j := ps.size - 1 - i
    body := mkApp (Expr.lam (Name.mkSimple ps[j]!.id) ps[j]!.concl body .default) abstracted[j]!
  return body

/-- The first line of a message: kernel errors print the whole offending term after it, which is
    large and full of unstable fvar names, so only the headline is recorded as the trust reason. -/
def firstLine (s : String) : String := (s.splitOn "\n").headD s

/-- Record the outcome of one kernel call. A rejected batch of more than one step is re-checked
    step by step, so that what is trusted is what the kernel actually rejected. -/
def recordBatch (steps : Array PendingStep) (r : Except Kernel.Exception Expr) (ns : Nat) :
    AletheM Unit := do
  modifyD fun st => { st with stats := { st.stats with kernelNs := st.stats.kernelNs + ns } }
  attributeKernel steps ns
  match r with
  | .ok _ =>
    modifyD fun st => { st with stats := { st.stats with checked := st.stats.checked + steps.size } }
  | .error ex =>
    if h : steps.size == 1 then
      let p := steps[0]'(by simp at h; omega)
      recordTrustRule p.id p.rule s!"kernel: {firstLine (← (ex.toMessageData (← getOptions)).toString)}"
    else
      let env ← getEnv
      for p in steps do
        let e := batchTerm #[p]
        let lctx ← kernelLCtx e
        match ← IO.lazyPure fun _ => Kernel.check env lctx e with
        | .ok _ => countChecked
        | .error ex =>
          recordTrustRule p.id p.rule s!"kernel: {firstLine (← (ex.toMessageData (← getOptions)).toString)}"

/-- Wait for the oldest kernel call in flight and record its outcome. -/
def joinOne : AletheM Unit := do
  let st ← getD
  if h : 0 < st.inflight.size then
    let job := st.inflight[0]
    modifyD fun st => { st with inflight := st.inflight.extract 1 st.inflight.size }
    let (r, ns) ← IO.wait job.task
    recordBatch job.steps r ns

/-- Wait until at most `n` kernel calls are in flight. -/
partial def drainTo (n : Nat) : AletheM Unit := do
  if (← getD).inflight.size ≤ n then return
  joinOne
  drainTo n

/-- `IO.lazyPure` for `BaseIO`: an opaque call that evaluates `fn ()` where it stands. A plain
    `let` is evaluated at its use site instead, which would leave the clock reads around a kernel
    call measuring nothing. -/
@[noinline] def lazyPure {α : Type} (fn : Unit → α) : BaseIO α :=
  pure (fn ())

/-- Send the pending steps to the kernel as a single call (synchronously, or as a task when
    `smt.alethe.jobs` allows more than one call in flight). -/
def flushBatch : AletheM Unit := do
  let st ← getD
  if st.pending.isEmpty then return
  modifyD fun st => { st with pending := #[], pendingSize := 0, pendingSeen := {} }
  let steps := st.pending
  let e := batchTerm steps
  let lctx ← kernelLCtx e
  let env ← getEnv
  let jobs := smt.alethe.jobs.get (← getOptions)
  if jobs ≤ 1 then
    let t₀ ← IO.monoNanosNow
    let r ← IO.lazyPure fun _ => Kernel.check env lctx e
    let t₁ ← IO.monoNanosNow
    trace[smt.alethe.step] "kernel batch of {steps.size} ending at {steps.back!.id}: \
{(t₁ - t₀) / 1000000} ms"
    recordBatch steps r (t₁ - t₀)
  else
    drainTo (jobs - 1)
    let task ← (BaseIO.asTask do
      let t₀ ← IO.monoNanosNow
      let r ← lazyPure fun _ => Kernel.check env lctx e
      let t₁ ← IO.monoNanosNow
      return (r, t₁ - t₀)).toIO
    modifyD fun st => { st with inflight := st.inflight.push { steps, lctx, task } }

/-- Wait for every kernel call in flight. -/
def joinAll : AletheM Unit := drainTo 0

/-- Whether the pending batch has reached the step count or size budget. -/
def batchFull : AletheM Bool := do
  let st ← getD
  let opts ← getOptions
  let maxSteps := smt.alethe.batch.get opts
  let maxSize := smt.alethe.batchSize.get opts
  return (maxSteps != 0 && st.pending.size ≥ maxSteps)
      || (maxSize != 0 && st.pendingSize ≥ maxSize)

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
        -- the premise a later step sees must have the type the proof states for it, as the step
        -- hypothesis of the step-by-step mode does: a reconstructor that reads a premise's type
        -- (congruence over an n-ary operator, for one) would otherwise see whatever type the
        -- proof term happens to infer to, which is only definitionally the stated one
        let e ← Meta.mkExpectedTypeHint e s.concl
        if s.lits.isEmpty then modifyD fun st => { st with refutation := some e }
        return e
    | none =>
      let e ← addTrustWith s.concl m!"Alethe step {s.id} ({s.rule})"
      if s.lits.isEmpty then modifyD fun st => { st with refutation := some e }
      return e
  else if st.depth == 0 then
    -- the hypothesis is introduced first: later steps refer to it, and the kernel sees the step's
    -- proof only when its batch is flushed
    let h ← addHypothesis s
    if let some e := e? then
      if !smt.alethe.kernel.get (← getOptions) then
        countChecked
      else
        let e ← instantiateMVars e
        let budget := smt.alethe.batchSize.get (← getOptions)
        modifyD fun st =>
          let (sz, seen) := if budget == 0 then (0, st.pendingSeen) else sharedSizeIncr e st.pendingSeen
          { st with
            pending := st.pending.push
              { fvar := h.fvarId!, concl := s.concl, proof := e, id := s.id, rule := s.countedRule },
            pendingSize := st.pendingSize + sz, pendingSeen := seen }
        if ← batchFull then flushBatch
    if s.lits.isEmpty then
      modifyD fun st => { st with stats := { st.stats with emptyClause := true } }
    return h
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
  let t₀ ← IO.monoNanosNow
  let k₀ := (← getD).stats.kernelNs
  let i ← beginStepTiming d.id (countedRule d.rule d.args)
  let s ← mkStep d
  let t₁ ← IO.monoNanosNow
  let e ← reconstructStep s
  let t₂ ← IO.monoNanosNow
  let e ← concludeStep s e
  registerPremise { id := d.id, lits := d.cl, concl := s.concl, proof := e }
  let t₃ ← IO.monoNanosNow
  endStepTiming i (t₃ - t₀) k₀
  if every > 0 then
    let ms (a b : Nat) := (b - a) / 1000000
    if ms t₀ t₃ ≥ 200 then
      progressLine s!"[alethe] slow step {d.id} ({d.rule}, {d.cl.size} literals, {d.premises.size} premises): {ms t₀ t₃} ms (mkStep {ms t₀ t₁}, reconstruct {ms t₁ t₂}, conclude {ms t₂ t₃})"

/-- A top-level `assume`: bind it to the assertion with the same term. A reflexive equality is
    accepted without an assertion: it is how a `define-fun` of the problem surfaces once the
    defined symbol has been expanded on both sides (cvc5 asserts definitions as equations). -/
def runAssumeCore (id : String) (t : cvc5.Term) : AletheM Unit := do
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
      -- the same assertion up to representation, as Carcara accepts it (`polyeq`): equalities in
      -- either orientation, bound variables renamed, numerals spelled differently (cvc5 prints
      -- the problem's `0.0` as `0/1`). Keep the proof's view of the term, and prove it from the
      -- assertion's
      let t₀ ← IO.monoNanosNow
      let matched := st.asserts.find? fun (ta, _, _) => polyeq t ta
      let t₁ ← IO.monoNanosNow
      modifyD fun st => { st with stats := { st.stats with
        polyeqNs := st.stats.polyeqNs + (t₁ - t₀) } }
      if let some (ta, ap, h) := matched then
        let some he ← polyeqProof? ap p
          | throwError "assumption '{id}' is the assertion {ta} up to representation, but the \
              two propositions could not be reconciled:\n  {ap}\n  {p}"
        registerPremise { id, lits := #[t], concl := p, proof := ← Meta.mkEqMP he h }
        return
      -- last resort: definitionally equal propositions, the kernel unfolds the difference
      for (_, ap, h) in st.asserts do
        if ← Meta.isDefEq p ap then
          registerPremise { id, lits := #[t], concl := p, proof := h }
          return
      throwError "assumption '{id}' is not an assertion of the problem:\n  {t}"

/-- Bind an assumption, timing it: carcara reports the share of checking spent on `assume`, and
    within it the share spent comparing terms with `polyeq`. -/
def runAssume (id : String) (t : cvc5.Term) : AletheM Unit := do
  let t₀ ← IO.monoNanosNow
  runAssumeCore id t
  let t₁ ← IO.monoNanosNow
  modifyD fun st => { st with stats := { st.stats with
    assumeNs := st.stats.assumeNs + (t₁ - t₀) } }

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
  -- the block's own cost — its variables, its assumptions, the contexts it opens — is the closing
  -- step's, not the body's; the body's steps are timed one by one
  let tA ← IO.monoNanosNow
  let (s, e?, i, t₀, k₀, setup) ← withScope (fun k => withNewTermCache (withNewProofCache k)) do
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
          let setup := (← IO.monoNanosNow) - tA
          runCommands rest
          let last ← match rest.back? with
            | some (.step d) => some <$> getPremise d.id
            | some (.anchor cid ..) => some <$> getPremise cid
            | _ => pure none
          modifyD fun st => { st with depth := st.depth - 1 }
          -- the closing step is reconstructed inside the subproof's context (its proof abstracts
          -- over the local hypotheses) but concluded at the enclosing level; only its own work is
          -- timed, the body's steps have records of their own
          let t₀ ← IO.monoNanosNow
          let k₀ := (← getD).stats.kernelNs
          let i ← beginStepTiming close.id (countedRule close.rule close.args)
          let s ← mkStep close (anchor := some { ctx with assums, last })
          let e? ← reconstructStep s
          return (s, e?, i, t₀, k₀, setup)
  let e ← concludeStep s e?
  registerPremise { id := close.id, lits := close.cl, concl := s.concl, proof := e }
  endStepTiming i (setup + (← IO.monoNanosNow) - t₀) k₀
where
  /-- Introduce the anchor's variables, extending `userNames` with their cvc5 symbols: first every
      kept variable `(x S)` as a free binder, then every substitution `(:= x t)` as a `let`.

      The two phases matter for veriT's chained renamings, `((y S) (z S) (:= x y) (:= y z))`: `y`
      is declared kept and then substituted by a *later* kept variable `z`. Inside the block `y`
      *is* `z` (veriT states `(= y z)` by `refl`, and Carcara accepts it), so `y` must be a `let`
      bound to `z` — which can only be built once `z` exists. The let shadows the kept binder for
      the block; the binder itself stays in `vars`, where the closing `bind` looks the conclusion's
      quantifier variable up. -/
  withVars {α} [Inhabited α] (args : Array (Arg cvc5.Term)) (i : Nat) (ctx : AnchorCtx)
      (k : AnchorCtx → AletheM α) : AletheM α := do
    if i == 0 then
      -- phase one: the kept variables, in anchor order
      let binders := args.filterMap fun | .binder x s c => some (x, s, c) | _ => none
      -- Phase two binds the substitutions as lets. A substitution of one of this block's kept
      -- variables (`(:= y z)` after `(y S)`) must come first: another substitution's value may
      -- be that very `y` (`(:= x y)`), and it has to capture the let `y := z`, not the binder,
      -- or zeta-reducing `x` later yields the binder where `z` is due. The lets of the kept
      -- variables depend only on binders, so they can always go first, in anchor order.
      let kept := args.filterMap fun | .binder _ _ c => some c | _ => none
      let isKept : Arg cvc5.Term → Bool | .assign _ c _ => kept.contains c | _ => false
      let ordered := args.filter isKept ++ args.filter (fun a => !isKept a)
      -- a term reconstructed in phase one (a binder's own atom, cached under its symbol) must not
      -- survive into the block, or the block would keep seeing the binder where a let now stands
      withBinders binders 0 ctx fun ctx => withScope (fun k => withNewTermCache k) (withAssigns ordered 0 ctx k)
    else
      k ctx
  withBinders {α} [Inhabited α] (bs : Array (String × Sexp × cvc5.Term)) (i : Nat) (ctx : AnchorCtx)
      (k : AnchorCtx → AletheM α) : AletheM α := do
    if h : i < bs.size then
      let (x, _, c) := bs[i]
      let ty ← reconstructSort c.getSort!
      Meta.withLocalDeclD (Name.mkSimple c.getSymbol!) ty fun fv =>
        withScope (fun k => withReader (fun r => { r with userNames := r.userNames.insert c.getSymbol! fv }) (withAssums #[fv] k)) do
          withBinders bs (i + 1) { ctx with vars := ctx.vars.push (x, c, fv) } k
    else
      k ctx
  /-- Phase two: the substitutions, in anchor order, each a `let x := t`. A substitution of one of
      the block's own kept variables shadows that binder from here on. -/
  withAssigns {α} [Inhabited α] (args : Array (Arg cvc5.Term)) (i : Nat) (ctx : AnchorCtx)
      (k : AnchorCtx → AletheM α) : AletheM α := do
    if h : i < args.size then
      match args[i] with
      | .assign x c t =>
        -- `x := t`: inside the subproof `x` is definitionally `t`, so `refl` steps relating them
        -- and the closing step's substitution are justified by unfolding
        let ty ← reconstructSort c.getSort!
        let te ← reconstructTerm t
        -- named by its fresh cvc5 symbol, not the user name: an enclosing anchor may bind the
        -- same user name, and a resolution by local-context name would land on that binder
        Meta.withLetDecl (Name.mkSimple c.getSymbol!) ty te fun fv =>
          withScope (fun k => withReader (fun r => { r with userNames := r.userNames.insert c.getSymbol! fv }) k) do
            withAssigns args (i + 1) { ctx with assigns := ctx.assigns.push (x, c, fv, t, te) } k
      | _ => withAssigns args (i + 1) ctx k
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
  let t₀ ← IO.monoNanosNow
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
                         localInsts := ← Meta.getLocalInstances, term,
                         collectSteps := smt.alethe.stats.get (← getOptions) : DState }
    let setupNs := (← IO.monoNanosNow) - t₀
    ref.modify fun st => { st with stats := { st.stats with setupNs } }
    runCommands r.proof.cmds ref
    -- steps still waiting for the kernel, and calls still running
    flushBatch ref
    joinAll ref
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
