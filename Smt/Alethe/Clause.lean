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

register_option smt.alethe.reflect : Bool := {
  defValue := false
  descr := "check the clausal rules (resolution, contraction, reordering, or, weakening) with the \
    reflective clause checker, one kernel evaluation per step; the term-by-term reconstruction \
    remains the fallback for the steps it declines"
}

register_option smt.alethe.reflectMinPremises : Nat := {
  defValue := 0
  descr := "with smt.alethe.reflect, only resolution steps with at least this many premises take \
    the reflective path"
}

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
    -- clauses are sets: drop the duplicates the resolution introduced (keeps the working clause
    -- small; the kernel cost of the index map is linear)
    (cc, cp) ← dedup cc cp
    -- Alethe removes every occurrence of the pivot: resolve again while it remains -- unless the
    -- premise itself holds the pivot with the polarity of the working clause (a tautological
    -- `(cl l (not l))`, as cvc5 emits for `not_equiv2`-style splits): that occurrence is put back
    -- by every resolution, so it stays, and resolving again would never end.
    let putsBack := if pol then c₂.contains l else c₂.any (isNotOf · l)
    while !putsBack && hasPivot cc c₂ l pol do
      cp ← Prop.reconstructResolution cc c₂ pol l cp hp
      cc := Prop.getResolutionResult cc c₂ pol l
      (cc, cp) ← dedup cc cp
  return (cc, cp)
where
  dedup (cc : Array cvc5.Term) (cp : Expr) : ReconstructM (Array cvc5.Term × Expr) := do
    let mut d := #[]
    for l in cc do
      if !d.contains l then d := d.push l
    if d.size == cc.size then return (cc, cp)
    let some cp' ← reindexClause cc cp d | return (cc, cp)
    return (d, cp')

/-- The reflective path for a clausal step: the premises' propositions reified as clauses over a
    context of atoms, the chain folded on bitsets, and one soundness theorem applied as a term
    (`Prop.ResNorm`). The `:args` pivots are hints. `none` when the step has a literal under two
    negations, which the encoding cannot express, or when the chain does not reach the stated
    clause, in which case the caller falls back. -/
def reflectClausal (s : Step) : ReconstructM (Option Expr) := do
  let hints : Array (Option Prop.ResNorm.Hint) ← match pivots? s with
    | some ps => ps.mapM fun (l, pol) => do return some { pivot := ← reconstructTerm l, pol }
    | none => pure (Array.replicate (s.premises.size - 1) none)
  Prop.ResNorm.proveClause (s.premises.map fun p => (p.proof, p.concl)) hints s.concl

/-- Whether `s` goes through the reflective path first. -/
def useReflect (s : Step) : ReconstructM Bool := do
  let opts ← getOptions
  return smt.alethe.reflect.get opts
    && s.premises.size ≥ smt.alethe.reflectMinPremises.get opts

/-- A proof of the stated clause of `s` from a computed clause `cc` with proof `cp`. -/
def concludeClause (s : Step) (cc : Array cvc5.Term) (cp : Expr) : ReconstructM Expr := do
  if cc == s.lits then
    return cp
  if let some h ← reindexClause cc cp s.lits then
    return h
  if smt.alethe.progress.get (← getOptions) > 0 then
    let missing := cc.filter (!s.lits.contains ·)
    progressLine s!"[alethe] {s.id} ({s.rule}): AC fallback, computed clause has {cc.size} literals, {missing.size} not in the stated one: {missing.toList.take 3}"
  fixClause (← mkClause cc) cp s.concl

@[alethe_rule_reconstruct] def reconstructClausal : RuleReconstructor := fun s => do
  match s.rule with
  | "resolution" | "strict_resolution" =>
    -- Carcara's special case: the empty clause from the single premise `(cl (not true))`
    if s.lits.isEmpty && s.premises.size == 1 then
      let p := s.premise! 0
      if p.lits.size == 1 && p.lits[0]!.getKind! == .NOT && p.lits[0]![0]!.getKind! == .CONST_BOOLEAN
          && p.lits[0]![0]!.getBooleanValue! then
        let h : Q(¬True) := p.proof
        return ← addThm s.concl q($h trivial)
    if ← useReflect s then
      if let some h ← reflectClausal s then
        return ← addThm s.concl h
    let (cc, cp) ← resolveChain s
    let h ← concludeClause s cc cp
    addThm s.concl h
  | "contraction" | "reordering" =>
    -- a step that neither permutes nor removes anything is its premise: return the premise's
    -- proof, as `concludeClause` would. Reifying two clauses to discover that costs 8x more
    let p := s.premise! 0
    if p.lits == s.lits then
      return ← addThm s.concl p.proof
    -- otherwise these two permute and deduplicate, which the reflective containment check does in
    -- one kernel evaluation instead of an index map: 0.80x and 0.74x (cvc5), 0.49x and 0.76x
    -- (veriT) over the round-eight smoke
    if smt.alethe.reflect.get (← getOptions) then
      if let some h ← reflectClausal s then
        return ← addThm s.concl h
    addThm s.concl (← concludeClause s p.lits p.proof)
  | "or" =>
    -- `(cl (or l₁ … lₙ)) ⊢ (cl l₁ … lₙ)`: the premise's proposition *is* the stated clause, since
    -- a clause is stated as exactly the right-nested `Or` chain the premise holds, so this returns
    -- the premise's proof untouched. The reflective path would reify both sides and build an atom
    -- context for a step that needs no work at all -- 3.2x slower on cvc5 and 3.9x on veriT in the
    -- round-eight smoke -- so it is not used here.
    let p := s.premise! 0
    addThm s.concl (← concludeClause s p.lits p.proof)
  | "weakening" =>
    -- (cl l₁ … lₙ) ⊢ (cl l₁ … lₙ m₁ … mₖ): a single `orN_append_left`, likewise cheaper than
    -- reifying the two clauses (1.8x on veriT in the round-eight smoke)
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
