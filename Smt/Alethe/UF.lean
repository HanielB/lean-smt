/-
Copyright (c) 2021-2026 by the authors listed in the file AUTHORS and their
institutional affiliations. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Haniel Barbosa
-/

module

public import Smt.Alethe.Clause
public meta import Smt.Alethe.Clause
public import Smt.Reconstruct.UF
public meta import Smt.Reconstruct.UF
public import Smt.Reconstruct.Builtin
public meta import Smt.Reconstruct.Builtin
public import Smt.Reconstruct.Prop
public meta import Smt.Reconstruct.Prop
public import Smt.Reconstruct.Int
public meta import Smt.Reconstruct.Int
public import Smt.Reconstruct.Rat
public meta import Smt.Reconstruct.Rat
public import Smt.Reconstruct.Quant
public meta import Smt.Reconstruct.Quant
public import Smt.Alethe.RareRules
public meta import Smt.Alethe.RareRules
public import Lean.Meta.Native
public meta import Lean.Meta.Native

public meta section

/-!
# Equality and rewriting rules

`refl`, `symm`, `trans`, `cong`, their clausal variants, and the term-level rewriting rules
(`aci_simp`, `evaluate`, `rare_rewrite`), mapped onto `Smt.Reconstruct.UF` and
`Smt.Reconstruct.Builtin`.
-/

namespace Smt.Alethe

open Lean Qq
open Smt.Reconstruct

/-- A proof of a decidable proposition by `decide`. -/
def decideProof (p : Q(Prop)) (hp : Q(Decidable $p)) : MetaM Q($p) :=
  return .app q(@of_decide_eq_true $p $hp) q(Eq.refl true)

/-- A proof of a decidable proposition by native evaluation. -/
def nativeDecideProof (p : Q(Prop)) (hp : Q(Decidable $p)) : MetaM Q($p) := do
  match ← Meta.nativeEqTrue `Smt.eval q(decide $p) with
  | .notTrue => throwError "evaluated that the proposition {indentExpr q(decide $p)} is false"
  | .success hdp => return .app q(@of_decide_eq_true $p $hp) hdp

/-- The sides of an equality term. -/
def eqSides (t : cvc5.Term) : ReconstructM (cvc5.Term × cvc5.Term) := do
  if t.getKind! != .EQUAL then throwError "expected an equality, got {t}"
  return (t[0]!, t[1]!)

/-- A proof of `a = b` from a premise proving either `a = b` or `b = a`. -/
def orient (pr : Premise) (a b : cvc5.Term) : ReconstructM Expr := do
  let (l, r) ← eqSides pr.lits[0]!
  if l == a && r == b then
    return pr.proof
  if l == b && r == a then
    let (u, (α : Q(Sort u))) ← reconstructSortLevelAndSort l.getSort!
    let x : Q($α) ← reconstructTerm l
    let y : Q($α) ← reconstructTerm r
    let h : Q($x = $y) := pr.proof
    return q(Eq.symm $h)
  throwError "premise {pr.lits[0]!} does not prove {a} = {b} in either direction"

/-- A proof of `a = a`. -/
def mkRefl (a : cvc5.Term) : ReconstructM Expr := mkEqRefl a

/-- A proof of `a = c` from `hab : a = b` and `hbc : b = c`. -/
def mkTrans (a b c : cvc5.Term) (hab hbc : Expr) : ReconstructM Expr := do
  let (u, (α : Q(Sort u))) ← reconstructSortLevelAndSort a.getSort!
  let x : Q($α) ← reconstructTerm a
  let y : Q($α) ← reconstructTerm b
  let z : Q($α) ← reconstructTerm c
  let hab : Q($x = $y) := hab
  let hbc : Q($y = $z) := hbc
  return q(Eq.trans $hab $hbc)

/-- `cong`: align the premises with the argument positions of the two applications (equal
    arguments get `Eq.refl`, flipped premises `Eq.symm`), then use `smtCongr`. -/
def reconstructCong (s : Step) : ReconstructM Expr := do
  let (l, r) ← eqSides s.lits[0]!
  let k := l.getKind!
  if k == .FORALL || k == .EXISTS || k == .LAMBDA || k == .WITNESS then
    throwError "cong under binders is not supported"
  if l.getKind! != r.getKind! || l.getNumChildren != r.getNumChildren then
    throwError "cong: {l} and {r} have different shapes"
  -- the function symbol of an application is child 0 in cvc5
  let start := if k == .APPLY_UF then 1 else 0
  if k == .APPLY_UF && l[0]! != r[0]! then
    throwError "cong: different function symbols"
  -- premises need not be one per argument nor in order (reflexive ones may be given or omitted)
  let matchesEq (pr : Premise) (a b : cvc5.Term) : Bool :=
    pr.lits.size == 1 && pr.lits[0]!.getKind! == .EQUAL &&
      ((pr.lits[0]![0]! == a && pr.lits[0]![1]! == b) || (pr.lits[0]![0]! == b && pr.lits[0]![1]! == a))
  let mut hs := #[]
  for i in [start:l.getNumChildren] do
    if l[i]! == r[i]! then
      hs := hs.push (← mkRefl l[i]!)
    else
      let some pr := s.premises.find? (matchesEq · l[i]! r[i]!)
        | throwError "cong: no premise for {l[i]!} = {r[i]!}"
      hs := hs.push (← orient pr l[i]! r[i]!)
  addTac s.concl (UF.smtCongr · hs)

/-- `rare_rewrite`: build a `RewriteStep` from the step's arguments and try the per-theory rewrite
    reconstructors shared with the cvc5 path. -/
def reconstructRareRewrite (s : Step) : ReconstructM (Option Expr) := do
  let some (Arg.str name) := s.args[0]? | throwError "rare_rewrite: missing rule name"
  -- rules newer than lean-cvc5's enumeration
  if name == "or-not-refl" then
    let t := s.args[1]!.term!
    let (u, (α : Q(Sort u))) ← reconstructSortLevelAndSort t.getSort!
    let te : Q($α) ← reconstructTerm t
    let ps ← mkPropList ((nary .OR s.lits[0]![0]!).extract 1 (nary .OR s.lits[0]![0]!).size)
    return some (← addThm s.concl (mkApp3 (mkConst ``or_not_refl [u]) α te ps))
  let some rule := rareRuleOfName name | throwError "rare_rewrite: unknown RARE rule {name}"
  let result := s.lits[0]!
  -- index 0 stands for the rule id, as in `cvc5.Proof.getArguments`
  let mut args := #[result]
  let mut lists : Std.HashMap Nat (Array cvc5.Term) := {}
  for a in s.args[1:] do
    match a with
    | .term t => args := args.push t
    | .list ts =>
      lists := lists.insert args.size ts
      args := args.push result
    | _ => throwError "rare_rewrite: unexpected argument"
  let rw : RewriteStep := { rule, args, lists, result,
                            premises := s.premises.map fun p => (p.lits[0]!, pure p.proof) }
  for f in [Prop.reconstructRewrite, Builtin.reconstructRewrite, UF.reconstructRewrite,
            Int.reconstructRewrite, Rat.reconstructRewrite, Quant.reconstructRewrite] do
    if let some e ← f rw then
      return some (← addThm s.concl e)
  return none

@[alethe_rule_reconstruct] def reconstructUF : RuleReconstructor := fun s => do
  match s.rule with
  | "refl" | "eq_reflexive" =>
    let (a, _) ← eqSides s.lits[0]!
    addThm s.concl (← mkRefl a)
  | "symm" =>
    let pr := s.premise! 0
    if s.lits[0]!.getKind! == .EQUAL then
      let (a, b) ← eqSides s.lits[0]!
      addThm s.concl (← orient pr a b)
    else
      -- (cl (not (= a b))) ⊢ (cl (not (= b a)))
      let (b, a) ← eqSides (← unNotTerm s.lits[0]!)
      let (u, (α : Q(Sort u))) ← reconstructSortLevelAndSort a.getSort!
      let x : Q($α) ← reconstructTerm a
      let y : Q($α) ← reconstructTerm b
      let h : Q($x ≠ $y) := pr.proof
      addThm s.concl q(Ne.symm $h)
  | "not_symm" =>
    let pr := s.premise! 0
    let (b, a) ← eqSides (← unNotTerm s.lits[0]!)
    let (u, (α : Q(Sort u))) ← reconstructSortLevelAndSort a.getSort!
    let x : Q($α) ← reconstructTerm a
    let y : Q($α) ← reconstructTerm b
    let h : Q($x ≠ $y) := pr.proof
    addThm s.concl q(Ne.symm $h)
  | "eq_symmetric" =>
    -- (cl (not (= a b)) (= b a))
    let (b, a) ← eqSides s.lits[1]!
    let (u, (α : Q(Sort u))) ← reconstructSortLevelAndSort a.getSort!
    let x : Q($α) ← reconstructTerm a
    let y : Q($α) ← reconstructTerm b
    addThm s.concl q(Prop.impliesElim (@Eq.symm $α $x $y))
  | "trans" =>
    let (a, b) ← eqSides s.lits[0]!
    -- chain the premises from `a`, orienting each one
    let mut curr := a
    let mut h : Option Expr := none
    for pr in s.premises do
      let (l, r) ← eqSides pr.lits[0]!
      let next ← if l == curr then pure r else if r == curr then pure l else
        throwError "trans: premise {pr.lits[0]!} does not continue from {curr}"
      let hstep ← orient pr curr next
      h := some (← match h with
        | none => pure hstep
        | some h₀ => mkTrans a curr next h₀ hstep)
      curr := next
    if curr != b then throwError "trans: chain ends at {curr}, expected {b}"
    let some hab := h | throwError "trans without premises"
    addThm s.concl hab
  | "cong" => reconstructCong s
  | "distinct_elim" =>
    let (l, _) ← eqSides s.lits[0]!
    addThm s.concl (← mkRefl l)
  | "aci_simp" =>
    addTac s.concl Meta.AC.rewriteUnnormalizedTop
  | "evaluate" =>
    let (l, r) ← eqSides s.lits[0]!
    let (u, (α : Q(Sort u))) ← reconstructSortLevelAndSort l.getSort!
    let t : Q($α) ← reconstructTerm l
    let t' : Q($α) ← reconstructTerm r
    if l == r then
      return some (← addThm q($t = $t') q(Eq.refl $t))
    let hp : Q(Decidable ($t = $t')) ← Meta.synthDecidableInstance q(($t = $t'))
    if hp.getUsedConstants.any (isNoncomputable (← getEnv)) then
      return none
    if ← useNative then
      addThm q($t = $t') (← nativeDecideProof q($t = $t') hp)
    else
      addThm q($t = $t') (← decideProof q($t = $t') hp)
  | "rare_rewrite" => reconstructRareRewrite s
  | _ => return none
where
  unNotTerm (t : cvc5.Term) : ReconstructM cvc5.Term := do
    if t.getKind! != .NOT then throwError "expected a negation, got {t}"
    return t[0]!

end Smt.Alethe
