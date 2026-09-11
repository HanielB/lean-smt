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
public import Smt.Reconstruct.Prop.Core
public meta import Smt.Reconstruct.Prop.Core

/-!
# Reflective normalizers for one layer of a propositional connective

Verified normalizers, in the style of the polynomial normalizer used for arithmetic, for the
two structures a layer of a propositional connective can have:

* **Bounded semilattice** (`∧`, `∨`): associative, commutative, idempotent, with a neutral
  element and an *annihilator* (`False` for `∧`, `True` for `∨`). The normal form is the *set*
  of the layer's atoms as a bitset — `none` when the annihilator occurs, since the whole layer
  then collapses to it. This checks the `semilattice_simp` rule (`aci_simp` and `absorb` of old).
* **Abelian group of exponent two** (`xor`): associative, commutative, with a neutral element and
  every element its own inverse. The normal form is the *parity* of the atoms — the bitset folded
  with `xor` instead of `or`, so that a pair `x ⊕ x` cancels. This checks `boolean_group_simp`.

A layer is reified into a binary `Tree` whose leaves are indices into a context of atoms (every
subterm that is not the connective itself, or one of its two distinguished constants, is an atom,
compared syntactically). The kernel evaluates the normal form in one structural pass with its
accelerated `Nat.shiftLeft`/`Nat.lor`/`Nat.xor` on literals, so checking a layer of `n` atoms costs
`O(n)` kernel steps (plus the unfolding of the denotation against the original formula).
-/

@[expose] public section

namespace Smt.Reconstruct.Prop.AciNorm

abbrev Context := Nat → Prop

/-- One layer of a connective: `unit` is its neutral element, `absorb` its annihilator, `leaf i`
the `i`-th atom. -/
inductive Tree where
  | unit
  | absorb
  | leaf (i : Nat)
  | node (l r : Tree)
deriving Repr, Inhabited

namespace Tree

def denoteAnd (ctx : Context) : Tree → Prop
  | unit => True
  | absorb => False
  | leaf i => ctx i
  | node l r => denoteAnd ctx l ∧ denoteAnd ctx r

def denoteOr (ctx : Context) : Tree → Prop
  | unit => False
  | absorb => True
  | leaf i => ctx i
  | node l r => denoteOr ctx l ∨ denoteOr ctx r

def denoteXor (ctx : Context) : Tree → Prop
  | unit => False
  | absorb => False
  | leaf i => ctx i
  | node l r => XOr (denoteXor ctx l) (denoteXor ctx r)

/-- The semilattice normal form of a layer: the set of its leaves as a bitset, or `none` when the
annihilator occurs. The kernel evaluates it with its accelerated `Nat.shiftLeft` and `Nat.lor` on
literals, in one pass over the tree. -/
def bits : Tree → Option Nat
  | unit => some 0
  | absorb => none
  | leaf i => some (1 <<< i)
  | node l r =>
    match bits l, bits r with
    | some a, some b => some (a ||| b)
    | _, _ => none

/-- The exponent-two normal form of a layer: the parity of its leaves, as the bitset folded with
`Nat.xor`, so that a leaf occurring an even number of times cancels. -/
def xbits : Tree → Nat
  | unit => 0
  | absorb => 0
  | leaf i => 1 <<< i
  | node l r => xbits l ^^^ xbits r

/-- One more than the largest leaf index, `0` for a tree without leaves. -/
def bound : Tree → Nat
  | unit => 0
  | absorb => 0
  | leaf i => i + 1
  | node l r => max (bound l) (bound r)

/-! ### Soundness of the semilattice normal form -/

theorem testBit_one_shiftLeft {i j : Nat} : (1 <<< j).testBit i = true ↔ i = j := by
  rw [Nat.one_shiftLeft, Nat.testBit_two_pow, decide_eq_true_iff]
  exact ⟨Eq.symm, Eq.symm⟩

theorem bits_node_some {l r : Tree} {k : Nat} (h : bits (node l r) = some k) :
    ∃ a b, bits l = some a ∧ bits r = some b ∧ k = a ||| b := by
  unfold bits at h
  cases hl : bits l <;> cases hr : bits r <;> simp [hl, hr] at h
  exact ⟨_, _, rfl, rfl, h.symm⟩

theorem bits_node_none {l r : Tree} (h : bits (node l r) = none) :
    bits l = none ∨ bits r = none := by
  unfold bits at h
  cases hl : bits l <;> cases hr : bits r <;> simp [hl, hr] at h <;> simp

theorem denoteAnd_iff {ctx : Context} : ∀ (t : Tree) {k : Nat}, bits t = some k →
    (denoteAnd ctx t ↔ ∀ i, k.testBit i = true → ctx i)
  | unit, k, h => by
    have hk : k = 0 := by simpa [bits] using h.symm
    subst hk
    show True ↔ ∀ i, (0 : Nat).testBit i = true → ctx i
    simp
  | absorb, _, h => by simp [bits] at h
  | leaf j, k, h => by
    have hk : k = 1 <<< j := by simpa [bits] using h.symm
    subst hk
    show ctx j ↔ ∀ i, (1 <<< j).testBit i = true → ctx i
    constructor
    · intro h i hi; rw [testBit_one_shiftLeft.mp hi]; exact h
    · intro h; exact h j (testBit_one_shiftLeft.mpr rfl)
  | node l r, k, h => by
    obtain ⟨a, b, hl, hr, hk⟩ := bits_node_some h
    subst hk
    show denoteAnd ctx l ∧ denoteAnd ctx r ↔ ∀ i, (a ||| b).testBit i = true → ctx i
    rw [denoteAnd_iff l hl, denoteAnd_iff r hr]
    constructor
    · rintro ⟨hl, hr⟩ i hi
      rw [Nat.testBit_or, Bool.or_eq_true] at hi
      rcases hi with hi | hi
      · exact hl i hi
      · exact hr i hi
    · intro h
      exact ⟨fun i hi => h i (by rw [Nat.testBit_or, hi, Bool.true_or]),
             fun i hi => h i (by rw [Nat.testBit_or, hi, Bool.or_true])⟩

theorem denoteAnd_none {ctx : Context} : ∀ (t : Tree), bits t = none → (denoteAnd ctx t ↔ False)
  | unit, h => by simp [bits] at h
  | absorb, _ => Iff.rfl
  | leaf _, h => by simp [bits] at h
  | node l r, h => by
    show denoteAnd ctx l ∧ denoteAnd ctx r ↔ False
    rcases bits_node_none h with hl | hr
    · rw [denoteAnd_none l hl]; simp
    · rw [denoteAnd_none r hr]; simp

theorem denoteOr_iff {ctx : Context} : ∀ (t : Tree) {k : Nat}, bits t = some k →
    (denoteOr ctx t ↔ ∃ i, k.testBit i = true ∧ ctx i)
  | unit, k, h => by
    have hk : k = 0 := by simpa [bits] using h.symm
    subst hk
    show False ↔ ∃ i, (0 : Nat).testBit i = true ∧ ctx i
    simp
  | absorb, _, h => by simp [bits] at h
  | leaf j, k, h => by
    have hk : k = 1 <<< j := by simpa [bits] using h.symm
    subst hk
    show ctx j ↔ ∃ i, (1 <<< j).testBit i = true ∧ ctx i
    constructor
    · intro h; exact ⟨j, testBit_one_shiftLeft.mpr rfl, h⟩
    · rintro ⟨i, hi, h⟩; rw [testBit_one_shiftLeft.mp hi] at h; exact h
  | node l r, k, h => by
    obtain ⟨a, b, hl, hr, hk⟩ := bits_node_some h
    subst hk
    show denoteOr ctx l ∨ denoteOr ctx r ↔ ∃ i, (a ||| b).testBit i = true ∧ ctx i
    rw [denoteOr_iff l hl, denoteOr_iff r hr]
    constructor
    · rintro (⟨i, hi, h⟩ | ⟨i, hi, h⟩)
      · exact ⟨i, by rw [Nat.testBit_or, hi, Bool.true_or], h⟩
      · exact ⟨i, by rw [Nat.testBit_or, hi, Bool.or_true], h⟩
    · rintro ⟨i, hi, h⟩
      rw [Nat.testBit_or, Bool.or_eq_true] at hi
      rcases hi with hi | hi
      · exact .inl ⟨i, hi, h⟩
      · exact .inr ⟨i, hi, h⟩

theorem denoteOr_none {ctx : Context} : ∀ (t : Tree), bits t = none → (denoteOr ctx t ↔ True)
  | unit, h => by simp [bits] at h
  | absorb, _ => Iff.rfl
  | leaf _, h => by simp [bits] at h
  | node l r, h => by
    show denoteOr ctx l ∨ denoteOr ctx r ↔ True
    rcases bits_node_none h with hl | hr
    · rw [denoteOr_none l hl]; simp
    · rw [denoteOr_none r hr]; simp

/-- Two conjunction layers with the same normal form `m` denote the same proposition. -/
theorem denoteAnd_eq (ctx : Context) (a b : Tree) (m : Option Nat)
    (ha : bits a = m) (hb : bits b = m) : denoteAnd ctx a = denoteAnd ctx b := by
  apply propext
  cases m with
  | none => rw [denoteAnd_none a ha, denoteAnd_none b hb]
  | some k => rw [denoteAnd_iff a ha, denoteAnd_iff b hb]

/-- Two disjunction layers with the same normal form `m` denote the same proposition. -/
theorem denoteOr_eq (ctx : Context) (a b : Tree) (m : Option Nat)
    (ha : bits a = m) (hb : bits b = m) : denoteOr ctx a = denoteOr ctx b := by
  apply propext
  cases m with
  | none => rw [denoteOr_none a ha, denoteOr_none b hb]
  | some k => rw [denoteOr_iff a ha, denoteOr_iff b hb]

/-! ### Soundness of the exponent-two normal form

The algebra of `XOr` is that of an abelian group of exponent two: `False` is the unit and every
proposition its own inverse. The identities below are propositional tautologies, proved by a case
analysis on the atoms. -/

theorem XOr_eq_or (p q : Prop) : XOr p q = ((p ∧ ¬q) ∨ (¬p ∧ q)) := by
  apply propext
  constructor
  · intro h; exact h.elim (fun hp hnq => .inl ⟨hp, hnq⟩) (fun hnp hq => .inr ⟨hnp, hq⟩)
  · rintro (⟨hp, hnq⟩ | ⟨hnp, hq⟩)
    · exact .inl hp hnq
    · exact .inr hnp hq

theorem XOr_false_right (p : Prop) : XOr p False = p := by
  rw [XOr_eq_or]; by_cases hp : p <;> simp [hp]

theorem XOr_false_left (p : Prop) : XOr False p = p := by
  rw [XOr_eq_or]; by_cases hp : p <;> simp [hp]

theorem XOr_self (p : Prop) : XOr p p = False := by
  rw [XOr_eq_or]; by_cases hp : p <;> simp [hp]

/-- The interchange law, from associativity and commutativity: the leaves of two layers may be
regrouped in any way. -/
theorem XOr_interchange (a b c d : Prop) : XOr (XOr a b) (XOr c d) = XOr (XOr a c) (XOr b d) := by
  simp only [XOr_eq_or]
  by_cases ha : a <;> by_cases hb : b <;> by_cases hc : c <;> by_cases hd : d <;> simp [ha, hb, hc, hd]

/-- The parity of the atoms `ctx i`, `i < n`, whose bit is set in `m`. -/
def parity (ctx : Context) (m : Nat) : Nat → Prop
  | 0 => False
  | n + 1 => XOr (parity ctx m n) (if m.testBit n then ctx n else False)

theorem parity_zero (ctx : Context) : ∀ n, parity ctx 0 n = False
  | 0 => rfl
  | n + 1 => by
    show XOr (parity ctx 0 n) (if (0 : Nat).testBit n then ctx n else False) = False
    rw [parity_zero ctx n, Nat.zero_testBit]
    simp [XOr_false_right]

theorem parity_xor (ctx : Context) (a b : Nat) : ∀ n,
    parity ctx (a ^^^ b) n = XOr (parity ctx a n) (parity ctx b n)
  | 0 => by
    show False = XOr False False
    rw [XOr_self]
  | n + 1 => by
    show XOr (parity ctx (a ^^^ b) n) (if (a ^^^ b).testBit n then ctx n else False)
      = XOr (XOr (parity ctx a n) (if a.testBit n then ctx n else False))
            (XOr (parity ctx b n) (if b.testBit n then ctx n else False))
    rw [parity_xor ctx a b n, XOr_interchange]
    congr 1
    rw [Nat.testBit_xor]
    cases a.testBit n <;> cases b.testBit n <;> simp [XOr_self, XOr_false_right, XOr_false_left]

/-- Below its own index, the bitset of a single leaf has no bit set. -/
theorem parity_leaf_le (ctx : Context) (i : Nat) : ∀ k, k ≤ i → parity ctx (1 <<< i) k = False
  | 0, _ => rfl
  | k + 1, hk => by
    show XOr (parity ctx (1 <<< i) k) (if (1 <<< i).testBit k then ctx k else False) = False
    rw [parity_leaf_le ctx i k (Nat.le_of_succ_le hk)]
    have hne : (1 <<< i).testBit k = false := by
      cases h : (1 <<< i).testBit k
      · rfl
      · exact absurd (testBit_one_shiftLeft.mp h) (Nat.ne_of_lt hk)
    rw [hne]
    simp [XOr_false_right]

theorem parity_leaf (ctx : Context) (i : Nat) : ∀ n, i < n → parity ctx (1 <<< i) n = ctx i
  | 0, h => absurd h (Nat.not_lt_zero i)
  | n + 1, h => by
    show XOr (parity ctx (1 <<< i) n) (if (1 <<< i).testBit n then ctx n else False) = ctx i
    rcases Nat.lt_or_eq_of_le (Nat.lt_succ_iff.mp h) with hlt | heq
    · rw [parity_leaf ctx i n hlt]
      have hne : (1 <<< i).testBit n = false := by
        cases h : (1 <<< i).testBit n
        · rfl
        · exact absurd (testBit_one_shiftLeft.mp h).symm (Nat.ne_of_lt hlt)
      rw [hne]
      simp [XOr_false_right]
    · subst heq
      rw [parity_leaf_le ctx i i (Nat.le_refl i), testBit_one_shiftLeft.mpr rfl]
      simp [XOr_false_left]

theorem denoteXor_parity {ctx : Context} : ∀ (t : Tree) {n : Nat}, bound t ≤ n →
    denoteXor ctx t = parity ctx (xbits t) n
  | unit, n, _ => by
    show False = parity ctx 0 n
    rw [parity_zero]
  | absorb, n, _ => by
    show False = parity ctx 0 n
    rw [parity_zero]
  | leaf i, n, h => by
    show ctx i = parity ctx (1 <<< i) n
    rw [parity_leaf ctx i n h]
  | node l r, n, h => by
    show XOr (denoteXor ctx l) (denoteXor ctx r) = parity ctx (xbits l ^^^ xbits r) n
    have hn := Nat.max_le.mp h
    rw [parity_xor, denoteXor_parity l hn.1, denoteXor_parity r hn.2]

/-- Two `xor` layers with the same parity normal form `m` (over a bound `n` above both trees'
leaves) denote the same proposition. -/
theorem denoteXor_eq (ctx : Context) (a b : Tree) (n m : Nat)
    (ha : Nat.ble (bound a) n = true) (hb : Nat.ble (bound b) n = true)
    (hxa : xbits a = m) (hxb : xbits b = m) : denoteXor ctx a = denoteXor ctx b := by
  rw [denoteXor_parity a (Nat.le_of_ble_eq_true ha), denoteXor_parity b (Nat.le_of_ble_eq_true hb),
    hxa, hxb]

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
`unit`, its annihilator `absorb`, everything else is an atom. -/
partial def reifyLayer (conj : Bool) (e : Expr) : ReifyM Tree := do
  match_expr e with
  | True => return if conj then .unit else .absorb
  | False => return if conj then .absorb else .unit
  | And a b =>
    if conj then return .node (← reifyLayer conj a) (← reifyLayer conj b) else atom e
  | Or a b =>
    if conj then atom e else return .node (← reifyLayer conj a) (← reifyLayer conj b)
  | _ => atom e
where
  atom (e : Expr) : ReifyM Tree := return .leaf (← getAtom e)

/-- Reify the `xor` layer at the top of `e`: nested `XOr`s are reified recursively, `False` (the
unit) becomes `unit`, everything else is an atom. -/
partial def reifyXor (e : Expr) : ReifyM Tree := do
  match_expr e with
  | False => return .unit
  | XOr a b => return .node (← reifyXor a) (← reifyXor b)
  | _ => return .leaf (← getAtom e)

-- Raw literals throughout, so that the kernel compares the normal forms literal by literal.
def Tree.toExpr : Tree → Expr
  | .unit => mkConst ``Tree.unit
  | .absorb => mkConst ``Tree.absorb
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

/-- Whether either side of `l = r` is an `xor`. -/
def topXor? (l r : Expr) : Bool :=
  (match_expr l with | XOr _ _ => true | _ => false)
  || (match_expr r with | XOr _ _ => true | _ => false)

/-- The context of atoms as an expression: `RArray.get` over the atoms, or a constant when there
are none. -/
def mkContext (atoms : Array Expr) : MetaM Q(Context) := do
  if h : 0 < atoms.size then
    let is : Q(RArray Prop) ← (RArray.ofArray atoms h).toExpr q(Prop) id
    pure q(«$is».get)
  else pure q(fun _ => False)

/-- The `Option Nat` normal form as an expression of raw literals. -/
def optNatExpr : Option Nat → Expr
  | none => mkApp (mkConst ``Option.none [.zero]) (mkConst ``Nat)
  | some m => mkApp2 (mkConst ``Option.some [.zero]) (mkConst ``Nat) (mkRawNatLit m)

-- `Tree.bits`/`Tree.xbits`/`Tree.bound` below are this module's own non-`meta` functions, which
-- the phase-distinction check only allows within a single module under this option.
set_option compiler.relaxedMetaCheck true in
/-- Prove `l = r` when the two sides are equal modulo the laws of the bounded semilattice of their
top connective: associativity, commutativity, idempotence, its neutral element and its
annihilator. Throws if they are not. -/
def proveEq (l r : Expr) : MetaM Expr := do
  let some conj := topConnective? l r
    | throwError "[aci_norm] neither side has a top-level connective:{indentExpr l}\n={indentExpr r}"
  let (tl, s) ← (reifyLayer conj l).run {}
  let (tr, s) ← (reifyLayer conj r).run s
  let m := tl.bits
  unless m == tr.bits do
    throwError "[aci_norm] the two sides have different normal forms:{indentExpr l}\n={indentExpr r}"
  let ctx ← mkContext s.atoms
  let mE := optNatExpr m
  let refl := mkApp2 (mkConst ``Eq.refl [1]) (mkApp (mkConst ``Option [.zero]) (mkConst ``Nat)) mE
  let thm := if conj then ``Tree.denoteAnd_eq else ``Tree.denoteOr_eq
  -- `Tree.denoteAnd ctx tl` unfolds to `l` (and likewise for `r`), which the kernel checks
  return mkAppN (mkConst thm) #[ctx, tl.toExpr, tr.toExpr, mE, refl, refl]

set_option compiler.relaxedMetaCheck true in
/-- Prove `l = r` when the two sides are `xor` layers equal modulo associativity, commutativity,
the neutral element `False` and the cancellation `XOr p p = False`. Throws if they are not. -/
def proveXorEq (l r : Expr) : MetaM Expr := do
  unless topXor? l r do
    throwError "[xor_norm] neither side has a top-level xor:{indentExpr l}\n={indentExpr r}"
  let (tl, s) ← (reifyXor l).run {}
  let (tr, s) ← (reifyXor r).run s
  let m := tl.xbits
  unless m == tr.xbits do
    throwError "[xor_norm] the two sides have different parities:{indentExpr l}\n={indentExpr r}"
  let ctx ← mkContext s.atoms
  let n := max tl.bound tr.bound
  let nE := mkRawNatLit n
  let mE := mkRawNatLit m
  let reflNat (e : Expr) := mkApp2 (mkConst ``Eq.refl [1]) (mkConst ``Nat) e
  let reflTrue := mkApp2 (mkConst ``Eq.refl [1]) (mkConst ``Bool) (mkConst ``Bool.true)
  return mkAppN (mkConst ``Tree.denoteXor_eq)
    #[ctx, tl.toExpr, tr.toExpr, nE, mE, reflTrue, reflTrue, reflNat mE, reflNat mE]

/-- Close a goal `l = r` with `proveEq`. -/
def aciNorm (mv : MVarId) : MetaM Unit := do
  let some (_, l, r) := (← mv.getType).eq?
    | throwError "[aci_norm] expected an equality, got {← mv.getType}"
  mv.assign (← proveEq l r)

/-- Close a goal `l = r` with `proveXorEq`. -/
def xorNorm (mv : MVarId) : MetaM Unit := do
  let some (_, l, r) := (← mv.getType).eq?
    | throwError "[xor_norm] expected an equality, got {← mv.getType}"
  mv.assign (← proveXorEq l r)

end Smt.Reconstruct.Prop.AciNorm

end
