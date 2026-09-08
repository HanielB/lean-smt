/-
Copyright (c) 2021-2026 by the authors listed in the file AUTHORS and their
institutional affiliations. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Haniel Barbosa
-/

module

public import Lean
public meta import Lean
public import Qq
public meta import Qq

/-!
# Normalization of `∧`/`∨` layers modulo associativity, commutativity and idempotence

A verified normalizer for one layer of a propositional connective, in the style of the
polynomial normalizer used for arithmetic. The layer is reified into a binary `Tree` whose leaves
are indices into a context of atoms (every subterm that is not the connective itself, or its
neutral element, is an atom, compared syntactically). `Tree.bits` computes the set of leaves
as a bitset; two trees with the same bitset denote the same proposition (`denoteAnd_eq`,
`denoteOr_eq`). The kernel evaluates `bits` in one structural pass with its accelerated
`Nat.shiftLeft`/`Nat.lor` on literals, so checking a layer of `n` atoms costs `O(n)` kernel steps
(plus the unfolding of the denotation against the original formula).
-/

@[expose] public section

namespace Smt.Reconstruct.Prop.AciNorm

abbrev Context := Nat → Prop

/-- One layer of a connective: `unit` is its neutral element, `leaf i` the `i`-th atom. -/
inductive Tree where
  | unit
  | leaf (i : Nat)
  | node (l r : Tree)
deriving Repr, Inhabited

namespace Tree

def denoteAnd (ctx : Context) : Tree → Prop
  | unit => True
  | leaf i => ctx i
  | node l r => denoteAnd ctx l ∧ denoteAnd ctx r

def denoteOr (ctx : Context) : Tree → Prop
  | unit => False
  | leaf i => ctx i
  | node l r => denoteOr ctx l ∨ denoteOr ctx r

/-- The normal form of a layer: the set of its leaves as a bitset. The kernel evaluates it with
its accelerated `Nat.shiftLeft` and `Nat.lor` on literals, in one pass over the tree. -/
def bits : Tree → Nat
  | unit => 0
  | leaf i => 1 <<< i
  | node l r => bits l ||| bits r

/-! ### Soundness -/

theorem testBit_bits_leaf {i j : Nat} : (bits (leaf j)).testBit i = true ↔ i = j := by
  show (1 <<< j).testBit i = true ↔ i = j
  rw [Nat.one_shiftLeft, Nat.testBit_two_pow, decide_eq_true_iff]
  exact ⟨Eq.symm, Eq.symm⟩

theorem denoteAnd_iff {ctx : Context} : ∀ (t : Tree),
    denoteAnd ctx t ↔ ∀ i, (bits t).testBit i = true → ctx i
  | unit => by
    show True ↔ ∀ i, (0 : Nat).testBit i = true → ctx i
    simp
  | leaf j => by
    show ctx j ↔ ∀ i, (bits (leaf j)).testBit i = true → ctx i
    constructor
    · intro h i hi; rw [testBit_bits_leaf.mp hi]; exact h
    · intro h; exact h j (testBit_bits_leaf.mpr rfl)
  | node l r => by
    show denoteAnd ctx l ∧ denoteAnd ctx r ↔ ∀ i, (bits l ||| bits r).testBit i = true → ctx i
    rw [denoteAnd_iff l, denoteAnd_iff r]
    constructor
    · rintro ⟨hl, hr⟩ i hi
      rw [Nat.testBit_or, Bool.or_eq_true] at hi
      rcases hi with hi | hi
      · exact hl i hi
      · exact hr i hi
    · intro h
      exact ⟨fun i hi => h i (by rw [Nat.testBit_or, hi, Bool.true_or]),
             fun i hi => h i (by rw [Nat.testBit_or, hi, Bool.or_true])⟩

theorem denoteOr_iff {ctx : Context} : ∀ (t : Tree),
    denoteOr ctx t ↔ ∃ i, (bits t).testBit i = true ∧ ctx i
  | unit => by
    show False ↔ ∃ i, (0 : Nat).testBit i = true ∧ ctx i
    simp
  | leaf j => by
    show ctx j ↔ ∃ i, (bits (leaf j)).testBit i = true ∧ ctx i
    constructor
    · intro h; exact ⟨j, testBit_bits_leaf.mpr rfl, h⟩
    · rintro ⟨i, hi, h⟩; rw [testBit_bits_leaf.mp hi] at h; exact h
  | node l r => by
    show denoteOr ctx l ∨ denoteOr ctx r ↔ ∃ i, (bits l ||| bits r).testBit i = true ∧ ctx i
    rw [denoteOr_iff l, denoteOr_iff r]
    constructor
    · rintro (⟨i, hi, h⟩ | ⟨i, hi, h⟩)
      · exact ⟨i, by rw [Nat.testBit_or, hi, Bool.true_or], h⟩
      · exact ⟨i, by rw [Nat.testBit_or, hi, Bool.or_true], h⟩
    · rintro ⟨i, hi, h⟩
      rw [Nat.testBit_or, Bool.or_eq_true] at hi
      rcases hi with hi | hi
      · exact .inl ⟨i, hi, h⟩
      · exact .inr ⟨i, hi, h⟩

/-- Two conjunction layers with the same normal form `m` denote the same proposition. -/
theorem denoteAnd_eq (ctx : Context) (a b : Tree) (m : Nat)
    (ha : bits a = m) (hb : bits b = m) : denoteAnd ctx a = denoteAnd ctx b := by
  apply propext
  rw [denoteAnd_iff, denoteAnd_iff, ha, hb]

/-- Two disjunction layers with the same normal form `m` denote the same proposition. -/
theorem denoteOr_eq (ctx : Context) (a b : Tree) (m : Nat)
    (ha : bits a = m) (hb : bits b = m) : denoteOr ctx a = denoteOr ctx b := by
  apply propext
  rw [denoteOr_iff, denoteOr_iff, ha, hb]

end Tree

end Smt.Reconstruct.Prop.AciNorm

end

public meta section

namespace Smt.Reconstruct.Prop.AciNorm

open Lean Qq Meta

structure ReifyState where
  atoms : Array Expr := #[]
  index : Std.HashMap Expr Nat := {}

abbrev ReifyM := StateT ReifyState MetaM

def getAtom (e : Expr) : ReifyM Nat := do
  let s ← get
  if let some i := s.index[e]? then
    return i
  let i := s.atoms.size
  set { atoms := s.atoms.push e, index := s.index.insert e i : ReifyState }
  return i

/-- Reify the layer of the connective `conj` (`true` for `∧`, `false` for `∨`) at the top of `e`:
nested occurrences of the same connective are reified recursively, its neutral element becomes
`unit`, everything else is an atom. -/
partial def reifyLayer (conj : Bool) (e : Expr) : ReifyM Tree := do
  match_expr e with
  | True => if conj then return .unit else atom e
  | False => if conj then atom e else return .unit
  | And a b =>
    if conj then return .node (← reifyLayer conj a) (← reifyLayer conj b) else atom e
  | Or a b =>
    if conj then atom e else return .node (← reifyLayer conj a) (← reifyLayer conj b)
  | _ => atom e
where
  atom (e : Expr) : ReifyM Tree := return .leaf (← getAtom e)

-- Raw literals throughout, so that the kernel compares the normal forms literal by literal.
def Tree.toExpr : Tree → Expr
  | .unit => mkConst ``Tree.unit
  | .leaf i => mkApp (mkConst ``Tree.leaf) (mkRawNatLit i)
  | .node l r => mkApp2 (mkConst ``Tree.node) l.toExpr r.toExpr

/-- The connective at the top of either side of `l = r`, if any. -/
def topConnective? (l r : Expr) : Option Bool :=
  match_expr l with
  | And _ _ => some true
  | Or _ _ => some false
  | _ =>
    match_expr r with
    | And _ _ => some true
    | Or _ _ => some false
    | _ => none

-- `Tree.bits` below is this module's own non-`meta` function, which the phase-distinction
-- check only allows within a single module under this option.
set_option compiler.relaxedMetaCheck true in
/-- Prove `l = r` when the two sides are equal modulo associativity, commutativity and idempotence
of their top connective (and its neutral element). Throws if they are not. -/
def proveEq (l r : Expr) : MetaM Expr := do
  let some conj := topConnective? l r
    | throwError "[aci_norm] neither side has a top-level connective:{indentExpr l}\n={indentExpr r}"
  let (tl, s) ← (reifyLayer conj l).run {}
  let (tr, s) ← (reifyLayer conj r).run s
  let m := tl.bits
  unless m == tr.bits do
    throwError "[aci_norm] the two sides have different normal forms:{indentExpr l}\n={indentExpr r}"
  let ctx : Q(Context) ← if h : 0 < s.atoms.size
    then do
      let is : Q(RArray Prop) ← (RArray.ofArray s.atoms h).toExpr q(Prop) id
      pure q(«$is».get)
    else pure q(fun _ => False)
  let mE := mkRawNatLit m
  let refl := mkApp2 (mkConst ``Eq.refl [1]) (mkConst ``Nat) mE
  let thm := if conj then ``Tree.denoteAnd_eq else ``Tree.denoteOr_eq
  -- `Tree.denoteAnd ctx tl` unfolds to `l` (and likewise for `r`), which the kernel checks
  return mkAppN (mkConst thm) #[ctx, tl.toExpr, tr.toExpr, mE, refl, refl]

/-- Close a goal `l = r` with `proveEq`. -/
def aciNorm (mv : MVarId) : MetaM Unit := do
  let some (_, l, r) := (← mv.getType).eq?
    | throwError "[aci_norm] expected an equality, got {← mv.getType}"
  mv.assign (← proveEq l r)

end Smt.Reconstruct.Prop.AciNorm

end
