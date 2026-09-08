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

/-- Close a quantifier-duality goal `(∀ xs, φ) = ¬∃ xs, ¬φ` (and the `∃`/`∀` variants of
    `connective_def` and `qnt_duality`) by pushing the negation through the binders. -/
def closeQuantDuality (mv : MVarId) : MetaM Unit := do
  let mut thms : Meta.SimpTheorems := {}
  for n in [`not_exists, `Classical.not_forall, `Classical.not_not, `not_not] do
    if (← getEnv).contains n then
      thms ← thms.addConst n
  let ctx ← Meta.Simp.mkContext (simpTheorems := #[thms]) (congrTheorems := ← Meta.getSimpCongrTheorems)
  let (r, _) ← Meta.simpGoal mv ctx
  if let some (_, mv') := r then
    -- the two sides now coincide (the simp set above has no `eq_self`)
    try mv'.refl catch _ => throwError "simp did not close the goal:{indentD (← mv'.getType)}"

/-- `connective_def`: the definitions of `xor`, Boolean `=` and Boolean `ite` in terms of `∧`, `∨`,
    `¬` and `→`, and the duality of the quantifiers. -/
def reconstructConnectiveDef (s : Step) : ReconstructM Expr := do
  let t := s.lits[0]!
  if t.getKind! != .EQUAL then throwError "{s.rule}: expected an equality"
  let l := t[0]!
  match l.getKind! with
  | .XOR =>
    let a : Q(Prop) ← reconstructTerm l[0]!
    let b : Q(Prop) ← reconstructTerm l[1]!
    addThm s.concl q(connective_def_xor $a $b)
  | .EQUAL =>
    let a : Q(Prop) ← reconstructTerm l[0]!
    let b : Q(Prop) ← reconstructTerm l[1]!
    addThm s.concl q(connective_def_eq $a $b)
  | .ITE =>
    let c : Q(Prop) ← reconstructTerm l[0]!
    let a : Q(Prop) ← reconstructTerm l[1]!
    let b : Q(Prop) ← reconstructTerm l[2]!
    let hc : Q(Decidable $c) ← Meta.synthDecidableInstance q($c)
    addThm s.concl q(@connective_def_ite $c $a $b $hc)
  | .FORALL | .EXISTS => addTac s.concl closeQuantDuality
  | _ => throwError "{s.rule}: unsupported shape {t}"

/-- The Boolean arguments of uninterpreted applications in `e` (other than `true`/`false`, and
    not under binders): the atoms the application form of `bfun_elim` case-splits on. -/
partial def bfunAtoms (e : Expr) (acc : Array Expr) : MetaM (Array Expr) := do
  match e with
  | .app .. =>
    let f := e.getAppFn
    let args := e.getAppArgs
    let mut acc := acc
    for a in args do
      acc ← bfunAtoms a acc
    if f.isFVar then
      for a in args do
        if !(a.isConstOf ``True || a.isConstOf ``False) && !a.hasLooseBVars && (← Meta.isProp a) then
          if !acc.contains a then acc := acc.push a
    return acc
  | .mdata _ b => bfunAtoms b acc
  | .proj _ _ b => bfunAtoms b acc
  | _ => return acc

/-- Close `φ = ψ`, where `ψ` is `φ` with Boolean arguments `b` of applications turned into
    `ite b (… true …) (… false …)`, by case-splitting on the atoms and simplifying. -/
partial def bfunElimProve (mv : MVarId) (atoms : List Expr) (hyps : Array Expr) : MetaM Unit := do
  match atoms with
  | [] =>
    let mut thms ← Meta.getSimpTheorems
    for h in hyps do
      thms ← thms.add (.fvar h.fvarId!) #[] h
    let ctx ← Meta.Simp.mkContext {} #[thms] (← Meta.getSimpCongrTheorems)
    let (r, _) ← Meta.simpGoal mv ctx #[← Meta.Simp.getSimprocs]
    if let some (_, mv') := r then
      throwError "bfun_elim: the two sides differ in a case:{indentExpr (← mv'.getType)}"
  | b :: rest =>
    let ty ← mv.getType
    let em ← Meta.mkAppM ``Classical.em #[b]
    let pos ← Meta.withLocalDeclD `hb b fun hb => do
      let m ← Meta.mkFreshExprMVar ty
      bfunElimProve m.mvarId! rest (hyps.push hb)
      Meta.mkLambdaFVars #[hb] (← instantiateMVars m)
    let neg ← Meta.withLocalDeclD `hnb (mkNot b) fun hnb => do
      let m ← Meta.mkFreshExprMVar ty
      bfunElimProve m.mvarId! rest (hyps.push hnb)
      Meta.mkLambdaFVars #[hnb] (← instantiateMVars m)
    mv.assign (← Meta.mkAppM ``Or.elim #[em, pos, neg])

@[alethe_rule_reconstruct] def reconstructProp : RuleReconstructor := fun s => do
  match s.rule with
  | "bfun_elim" =>
    -- the application form (Carcara's core pass reduces the quantifier form): `f … b …` becomes
    -- `ite b (f … true …) (f … false …)` throughout the premise
    let pr := s.premise! 0
    if pr.lits.size != 1 || s.lits.size != 1 then throwError "bfun_elim: expected unit clauses"
    let phi ← reconstructTerm pr.lits[0]!
    let psi ← reconstructTerm s.lits[0]!
    let atoms ← bfunAtoms phi #[]
    if atoms.size > 8 then throwError "bfun_elim: {atoms.size} Boolean arguments to split on"
    let heq ← addTac (← Meta.mkEq phi psi) fun mv => bfunElimProve mv atoms.toList #[]
    addThm s.concl (← Meta.mkAppM ``Eq.mp #[heq, pr.proof])
  | "connective_def" | "qnt_duality" => reconstructConnectiveDef s
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
