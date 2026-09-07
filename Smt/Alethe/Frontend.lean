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

def CheckResult.verdict (r : CheckResult) : String :=
  if r.stats.valid then "valid" else "holey"

def timed (label : String) (k : MetaM α) : StateT (Array (String × Nat)) MetaM α := do
  let t₀ ← IO.monoMsNow
  let r ← k
  let t₁ ← IO.monoMsNow
  modify (·.push (label, t₁ - t₀))
  return r

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

/-- Bind each `choice` constant to `Classical.epsilon` of its body (in order: a choice may mention
    earlier ones). -/
def withChoices (cs : List (cvc5.Term × cvc5.Term)) (k : ReconstructM α) : ReconstructM α := do
  match cs with
  | [] => k
  | (c, lam) :: cs =>
    let f ← reconstructTerm lam
    let (u, (α : Q(Sort u))) ← reconstructSortLevelAndSort c.getSort!
    let inst : Q(Nonempty $α) ← Meta.synthInstance q(Nonempty $α)
    let f : Q($α → Prop) := f
    let e : Q($α) := q(@Classical.epsilon $α $inst $f)
    withReader (fun r => { r with userNames := r.userNames.insert c.getSymbol! e }) (withChoices cs k)

/-- Check the Alethe proof in `proofPath` against the SMT-LIB problem in `problemPath`. -/
def checkAlethe (problemPath proofPath : System.FilePath) (native := false) (lax := false) :
    MetaM CheckResult := do
  let _ := lax
  -- a proof is one command with thousands of steps: no heartbeat budget
  withTheReader Core.Context (fun ctx => { ctx with maxHeartbeats := 0 }) do
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
    let (type, stats) ← timed "reconstruct" do
      let ctx : Reconstruct.Context := { native }
      -- symbols introduced by the proof (anchor variables, choice constants) are not the problem's
      let skip : Array String := realized.renamed.map (fun (x : String × String) => x.1)
        ++ realized.choices.map (fun (c : cvc5.Term × cvc5.Term) => c.1.getSymbol!)
      let ((type, stats), _) ← (withProblemSymbols realized.problem skip fun xs => do
        withChoices realized.choices.toList do
          let (type, stats) ← reconstructProof realized
          let type ← Meta.mkForallFVars xs type
          return (type, stats)).run ctx {}
      pure (type, stats)
    modify fun (ts : Array (String × Nat)) => ts.push ("kernel", stats.kernelMs)
    return ({ type, stats, timings := #[] } : CheckResult)).run #[]
  return { r with timings }

end Smt.Alethe
