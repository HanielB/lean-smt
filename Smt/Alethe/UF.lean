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
public import Smt.Alethe.Rare
public meta import Smt.Alethe.Rare
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

/-- Prove a clause `(cl l₁ … lₙ)` by refuting the negations of its literals: `k` receives the
    hypotheses `hᵢ : ¬lᵢ` (with their terms) and must return a proof of `False`. -/
def byRefutation (s : Step) (k : Array (cvc5.Term × Expr) → ReconstructM Expr) : ReconstructM Expr := do
  let ps ← mkPropList s.lits
  let decls ← s.lits.mapIdxM fun i l => do
    let p ← reconstructTerm l
    return (Name.num `h i, fun (_ : Array Expr) => pure (mkApp (mkConst ``Not) p))
  let h ← Meta.withLocalDeclsD decls fun hs => do
    Meta.mkLambdaFVars hs (← k (s.lits.zip hs))
  return mkApp2 (mkConst ``orN_of_impliesN_not) ps h

/-- From `hneg : ¬¬(a = b)` (or `¬¬(b = a)`) a proof of `a = b`. -/
def eqOfNegNeg (hneg : Expr) (l : cvc5.Term) (a b : cvc5.Term) : ReconstructM Expr := do
  let h ← Meta.mkAppM ``Prop.notNotElim #[hneg]
  let (x, y) ← eqSides l[0]!
  if x == a && y == b then return h
  if x == b && y == a then return ← Meta.mkAppM ``Eq.symm #[h]
  throwError "premise {l} does not relate {a} and {b}"

/-- `eq_transitive`: `(cl (not (= t₁ t₂)) … (not (= tₙ₋₁ tₙ)) (= t₁ tₙ))`. -/
def reconstructEqTransitive (s : Step) : ReconstructM Expr := do
  let n := s.lits.size
  if n < 2 then throwError "eq_transitive: too few literals"
  let (a, b) ← eqSides s.lits[n-1]!
  byRefutation s fun hs => do
    -- chain the negated-negated equalities from `a`
    let mut curr := a
    let mut h : Option Expr := none
    for (l, hneg) in hs[:n-1] do
      let (x, y) ← eqSides l[0]!
      let next := if x == curr then y else if y == curr then x else
        curr
      if next == curr && !(x == curr && y == curr) then throwError "eq_transitive: chain broken at {l}"
      let hstep ← eqOfNegNeg hneg l curr next
      h := some (← match h with
        | none => pure hstep
        | some h₀ => Meta.mkAppM ``Eq.trans #[h₀, hstep])
      curr := next
    if curr != b then throwError "eq_transitive: chain ends at {curr}, expected {b}"
    let some hab := h | throwError "eq_transitive: no premises"
    return mkApp hs[n-1]!.2 hab  -- ¬(a = b) applied to a = b

/-- `eq_congruent`: `(cl (not (= t₁ u₁)) … (not (= tₙ uₙ)) (= (f ts) (f us)))`, and
    `eq_congruent_pred`: `… (not (P ts)) (P us)`. -/
def reconstructEqCongruent (s : Step) (pred : Bool) : ReconstructM Expr := do
  let n := s.lits.size
  byRefutation s fun hs => do
    let (l, r) ← if pred then pure (s.lits[n-2]![0]!, s.lits[n-1]!) else eqSides s.lits[n-1]!
    if l.getKind! != r.getKind! || l.getNumChildren != r.getNumChildren then
      throwError "eq_congruent: {l} and {r} have different shapes"
    let start := if l.getKind! == .APPLY_UF then 1 else 0
    let eqs := hs[:n - (if pred then 2 else 1)]
    let mut args := #[]
    for i in [start:l.getNumChildren] do
      if l[i]! == r[i]! then
        args := args.push (← mkRefl l[i]!)
      else
        let some (le, hneg) := eqs.toArray.find? (fun (le, _) =>
            let (x, y) := (le[0]![0]!, le[0]![1]!)
            (x == l[i]! && y == r[i]!) || (x == r[i]! && y == l[i]!))
          | throwError "eq_congruent: no premise for {l[i]!} = {r[i]!}"
        args := args.push (← eqOfNegNeg hneg le l[i]! r[i]!)
    let le ← reconstructTerm l
    let re ← reconstructTerm r
    let goal ← Meta.mkEq le re
    let mv ← Meta.mkFreshExprMVar goal
    UF.smtCongr mv.mvarId! args
    let hlr ← instantiateMVars mv
    if pred then
      -- hs[n-2] : ¬¬(P ts), hs[n-1] : ¬(P us)
      let hp ← Meta.mkAppM ``Prop.notNotElim #[hs[n-2]!.2]
      return mkApp hs[n-1]!.2 (← Meta.mkAppM ``Eq.mp #[hlr, hp])
    else
      return mkApp hs[n-1]!.2 hlr

@[alethe_rule_reconstruct] def reconstructUF : RuleReconstructor := fun s => do
  match s.rule with
  | "eq_transitive" => addThm s.concl (← reconstructEqTransitive s)
  | "eq_congruent" => addThm s.concl (← reconstructEqCongruent s false)
  | "eq_congruent_pred" => addThm s.concl (← reconstructEqCongruent s true)
  | "ac_simp" => addTac s.concl Meta.AC.rewriteUnnormalizedTop
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
    if s.lits.size == 1 then
      -- Carcara's form: (cl (= (= a b) (= b a)))
      let (l, _) ← eqSides s.lits[0]!
      let (a, b) ← eqSides l
      let (u, (α : Q(Sort u))) ← reconstructSortLevelAndSort a.getSort!
      let x : Q($α) ← reconstructTerm a
      let y : Q($α) ← reconstructTerm b
      addThm s.concl q(@UF.eq_symm $α $x $y)
    else
      -- (cl (not (= a b)) (= b a))
      let (b, a) ← eqSides s.lits[1]!
      let (u, (α : Q(Sort u))) ← reconstructSortLevelAndSort a.getSort!
      let x : Q($α) ← reconstructTerm a
      let y : Q($α) ← reconstructTerm b
      addThm s.concl q(Prop.impliesElim (@Eq.symm $α $x $y))
  | "trans" =>
    let (a, b) ← eqSides s.lits[0]!
    -- a reflexive conclusion (a chain that returns to its start) needs no premise
    if a == b then return ← addThm s.concl (← mkEqRefl a)
    -- chain the premises from `a`, orienting each one (reflexive premises do not advance it)
    let mut curr := a
    let mut h : Option Expr := none
    for pr in s.premises do
      let (l, r) ← eqSides pr.lits[0]!
      if l == r then continue
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
  | "rare_rewrite" => reconstructRareRule s
  | _ => return none
where
  unNotTerm (t : cvc5.Term) : ReconstructM cvc5.Term := do
    if t.getKind! != .NOT then throwError "expected a negation, got {t}"
    return t[0]!

end Smt.Alethe
