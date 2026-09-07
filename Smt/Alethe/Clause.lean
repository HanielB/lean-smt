/-
Copyright (c) 2021-2026 by the authors listed in the file AUTHORS and their
institutional affiliations. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Haniel Barbosa
-/

module

public import Smt.Alethe.Basic
public meta import Smt.Alethe.Basic
public import Smt.Alethe.Lemmas
public meta import Smt.Alethe.Lemmas
public import Smt.Reconstruct.Prop
public meta import Smt.Reconstruct.Prop
public import Smt.Reconstruct.Builtin.AC
public meta import Smt.Reconstruct.Builtin.AC

public meta section

/-!
# Clausal reasoning

n-ary resolution driven by the pivots Carcara writes as `:args`, and the normalization fix-up
that reconciles a computed clause with the stated one (permutations, duplicates, flattening).
-/

namespace Smt.Alethe

open Lean Qq
open Smt.Reconstruct

/-- Given `hp : p`, prove `concl` when `p` and `concl` are the same clause up to
    associativity, commutativity, idempotence and flattening of `∨`. -/
def fixClause (p : Expr) (hp : Expr) (concl : Expr) : ReconstructM Expr := do
  if p == concl then
    return hp
  if p.isConstOf ``False then
    return mkApp2 (mkConst ``False.elim [Level.zero]) concl hp
  let hpq ← Meta.mkFreshExprMVar (mkApp3 (mkConst ``Eq [Level.succ .zero]) (mkSort .zero) p concl)
  Meta.AC.rewriteUnnormalizedTop hpq.mvarId!
  return mkApp4 (mkConst ``Prop.eqResolve) p concl hp hpq

/-- Given `hp : orN src`, prove the clause `tgt` (as the proposition `concl`) when every literal of
    `src` occurs in `tgt`: permutations, duplicate removal and weakening, through `orN_of_map`
    with an index map the kernel evaluates. `none` if some source literal is missing. -/
def reindexClause (src : Array cvc5.Term) (hp : Expr) (tgt : Array cvc5.Term) : ReconstructM (Option Expr) := do
  let mut g : Array Nat := #[]
  for l in src do
    let some k := tgt.idxOf? l | return none
    g := g.push k
  let qs ← mkPropList tgt
  let gE := toExpr g.toList
  let hb := mkApp2 (mkConst ``Eq.refl [.succ .zero]) (mkConst ``Bool) (mkConst ``Bool.true)
  return some (mkApp4 (mkConst ``orN_of_map) qs gE hb hp)

/-- The pivot/polarity pairs of a resolution step's `:args`, if present and well-formed. -/
def pivots? (s : Step) : Option (Array (cvc5.Term × Bool)) := do
  if s.args.isEmpty then none
  if s.args.size % 2 != 0 then none
  let mut ps := #[]
  for i in [0:s.args.size / 2] do
    let l ← s.args[2*i]!.term?
    let b ← s.args[2*i+1]!.bool?
    ps := ps.push (l, b)
  if ps.size != s.premises.size - 1 then none
  return ps

/-- Find a pivot between the current clause `cc` and the next premise `c₂`: a literal occurring
    positively on one side and negated on the other. -/
def findPivot (cc c₂ : Array cvc5.Term) : Option (cvc5.Term × Bool) := do
  for l in cc do
    if l.getKind! == .NOT then
      if c₂.contains l[0]! then return (l[0]!, false)
    if c₂.any (isNotOf · l) then return (l, true)
  none

def hasPivot (cc c₂ : Array cvc5.Term) (l : cvc5.Term) (pol : Bool) : Bool :=
  if pol then cc.contains l && c₂.any (isNotOf · l)
  else cc.any (isNotOf · l) && c₂.contains l

/-- Resolve the premises of a step in order, using the `:args` pivots as hints and searching for
    a pivot otherwise. Returns the computed clause and its proof. -/
def resolveChain (s : Step) : ReconstructM (Array cvc5.Term × Expr) := do
  if s.premises.isEmpty then
    throwError "resolution without premises"
  let hints := pivots? s
  let mut cc := s.premises[0]!.lits
  let mut cp := s.premises[0]!.proof
  for i in [1:s.premises.size] do
    let c₂ := s.premises[i]!.lits
    let hp := s.premises[i]!.proof
    let hint := hints.bind (·[i-1]?)
    let some (l, pol) := (match hint with
        | some (l, pol) => if hasPivot cc c₂ l pol then some (l, pol) else findPivot cc c₂
        | none => findPivot cc c₂)
      | throwError "no pivot found between {cc} and {c₂}"
    cp ← Prop.reconstructResolution cc c₂ pol l cp hp
    cc := Prop.getResolutionResult cc c₂ pol l
    -- Alethe removes every occurrence of the pivot: resolve again while it remains.
    while hasPivot cc c₂ l pol do
      cp ← Prop.reconstructResolution cc c₂ pol l cp hp
      cc := Prop.getResolutionResult cc c₂ pol l
  return (cc, cp)

/-- A proof of the stated clause of `s` from a computed clause `cc` with proof `cp`. -/
def concludeClause (s : Step) (cc : Array cvc5.Term) (cp : Expr) : ReconstructM Expr := do
  if cc == s.lits then
    return cp
  if let some h ← reindexClause cc cp s.lits then
    return h
  fixClause (← mkClause cc) cp s.concl

@[alethe_rule_reconstruct] def reconstructClausal : RuleReconstructor := fun s => do
  match s.rule with
  | "resolution" | "th_resolution" | "strict_resolution" =>
    let (cc, cp) ← resolveChain s
    let h ← concludeClause s cc cp
    addThm s.concl h
  | "contraction" | "reordering" | "or" =>
    let p := s.premise! 0
    addThm s.concl (← concludeClause s p.lits p.proof)
  | "weakening" =>
    -- (cl l₁ … lₙ) ⊢ (cl l₁ … lₙ m₁ … mₖ)
    let p := s.premise! 0
    let n := p.lits.size
    let ps : Q(List Prop) ← mkPropList p.lits
    let qs : Q(List Prop) ← mkPropList (s.lits.extract n s.lits.size)
    let hps : Q(orN $ps) := p.proof
    addThm s.concl q(@Prop.orN_append_left $ps $qs $hps)
  | "subproof" =>
    let some a := s.anchor | throwError "subproof outside of an anchor"
    let some last := a.last | throwError "empty subproof"
    let hs := s.discharge.map (·.proof)
    let h ← Meta.mkLambdaFVars hs last.proof
    let ps ← mkPropList (s.discharge.map (·.lits[0]!))
    -- the shape `¬p₁ ∨ … ∨ ¬pₙ ∨ q` the lemma produces, as an `Or` chain
    let mut p : Expr := last.concl
    for d in s.discharge.reverse do
      p := mkApp2 (mkConst ``Or) (mkApp (mkConst ``Not) d.concl) p
    let hp := mkApp3 (mkConst ``orN_of_impliesN) ps last.concl h
    addThm s.concl (← fixClause p hp s.concl)
  | _ => return none

end Smt.Alethe
