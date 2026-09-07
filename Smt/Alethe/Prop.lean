/-
Copyright (c) 2021-2026 by the authors listed in the file AUTHORS and their
institutional affiliations. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Haniel Barbosa
-/

module

public import Smt.Alethe.Clause
public meta import Smt.Alethe.Clause
public import Smt.Reconstruct.Builtin
public meta import Smt.Reconstruct.Builtin
public import Smt.Reconstruct.UF
public meta import Smt.Reconstruct.UF

public meta section

/-!
# Propositional Alethe rules

The CNF axioms and the clausification rules, mapped onto the lemmas of
`Smt.Reconstruct.Prop.Lemmas` and `Smt.Reconstruct.Builtin.Lemmas`.
-/

namespace Smt.Alethe

open Lean Qq
open Smt.Reconstruct

/-- Strip one negation from a term, or fail. -/
def unNot (t : cvc5.Term) : ReconstructM cvc5.Term := do
  if t.getKind! != .NOT then throwError "expected a negation, got {t}"
  return t[0]!

/-- The two propositions of a binary connective `t`. -/
def binary (t : cvc5.Term) : ReconstructM (Q(Prop) × Q(Prop)) := do
  let p : Q(Prop) ← reconstructTerm t[0]!
  let q : Q(Prop) ← reconstructTerm t[1]!
  return (p, q)

/-- Apply an `ite` lemma of `Smt.Reconstruct.Builtin` (implicit arguments `c a b`, then the
    `Decidable c` instance) to the parts of the `ite` term `t` and the extra arguments `hs`. -/
def iteLemma (n : Name) (t : cvc5.Term) (hs : Array Expr := #[]) : ReconstructM Expr := do
  let c : Q(Prop) ← reconstructTerm t[0]!
  let a ← reconstructTerm t[1]!
  let b ← reconstructTerm t[2]!
  let hc ← Meta.synthDecidableInstance q($c)
  return mkAppN (mkConst n) ((#[c, a, b, hc] : Array Expr) ++ hs)

/-- Close the goal `lhs = rhs` of a `*_simplify` step with `simp` (the default simp set, which
    decides these propositional identities). -/
def simpClose (mv : MVarId) : MetaM Unit := do
  let thms ← Meta.getSimpTheorems
  -- the classical propositional identities of the `*_simplify` rules
  let extra : List Name := [`not_or, `Classical.not_and_iff_not_or_not, `Classical.not_imp_iff_and_not,
    `Classical.imp_iff_not_or, `imp_iff_not_or, `Classical.not_not, `Classical.not_forall, `not_exists,
    `and_imp, `or_imp, `imp_self, `and_self, `or_self]
  let mut thms := thms
  for n in extra do
    if (← getEnv).contains n then
      thms ← thms.addConst n
  -- flattening, reordering and duplicates of ∧/∨ first (on the equality itself)
  if ← (do try Meta.AC.rewriteUnnormalizedTop mv; pure true catch _ => pure false) then return
  let ctx ← Meta.Simp.mkContext (simpTheorems := #[thms]) (congrTheorems := ← Meta.getSimpCongrTheorems)
  let (r, _) ← Meta.simpGoal mv ctx
  if let some (_, mv') := r then
    throwError "simp did not close the goal:{indentD (← mv'.getType)}"

/-- `(or … φ … ¬φ …) = true` and `(and … φ … ¬φ …) = false` (also with a `true`/`false` literal). -/
def reconstructComplementary (l r : cvc5.Term) : ReconstructM (Option Expr) := do
  let isConst (u : cvc5.Term) (b : Bool) := u.getKind! == .CONST_BOOLEAN && u.getBooleanValue! == b
  let disj := l.getKind! == .OR && isConst r true
  let conj := l.getKind! == .AND && isConst r false
  if !disj && !conj then return none
  let lits := nary l.getKind! l
  let ps ← mkPropList lits
  let len ← Meta.mkAppM ``List.length #[ps]
  let bound (i : Nat) : ReconstructM Expr := do Meta.mkDecideProof (← Meta.mkAppM ``LT.lt #[toExpr i, len])
  -- a `true` (resp. `false`) literal
  if let some i := lits.findIdx? (isConst · disj) then
    let n := if disj then ``orN_eq_true_of_true else ``andN_eq_false_of_false
    let h ← Meta.mkEqRefl (← reconstructTerm lits[i]!)
    return some (mkAppN (mkConst n) #[ps, toExpr i, ← bound i, h])
  -- a complementary pair
  for i in [0:lits.size] do
    for j in [0:lits.size] do
      if isNotOf lits[j]! lits[i]! then
        let n := if disj then ``orN_eq_true_of_compl else ``andN_eq_false_of_compl
        let h ← Meta.mkEqRefl (← reconstructTerm lits[j]!)
        return some (mkAppN (mkConst n) #[ps, toExpr i, toExpr j, ← bound i, ← bound j, h])
  return none

/-- The `*_simplify` rules: a table of the frequent shapes over the existing rewrite theorems,
    with `simp` as the fallback. -/
def reconstructSimplify (s : Step) : ReconstructM Expr := do
  let t := s.lits[0]!
  if t.getKind! != .EQUAL then throwError "{s.rule}: expected an equality"
  let l := t[0]!
  let r := t[1]!
  if let some h ← reconstructComplementary l r then
    return ← addThm s.concl h
  let isConst (u : cvc5.Term) (b : Bool) := u.getKind! == .CONST_BOOLEAN && u.getBooleanValue! == b
  -- (= (= φ false) (not φ)), (= (= φ true) φ), (= (= φ φ) true), (= (= φ (not φ)) false)
  if l.getKind! == .EQUAL && l[0]!.getSort!.isBoolean then
    let a := l[0]!
    let b := l[1]!
    if isConst b false && isNotOf r a then
      let p : Q(Prop) ← reconstructTerm a
      return ← addThm s.concl q(@Prop.bool_eq_false $p)
    if isConst b true && r == a then
      let p : Q(Prop) ← reconstructTerm a
      return ← addThm s.concl q(@Prop.bool_eq_true $p)
    if a == b && isConst r true then
      let p : Q(Prop) ← reconstructTerm a
      return ← addThm s.concl q(@UF.eq_refl $p)
    if isNotOf b a && isConst r false then
      let p : Q(Prop) ← reconstructTerm a
      return ← addThm s.concl q(@Prop.bool_eq_nrefl $p)
  -- (= (not (not φ)) φ)
  if l.getKind! == .NOT && l[0]!.getKind! == .NOT && l[0]![0]! == r then
    let p : Q(Prop) ← reconstructTerm r
    return ← addThm s.concl q(@Prop.bool_double_not_elim $p)
  addTac s.concl simpClose

@[alethe_rule_reconstruct] def reconstructProp : RuleReconstructor := fun s => do
  match s.rule with
  | "equiv_simplify" | "implies_simplify" | "not_simplify" | "bool_simplify" | "and_simplify"
  | "or_simplify" | "ite_simplify" | "eq_simplify" | "connective_def" | "qnt_duality" =>
    reconstructSimplify s
  | "true" => addThm s.concl q(trivial)
  | "false" => addThm s.concl q(not_false_cl)
  | "not_not" =>
    let p : Q(Prop) ← reconstructTerm s.lits[1]!
    addThm s.concl q(@not_not_cl $p)
  -- premise-taking rules
  | "and" =>
    let some i := s.index? | throwError "and: missing index"
    let pr := s.premise! 0
    let ps : Q(List Prop) ← mkPropList (nary .AND pr.lits[0]!)
    let hi : Q($i < «$ps».length) ← Meta.mkDecideProof q($i < «$ps».length)
    let hps : Q(andN $ps) := pr.proof
    addThm s.concl q(@Prop.and_elim _ $hps $i $hi)
  | "not_or" =>
    let some i := s.index? | throwError "not_or: missing index"
    let pr := s.premise! 0
    let ps : Q(List Prop) ← mkPropList (nary .OR (← unNot pr.lits[0]!))
    let hi : Q($i < «$ps».length) ← Meta.mkDecideProof q($i < «$ps».length)
    let hnps : Q(¬orN $ps) := pr.proof
    addThm s.concl q(@Prop.not_or_elim _ $hnps $i $hi)
  | "not_and" =>
    let pr := s.premise! 0
    let ps : Q(List Prop) ← mkPropList (nary .AND (← unNot pr.lits[0]!))
    let hnps : Q(¬andN $ps) := pr.proof
    let hp : Q(orN (notN $ps)) := q(Prop.notAnd $ps $hnps)
    let p ← mkClause s.lits  -- ¬φ₁ ∨ … ∨ ¬φₙ, definitionally `orN (notN ps)`
    addThm s.concl (← fixClause p hp s.concl)
  | "and_intro" =>
    let last := s.premises.back!
    let f := fun (pr : Premise) ((q, hq) : Expr × Expr) =>
      (mkApp2 (mkConst ``And) pr.concl q, mkApp4 (mkConst ``And.intro) pr.concl q pr.proof hq)
    let (_, hq) := s.premises.pop.foldr f (last.concl, last.proof)
    addThm s.concl hq
  | "implies" =>
    let pr := s.premise! 0
    let (p, q) ← binary pr.lits[0]!
    let hpq : Q($p → $q) := pr.proof
    addThm s.concl q(Prop.impliesElim $hpq)
  | "not_implies1" =>
    let pr := s.premise! 0
    let (p, q) ← binary (← unNot pr.lits[0]!)
    let h : Q(¬($p → $q)) := pr.proof
    addThm s.concl q(Prop.notImplies1 $h)
  | "not_implies2" =>
    let pr := s.premise! 0
    let (p, q) ← binary (← unNot pr.lits[0]!)
    let h : Q(¬($p → $q)) := pr.proof
    addThm s.concl q(Prop.notImplies2 $h)
  | "equiv1" =>
    let pr := s.premise! 0
    let (p, q) ← binary pr.lits[0]!
    let h : Q($p = $q) := pr.proof
    addThm s.concl q(Prop.equivElim1 $h)
  | "equiv2" =>
    let pr := s.premise! 0
    let (p, q) ← binary pr.lits[0]!
    let h : Q($p = $q) := pr.proof
    addThm s.concl q(Prop.equivElim2 $h)
  | "not_equiv1" =>
    let pr := s.premise! 0
    let (p, q) ← binary (← unNot pr.lits[0]!)
    let h : Q(¬($p = $q)) := pr.proof
    addThm s.concl q(Prop.notEquivElim1 $h)
  | "not_equiv2" =>
    let pr := s.premise! 0
    let (p, q) ← binary (← unNot pr.lits[0]!)
    let h : Q(¬($p = $q)) := pr.proof
    addThm s.concl q(Prop.notEquivElim2 $h)
  | "xor1" =>
    let pr := s.premise! 0
    let (p, q) ← binary pr.lits[0]!
    let h : Q(XOr $p $q) := pr.proof
    addThm s.concl q(Prop.xorElim1 $h)
  | "xor2" =>
    let pr := s.premise! 0
    let (p, q) ← binary pr.lits[0]!
    let h : Q(XOr $p $q) := pr.proof
    addThm s.concl q(Prop.xorElim2 $h)
  | "not_xor1" =>
    let pr := s.premise! 0
    let (p, q) ← binary (← unNot pr.lits[0]!)
    let h : Q(¬XOr $p $q) := pr.proof
    addThm s.concl q(Prop.notXorElim1 $h)
  | "not_xor2" =>
    let pr := s.premise! 0
    let (p, q) ← binary (← unNot pr.lits[0]!)
    let h : Q(¬XOr $p $q) := pr.proof
    addThm s.concl q(Prop.notXorElim2 $h)
  | "ite1" =>
    let pr := s.premise! 0
    addThm s.concl (← iteLemma ``Builtin.iteElim2 pr.lits[0]! #[pr.proof])
  | "ite2" =>
    let pr := s.premise! 0
    addThm s.concl (← iteLemma ``Builtin.iteElim1 pr.lits[0]! #[pr.proof])
  | "not_ite1" =>
    let pr := s.premise! 0
    addThm s.concl (← iteLemma ``Builtin.notIteElim2 (← unNot pr.lits[0]!) #[pr.proof])
  | "not_ite2" =>
    let pr := s.premise! 0
    addThm s.concl (← iteLemma ``Builtin.notIteElim1 (← unNot pr.lits[0]!) #[pr.proof])
  -- CNF axioms
  | "and_pos" =>
    let some i := s.index? | throwError "and_pos: missing index"
    let ps : Q(List Prop) ← mkPropList (nary .AND (← unNot s.lits[0]!))
    addThm s.concl q(Prop.cnfAndPos $ps $i)
  | "and_neg" =>
    let ps : Q(List Prop) ← mkPropList (nary .AND s.lits[0]!)
    addThm s.concl q(@Prop.cnfAndNeg $ps)
  | "or_pos" =>
    let ps : Q(List Prop) ← mkPropList (nary .OR (← unNot s.lits[0]!))
    addThm s.concl q(@Prop.cnfOrPos $ps)
  | "or_neg" =>
    let some i := s.index? | throwError "or_neg: missing index"
    let ps : Q(List Prop) ← mkPropList (nary .OR s.lits[0]!)
    addThm s.concl q(Prop.cnfOrNeg $ps $i)
  | "implies_pos" =>
    let (p, q) ← binary (← unNot s.lits[0]!)
    addThm s.concl q(@Prop.cnfImpliesPos $p $q)
  | "implies_neg1" =>
    let (p, q) ← binary s.lits[0]!
    addThm s.concl q(@Prop.cnfImpliesNeg1 $p $q)
  | "implies_neg2" =>
    let (p, q) ← binary s.lits[0]!
    addThm s.concl q(@Prop.cnfImpliesNeg2 $p $q)
  | "equiv_pos1" =>
    let (p, q) ← binary (← unNot s.lits[0]!)
    addThm s.concl q(@Prop.cnfEquivPos2 $p $q)
  | "equiv_pos2" =>
    let (p, q) ← binary (← unNot s.lits[0]!)
    addThm s.concl q(@Prop.cnfEquivPos1 $p $q)
  | "equiv_neg1" =>
    let (p, q) ← binary s.lits[0]!
    addThm s.concl q(@Prop.cnfEquivNeg2 $p $q)
  | "equiv_neg2" =>
    let (p, q) ← binary s.lits[0]!
    addThm s.concl q(@Prop.cnfEquivNeg1 $p $q)
  | "xor_pos1" =>
    let (p, q) ← binary (← unNot s.lits[0]!)
    addThm s.concl q(@Prop.cnfXorPos1 $p $q)
  | "xor_pos2" =>
    let (p, q) ← binary (← unNot s.lits[0]!)
    addThm s.concl q(@Prop.cnfXorPos2 $p $q)
  | "xor_neg1" =>
    let (p, q) ← binary s.lits[0]!
    addThm s.concl q(@Prop.cnfXorNeg2 $p $q)
  | "xor_neg2" =>
    let (p, q) ← binary s.lits[0]!
    addThm s.concl q(@Prop.cnfXorNeg1 $p $q)
  | "ite_pos1" =>
    addThm s.concl (← iteLemma ``Builtin.cnfItePos2 (← unNot s.lits[0]!))
  | "ite_pos2" =>
    addThm s.concl (← iteLemma ``Builtin.cnfItePos1 (← unNot s.lits[0]!))
  | "ite_neg1" =>
    addThm s.concl (← iteLemma ``Builtin.cnfIteNeg2 s.lits[0]!)
  | "ite_neg2" =>
    addThm s.concl (← iteLemma ``Builtin.cnfIteNeg1 s.lits[0]!)
  | _ => return none

end Smt.Alethe
