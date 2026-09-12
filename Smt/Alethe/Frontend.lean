/-
Copyright (c) 2021-2026 by the authors listed in the file AUTHORS and their
institutional affiliations. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Haniel Barbosa
-/

module

public import Smt.Alethe.Reconstruct
public meta import Smt.Alethe.Reconstruct
public import Smt.Reconstruct.UF
public meta import Smt.Reconstruct.UF

public meta section

/-!
# Checking an Alethe proof file

`checkAlethe` parses the problem and the proof, realizes them with cvc5's parser, closes the
reconstructed statement over the problem's sorts and symbols, and sends the theorem to the
kernel.
-/

namespace Smt.Alethe

open Lean Qq
open Smt.Reconstruct

structure CheckResult where
  /-- The statement that was checked (closed over the problem's symbols). -/
  type : Expr
  stats : Stats
  /-- Milliseconds spent in each phase. -/
  timings : Array (String × Nat)
  /-- The same, in nanoseconds. -/
  timingsNs : Array (String × Nat) := #[]
  /-- Nanoseconds spent reading and realizing the problem and the proof. -/
  parsingNs : Nat := 0
  /-- Nanoseconds spent reconstructing the steps and checking them in the kernel. -/
  checkingNs : Nat := 0
  /-- Nanoseconds of the whole run. -/
  totalNs : Nat := 0

def CheckResult.verdict (r : CheckResult) : String :=
  if r.stats.valid then "valid" else "holey"

def timed (label : String) (k : MetaM α) : StateT (Array (String × Nat)) MetaM α := do
  let t₀ ← IO.monoNanosNow
  let r ← k
  let t₁ ← IO.monoNanosNow
  modify (·.push (label, t₁ - t₀))
  return r

/-! ## Dumping the run to CSV

`#check_alethe … csv "<dir>"` writes `<dir>/runs.csv` and `<dir>/steps.csv`, the two files
carcara's `bench --dump-to-csv` produces, with carcara's columns in carcara's order so that one
analysis reads either checker's output. Times are nanoseconds throughout, as there too.

Both files carry extra trailing columns for what carcara has no counterpart for — the split of a
step between reconstruction and the kernel, and whether the step was trusted. A reader that goes
by column position (`rule` is field 1 and `time` field 2 of `steps.csv`) is unaffected by them.
-/

/-- `num / den` as carcara prints its ratio columns; `0` when nothing was measured. -/
private def csvRatio (num den : Nat) : String :=
  if den == 0 then "0" else toString (num.toFloat / den.toFloat)

/-- One row per step. `rule,time` come first, as in carcara's file; `time` is the step's whole
    cost, reconstruction and kernel together. -/
def writeStepsCsv (path : System.FilePath) (steps : Array StepTiming) : IO Unit :=
  IO.FS.withFile path .write fun h => do
    h.putStr "rule,time,reconstruct,kernel,depth,trusted,step_id\n"
    -- written in chunks: a proof has hundreds of thousands of steps, and neither one write per
    -- row nor one string for the whole file is reasonable
    let mut buf := ""
    let mut n := 0
    for t in steps do
      buf := buf ++ s!"{t.rule},{t.reconstructNs + t.kernelNs},{t.reconstructNs},{t.kernelNs},\
{t.depth},{if t.trusted then 1 else 0},{t.id}\n"
      n := n + 1
      if n % 4096 == 0 then
        h.putStr buf
        buf := ""
    unless buf.isEmpty do h.putStr buf

/-- The single row of this run. `elaboration` is always 0: the Carcara pass that elaborates the
    solver's proof is a separate process, and what it cost belongs to its own run.

    `checking` is the whole of it; the rows of `steps.csv` sum to less, the difference being
    `setup` (the problem's assertions), `assume` (binding the proof's assumptions to them) and the
    per-command bookkeeping between steps. -/
def writeRunsCsv (path : System.FilePath) (proofFile : String) (r : CheckResult) : IO Unit := do
  let st := r.stats
  let kernel := st.kernelNs
  let accounted := r.parsingNs + r.checkingNs
  IO.FS.writeFile path <|
    "proof_file,run_id,parsing,checking,elaboration,total_accounted_for,total,polyeq,\
polyeq_ratio,assume,assume_ratio,reconstruct,kernel,setup,steps,checked,trusted,holes,\
kernel_split\n" ++
    s!"{proofFile},0,{r.parsingNs},{r.checkingNs},0,{accounted},{r.totalNs},{st.polyeqNs},\
{csvRatio st.polyeqNs r.checkingNs},{st.assumeNs},{csvRatio st.assumeNs r.checkingNs},\
{r.checkingNs - kernel},{kernel},{st.setupNs},{st.steps.size},{st.checked},{st.numTrusted},\
{st.holes},{if st.kernelSplit then 1 else 0}\n"

/-- Write `runs.csv` and `steps.csv` into `dir`. -/
def writeCsv (dir : System.FilePath) (proofPath : System.FilePath) (r : CheckResult) : IO Unit := do
  IO.FS.createDirAll dir
  writeRunsCsv (dir / "runs.csv") proofPath.toString r
  writeStepsCsv (dir / "steps.csv") r.stats.steps

def parseSexps (what : String) (text : String) : MetaM (List Sexp) :=
  match Sexp.Parser.manySexps!.run text with
  | .ok s => return s
  | .error e => throwError "failed to parse {what}: {e}"

/-- Introduce the problem's uninterpreted sorts (with `Nonempty` instances) and symbols as local
    hypotheses, and run `k` with `userNames` mapping their symbols to the new fvars. -/
def withProblemSymbols [Inhabited α] (prob : Problem) (skip : Array String) (k : Array Expr → ReconstructM α) : ReconstructM α := do
  let sortDecls := prob.sorts.map fun s => (Name.mkSimple s.getSymbol!, fun (_ : Array Expr) => pure q(Type))
  Meta.withLocalDeclsD sortDecls fun ss => do
    let instDecls := ss.map fun s => (`inst, .instImplicit, fun (_ : Array Expr) => pure (mkApp (mkConst ``Nonempty [1]) s))
    Meta.withLocalDecls instDecls fun is => do
      let names := (prob.sorts.zip ss).foldl (fun m (s, e) => m.insert s.getSymbol! e) (← read).userNames
      withReader (fun r => { r with userNames := names }) do
        -- `define-fun`s are macro-expanded by cvc5's parser; only declared symbols get fvars
        let funs := prob.funs.filter fun f => f.getKind! == .CONSTANT && f.hasSymbol! && !skip.contains f.getSymbol!
        let funDecls ← funs.mapM fun f => do
          let ty ← reconstructSort f.getSort!
          return (Name.mkSimple f.getSymbol!, fun (_ : Array Expr) => pure ty)
        Meta.withLocalDeclsD funDecls fun fs => do
          let names := (funs.zip fs).foldl (fun m (f, e) => m.insert f.getSymbol! e) names
          withReader (fun r => { r with userNames := names }) do
            k (ss ++ is ++ fs)

/-- Bind each epsilon symbol `ε_S : (S → Prop) → S` to `Classical.epsilon`. -/
def withChoices (cs : List cvc5.Term) (k : ReconstructM α) : ReconstructM α := do
  match cs with
  | [] => k
  | c :: cs =>
    let (u, (α : Q(Sort u))) ← reconstructSortLevelAndSort c.getSort!.getFunctionCodomainSort!
    let inst : Q(Nonempty $α) ← Meta.synthInstance q(Nonempty $α)
    let e : Q(($α → Prop) → $α) := q(@Classical.epsilon $α $inst)
    withReader (fun r => { r with userNames := r.userNames.insert c.getSymbol! e }) (withChoices cs k)

/-- Check the Alethe proof in `proofPath` against the SMT-LIB problem in `problemPath`. With `term`, the whole proof is reconstructed as
    one term and sent to the kernel in a single call (the shape lean-cpc-checker uses for cvc5's
    proofs); otherwise each step is checked on its own in a minimal local context. -/
def checkAlethe (problemPath proofPath : System.FilePath) (native := false) (lax := false)
    (term := false) (csv : Option System.FilePath := none) : MetaM CheckResult := do
  let _ := lax
  -- a proof is one command with thousands of steps: no heartbeat budget
  -- the depth is raised through the options, not the context alone: `native` compiles its
  -- certificates, and the compiler reads the limit from there
  withOptions (fun o => smt.alethe.stats.set (maxRecDepth.set o 100000) csv.isSome) do
  withTheReader Core.Context (fun ctx => { ctx with maxHeartbeats := 0 }) do
  let start ← IO.monoNanosNow
  let (r, timings) ← (do
    let parsed ← timed "parse" do
      let problemText ← IO.FS.readFile problemPath
      let proofText ← IO.FS.readFile proofPath
      let problemCmds ← parseSexps "problem" problemText
      let proofSexps ← parseSexps "proof" proofText
      match Parser.parse problemCmds proofSexps with
      | .ok p => pure p
      | .error e => throwError "failed to parse the input: {e}"
    let realized ← timed "realize" do
      match ← cvc5.run (realize parsed) with
      | .ok r => pure r
      | .error e => throwError "cvc5 failed to parse the input: {e}"
    let ((type, value?), stats) ← timed "reconstruct" do
      let ctx : Reconstruct.Context := { native }
      -- symbols introduced by the proof (anchor variables, choice constants) are not the problem's
      let skip : Array String := realized.renamed.map (fun (x : String × String) => x.1)
        ++ realized.choices.map (fun (c : cvc5.Term) => c.getSymbol!)
      let ((type, value?, stats), _) ← (withProblemSymbols realized.problem skip fun xs => do
        if smt.alethe.progress.get (← getOptions) > 0 then
          progressLine s!"[alethe] {xs.size} problem symbols introduced"
        withChoices realized.choices.toList do
          let r ← reconstructProof realized (term := term)
          let type ← Meta.mkForallFVars xs r.type
          -- the trusted steps are metavariables of the term; `sorry` stands for them, as in
          -- lean-cpc-checker (they are already counted in the statistics)
          for mv in (← getThe Reconstruct.State).skippedGoals do
            unless ← mv.isAssigned do
              mv.assign (← Meta.mkSorry (← mv.getType) false)
          let value? ← match r.proof with
            | some v => some <$> Meta.mkLambdaFVars xs (← instantiateMVars v)
            | none => pure none
          return (type, value?, r.stats)).run ctx {}
      pure ((type, value?), stats)
    let mut stats := stats
    if let some value := value? then
      -- one kernel call for the whole proof
      let t₀ ← IO.monoNanosNow
      let e := mkApp2 (mkConst ``id [.zero]) type value
      let env ← getEnv
      let r ← IO.lazyPure fun _ => Kernel.check env {} e
      let t₁ ← IO.monoNanosNow
      stats := { stats with kernelNs := t₁ - t₀ }
      match r with
      | .ok _ => stats := { stats with checked := stats.checked + 1 }
      | .error ex =>
        let msg ← (ex.toMessageData (← getOptions)).toString
        stats := { stats with failures := stats.failures.push ("<proof>", "term", s!"kernel: {msg}"),
                              trusted := stats.trusted.insert "term-mode-kernel" 1 }
    modify fun (ts : Array (String × Nat)) => ts.push ("kernel", stats.kernelNs)
    return ({ type, stats, timings := #[] } : CheckResult)).run #[]
  let totalNs := (← IO.monoNanosNow) - start
  let ns (l : String) : Nat := (timings.find? (·.1 == l)).map (·.2) |>.getD 0
  -- checking each step on its own runs the kernel inside the reconstruction; in term mode the
  -- single kernel call follows it, so there it is a phase of its own
  let checkingNs := ns "reconstruct" + (if term then ns "kernel" else 0)
  let r := { r with timings := timings.map fun (l, n) => (l, n / 1000000), timingsNs := timings,
                    parsingNs := ns "parse" + ns "realize", checkingNs, totalNs }
  if let some dir := csv then
    writeCsv dir proofPath r
  return r

/-- Parse and realize a problem and an (elaborated) proof given as text, and reconstruct the
    proof as a term, with the problem's symbols resolved through `ctx.userNames` (the `alethe`
    tactic). Returns the result and the goals of the trusted steps. -/
def reconstructAletheText (problemText proofText : String) (ctx : Reconstruct.Context) :
    MetaM (ProofResult × List MVarId) := do
  withOptions (maxRecDepth.set · 100000) do
  withTheReader Core.Context (fun c => { c with maxHeartbeats := 0 }) do
  let problemCmds ← parseSexps "problem" problemText
  let proofSexps ← parseSexps "proof" proofText
  let parsed ← match Parser.parse problemCmds proofSexps with
    | .ok p => pure p
    | .error e => throwError "failed to parse the Alethe proof: {e}"
  let realized ← match ← cvc5.run (realize parsed) with
    | .ok r => pure r
    | .error e => throwError "cvc5 failed to parse the Alethe proof: {e}"
  let (r, st) ← (withChoices realized.choices.toList (reconstructProof realized (term := true))).run ctx {}
  return (r, st.skippedGoals.toList)

end Smt.Alethe
