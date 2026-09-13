/-
Copyright (c) 2021-2026 by the authors listed in the file AUTHORS and their
institutional affiliations. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Haniel Barbosa
-/

module

public import Lean
public meta import Lean

@[expose] public section

/-!
# Projecting out of a right-nested `∧` or `¬∨` chain

`reconstructTerm` sends an n-ary `AND` to the right-nested `p₀ ∧ (p₁ ∧ … ∧ pₙ₋₁)`
(`Smt.Reconstruct.Prop.reconstructTerm`, the `.AND` case), which is *definitionally* `andN
[p₀, …, pₙ₋₁]` but only after `n` unfoldings of `andN`. So a rule that projects the `i`-th
conjunct by way of `andN` and `List.getElem` makes the kernel pay for the whole conjunction
at every step: `n` unfoldings to reconcile the hypothesis's stated type with `andN`, a
`decide` of `i < ps.length` over an `n`-element literal, and `i` reductions of `getElem`.

Projecting structurally instead costs nothing to reduce. The hypothesis's type is *already*
headed by `And`, so `And.right` applies with no unfolding at all, and the conjunct that
comes out is the very `Expr` the conclusion was built from — `reconstructTerm` memoises, so
the two are pointer-equal and the kernel's defeq check is a pointer hit.

`ProjChain` keeps the partially unrolled spine so that a step projecting many indices out of
one hypothesis (`distinct_elim`'s conversion, say) builds `O(n)` nodes in total rather than
a fresh chain of length `i` per index.
-/

namespace Smt.Reconstruct.Prop

open Lean

/-- `¬(a ∨ b) → ¬a`. The `∨` counterpart of `And.left`: stated so that projecting out of a
    negated disjunction is an application spine, shareable exactly like the `∧` one, rather
    than a fresh lambda per index. -/
theorem notOrLeft {a b : Prop} (h : ¬(a ∨ b)) : ¬a := fun ha => h (.inl ha)

/-- `¬(a ∨ b) → ¬b`. The `∨` counterpart of `And.right`; see `notOrLeft`. -/
theorem notOrRight {a b : Prop} (h : ¬(a ∨ b)) : ¬b := fun hb => h (.inr hb)

/-- `¬a ∨ a`: the CNF axiom of a one-element chain, and the whole of `or_pos`, whose stated
    clause `(cl (not P) q₀ … qₙ₋₁)` *is* `¬P ∨ P` once the disjuncts are re-associated. -/
theorem notOrSelf {a : Prop} : ¬a ∨ a := (Classical.em a).symm

/-- The head case of `and_pos`. -/
theorem cnfAndPosHead {a b : Prop} : ¬(a ∧ b) ∨ a := (Classical.em a).symm.imp (· ∘ And.left) id

/-- One `∧` layer of `and_pos`: the conjunct stays reachable under a wider conjunction. -/
theorem cnfAndPosTail {a b c : Prop} (h : ¬b ∨ c) : ¬(a ∧ b) ∨ c := h.imp (· ∘ And.right) id

/-- The head case of `or_neg`. -/
theorem cnfOrNegHead {a b : Prop} : (a ∨ b) ∨ ¬a := (Classical.em a).imp .inl id

/-- One `∨` layer of `or_neg`. -/
theorem cnfOrNegTail {a b c : Prop} (h : b ∨ ¬c) : (a ∨ b) ∨ ¬c := h.imp .inr id

/-- One layer of `and_neg`: `(cl (and ps) (not p₀) … (not pₙ₋₁))`, peeled from the left. -/
theorem cnfAndNegTail {a b d : Prop} (h : b ∨ d) : (a ∧ b) ∨ (¬a ∨ d) :=
  (Classical.em a).elim (fun ha => h.imp (⟨ha, ·⟩) (.inr ·)) (.inr ∘ .inl)

/-- Which chain a `ProjChain` walks: `p₀ ∧ (p₁ ∧ …)` from a proof of it, or `q₀ ∨ (q₁ ∨ …)`
    from a proof of its negation. -/
inductive ProjKind where
  | and
  | notOr
deriving Inhabited, BEq

/-- A right-nested `∧`/`∨` chain of `n` elements, unrolled as far as it has been needed:
    `tys[j]` is the `j`-th suffix `pⱼ ∧ (pⱼ₊₁ ∧ …)` and `prfs[j]` proves it (or, for
    `.notOr`, proves its negation). `tys[0]`/`prfs[0]` are what the chain was built from.

    `n` is the arity *stated by the proof*, and it alone decides where the chain stops: a
    conjunct may itself be a conjunction, so the last element cannot be recognised by shape.
    See `ProjChain.proj`. -/
structure ProjChain where
  kind : ProjKind
  /-- The number of elements of the chain, from the rule's own arity — never inferred from
      the shape of the type. -/
  n : Nat
  tys : Array Expr
  prfs : Array Expr
deriving Inhabited

namespace ProjChain

/-- The chain of `n` elements that `h : ty` (`.and`) or `h : ¬ty` (`.notOr`) heads. `ty` must
    be the *stated* type of `h`, not one inferred from it: the arguments of the projections
    are then shared with the type the hypothesis was declared with, which is what makes the
    kernel's check on each of them a pointer comparison. -/
def of (kind : ProjKind) (h ty : Expr) (n : Nat) : ProjChain :=
  { kind, n, tys := #[ty], prfs := #[h] }

/-- Split the `j`-th suffix into its head and its tail. -/
def split (kind : ProjKind) (ty : Expr) : Option (Expr × Expr) :=
  match kind with
  | .and => ty.consumeMData.and?
  | .notOr => ty.consumeMData.app2? ``Or

/-- Unroll the chain until `prfs[i]` exists. -/
def unrollTo (c : ProjChain) (i : Nat) : MetaM ProjChain := do
  let mut c := c
  while c.prfs.size ≤ i do
    let j := c.prfs.size - 1
    let some (a, b) := split c.kind c.tys[j]!
      | throwError "expected a chain of {c.n} elements, but element {j} is not a \
                    {if c.kind == ProjKind.and then "conjunction" else "disjunction"}:\
                    {indentExpr c.tys[j]!}"
    let thm := if c.kind == ProjKind.and then ``And.right else ``notOrRight
    c := { c with tys := c.tys.push b, prfs := c.prfs.push (mkApp3 (mkConst thm) a b c.prfs[j]!) }
  return c

/-- A proof of the `i`-th element of the chain (of its negation, for `.notOr`), together with
    the chain unrolled far enough to have produced it — pass that on to the next projection
    out of the same hypothesis and the spine is built once, not once per index.

    The last element is the one the chain *ends* at, so it is taken from the arity `c.n` and
    never from the shape of the type: `andN` leaves the last conjunct bare, and that conjunct
    may itself be a conjunction. -/
def proj (c : ProjChain) (i : Nat) : MetaM (Expr × ProjChain) := do
  if i ≥ c.n then
    throwError "element {i} of a chain of {c.n}"
  let c ← c.unrollTo i
  let pr := c.prfs[i]!
  -- the last element is bare: `p₀ ∧ (p₁ ∧ p₂)` ends at `p₂`, with nothing to project off it
  if i + 1 == c.n then
    return (pr, c)
  let some (a, b) := split c.kind c.tys[i]!
    | throwError "element {i} of {c.n} is not a \
                  {if c.kind == ProjKind.and then "conjunction" else "disjunction"}:\
                  {indentExpr c.tys[i]!}"
  let thm := if c.kind == ProjKind.and then ``And.left else ``notOrLeft
  return (mkApp3 (mkConst thm) a b pr, c)

end ProjChain

/-- A proof of the `i`-th of the `n` conjuncts of `ty`, from `h : ty`. For several
    projections out of one `h`, thread a `ProjChain` instead. -/
def mkAndProj (h ty : Expr) (n i : Nat) : MetaM Expr :=
  return (← (ProjChain.of .and h ty n).proj i).1

/-- A proof of the negation of the `i`-th of the `n` disjuncts of `ty`, from `h : ¬ty`. For
    several projections out of one `h`, thread a `ProjChain` instead. -/
def mkNotOrProj (h ty : Expr) (n i : Nat) : MetaM Expr :=
  return (← (ProjChain.of .notOr h ty n).proj i).1

/-- The `n` suffixes of a right-nested chain: `tys[0] = ty`, `tys[j+1]` is the tail of `tys[j]`,
    and `tys[n-1]` is the last element itself (never split further — see `ProjChain.proj`). -/
def suffixes (kind : ProjKind) (ty : Expr) (n : Nat) : MetaM (Array Expr) := do
  let mut tys := #[ty]
  for j in [0:n-1] do
    let some (_, b) := ProjChain.split kind tys[j]!
      | throwError "expected a chain of {n} elements, but element {j} is not a \
                    {if kind == ProjKind.and then "conjunction" else "disjunction"}:\
                    {indentExpr tys[j]!}"
    tys := tys.push b
  return tys

/-- `and_pos`: a proof of `¬ty ∨ pᵢ`, where `ty` is the `n`-conjunct chain `p₀ ∧ (p₁ ∧ …)`.
    `i + 1` nodes, against a `List Prop` plus a `getD` reduction per step. -/
def mkCnfAndPos (ty : Expr) (n i : Nat) : MetaM Expr := do
  if i ≥ n then throwError "element {i} of a chain of {n}"
  let tys ← suffixes .and ty n
  -- at the i-th suffix the conjunct is the head, unless it is the last, where it is all there is
  let (pᵢ, pr₀) ← if i + 1 == n then
      pure (tys[i]!, mkApp (mkConst ``notOrSelf) tys[i]!)
    else do
      let some (a, b) := ProjChain.split .and tys[i]! | throwError "element {i} of {n} is not a conjunction"
      pure (a, mkApp2 (mkConst ``cnfAndPosHead) a b)
  -- widen it back out through the conjuncts to its left
  let mut pr := pr₀
  for j in [0:i] do
    let j := i - 1 - j
    let some (a, b) := ProjChain.split .and tys[j]! | throwError "element {j} of {n} is not a conjunction"
    pr := mkApp4 (mkConst ``cnfAndPosTail) a b pᵢ pr
  return pr

/-- `or_neg`: a proof of `ty ∨ ¬qᵢ`, where `ty` is the `n`-disjunct chain `q₀ ∨ (q₁ ∨ …)`. -/
def mkCnfOrNeg (ty : Expr) (n i : Nat) : MetaM Expr := do
  if i ≥ n then throwError "element {i} of a chain of {n}"
  let tys ← suffixes .notOr ty n
  let (qᵢ, pr₀) ← if i + 1 == n then
      pure (tys[i]!, mkApp (mkConst ``Classical.em) tys[i]!)
    else do
      let some (a, b) := ProjChain.split .notOr tys[i]! | throwError "element {i} of {n} is not a disjunction"
      pure (a, mkApp2 (mkConst ``cnfOrNegHead) a b)
  let mut pr := pr₀
  for j in [0:i] do
    let j := i - 1 - j
    let some (a, b) := ProjChain.split .notOr tys[j]! | throwError "element {j} of {n} is not a disjunction"
    pr := mkApp4 (mkConst ``cnfOrNegTail) a b qᵢ pr
  return pr

/-- `and_neg`: a proof of `ty ∨ (¬p₀ ∨ (¬p₁ ∨ … ∨ ¬pₙ₋₁))`, where `ty` is the `n`-conjunct
    chain. `O(n)` nodes, none of which the kernel reduces — against `orN (andN ps :: notN ps)`,
    which makes it unfold `notN`'s `List.map` over the whole list. -/
def mkCnfAndNeg (ty : Expr) (n : Nat) : MetaM Expr := do
  if n == 0 then throwError "and_neg: an empty conjunction"
  let tys ← suffixes .and ty n
  -- innermost: `pₙ₋₁ ∨ ¬pₙ₋₁`; then one `∧` layer at a time, each adding its own `¬pⱼ`
  let mut pr := mkApp (mkConst ``Classical.em) tys[n-1]!
  let mut d := mkApp (mkConst ``Not) tys[n-1]!
  for j in [0:n-1] do
    let j := n - 2 - j
    let some (a, b) := ProjChain.split .and tys[j]! | throwError "element {j} of {n} is not a conjunction"
    pr := mkApp4 (mkConst ``cnfAndNegTail) a b d pr
    d := mkApp2 (mkConst ``Or) (mkApp (mkConst ``Not) a) d
  return pr

/-- The dual of `mkAndProj`: a proof of the `n`-element disjunction `ty` from `h`, a proof of
    its `i`-th disjunct, as `Or.inr (… (Or.inl h))`. Built from the inside out, so there is
    nothing to share between indices. -/
def mkOrInj (ty : Expr) (n i : Nat) (h : Expr) : MetaM Expr := do
  if i ≥ n then
    throwError "element {i} of a chain of {n}"
  -- the disjuncts down to `i`, with the `i`-th suffix last
  let mut tys := #[]
  let mut curr := ty
  for j in [0:i] do
    let some (a, b) := curr.consumeMData.app2? ``Or
      | throwError "element {j} of {n} is not a disjunction:{indentExpr curr}"
    tys := tys.push (a, b)
    curr := b
  -- `curr` is the `i`-th suffix; the last disjunct is bare
  let mut pr := h
  if i + 1 != n then
    let some (a, b) := curr.consumeMData.app2? ``Or
      | throwError "element {i} of {n} is not a disjunction:{indentExpr curr}"
    pr := mkApp3 (mkConst ``Or.inl) a b pr
  for (a, b) in tys.reverse do
    pr := mkApp3 (mkConst ``Or.inr) a b pr
  return pr

end Smt.Reconstruct.Prop
