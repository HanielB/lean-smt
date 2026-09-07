/-
Copyright (c) 2021-2026 by the authors listed in the file AUTHORS and their
institutional affiliations. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Haniel Barbosa
-/

module

public import Smt.Reconstruct.Prop.Core
public import Smt.Reconstruct.Prop.Lemmas
public import Smt.Reconstruct.Int.Lemmas
public import Smt.Reconstruct.Rat.Lemmas

@[expose] public section

namespace Smt.Alethe

/-- The clause of a discharged subproof: from `p₁ → … → pₙ → q` conclude `(cl ¬p₁ … ¬pₙ q)`. -/
theorem orN_of_impliesN : ∀ {ps : List Prop} {q : Prop}, impliesN ps q → orN (notN ps ++ [q])
  | [], _, h => h
  | p :: ps, q, h => by
    show orN ((¬p) :: (notN ps ++ [q]))
    rw [orN_cons_append]
    exact match Classical.em p with
    | .inl hp => .inr (orN_of_impliesN (h hp))
    | .inr hnp => .inl hnp

/-- Alethe `not_not`: `(cl (not (not (not p))) p)`. -/
theorem not_not_cl {p : Prop} : ¬¬¬p ∨ p :=
  match Classical.em p with
  | .inl hp => .inr hp
  | .inr hnp => .inl (fun hnnp => hnnp hnp)

/-- Alethe `false`: `(cl (not false))`. -/
theorem not_false_cl : ¬False := id

/-- A clause from the refutation of the negations of its literals (`la_generic`). -/
theorem orN_of_impliesN_not : ∀ {ps : List Prop}, impliesN (notN ps) False → orN ps
  | [], h => h
  | p :: ps, h => by
    show orN (p :: ps)
    rw [orN_cons_append]
    exact match Classical.em p with
    | .inl hp => .inl hp
    | .inr hnp => .inr (orN_of_impliesN_not (h hnp))

/-! ### Farkas contradictions

The summed, scaled bound `a ⋈ b` of an `la_generic` step is refuted through the normalized
difference `a - b = k` (proved by `poly_norm`) and a decidable fact about the constant `k`. -/

theorem Int.farkas_lt {a b k : Int} (h : a < b) (hk : a - b = k) (hk0 : 0 ≤ k) : False :=
  Int.lt_irrefl 0 (Int.lt_of_le_of_lt hk0 (hk ▸ Int.sub_neg_of_lt h))

theorem Int.farkas_le {a b k : Int} (h : a ≤ b) (hk : a - b = k) (hk0 : 0 < k) : False :=
  Int.lt_irrefl 0 (Int.lt_of_lt_of_le hk0 (hk ▸ Int.sub_nonpos_of_le h))

theorem Int.farkas_eq {a b k : Int} (h : a = b) (hk : a - b = k) (hk0 : k ≠ 0) : False :=
  hk0 (hk ▸ h ▸ Int.sub_self a)

theorem Rat.farkas_lt {a b k : Rat} (h : a < b) (hk : a - b = k) (hk0 : 0 ≤ k) : False :=
  have h' : a - b < 0 := Smt.Reconstruct.Rat.lt_eq_sub_lt_zero ▸ h
  Rat.lt_irrefl (Smt.Reconstruct.Rat.lt_of_le_of_lt hk0 (hk ▸ h'))

theorem Rat.farkas_le {a b k : Rat} (h : a ≤ b) (hk : a - b = k) (hk0 : 0 < k) : False :=
  have h' : a - b ≤ 0 := Smt.Reconstruct.Rat.le_eq_sub_le_zero ▸ h
  Rat.lt_irrefl (Smt.Reconstruct.Rat.lt_of_lt_of_le hk0 (hk ▸ h'))

theorem Rat.farkas_eq {a b k : Rat} (h : a = b) (hk : a - b = k) (hk0 : k ≠ 0) : False :=
  hk0 (hk ▸ h ▸ Rat.sub_self)

/-- Alethe `la_disequality`: `(cl (or (= a b) (not (<= a b)) (not (<= b a))))`. -/
theorem Int.la_disequality {a b : Int} : a = b ∨ ¬a ≤ b ∨ ¬b ≤ a :=
  match Classical.em (a ≤ b), Classical.em (b ≤ a) with
  | .inl h₁, .inl h₂ => .inl (Int.le_antisymm h₁ h₂)
  | .inr h₁, _ => .inr (.inl h₁)
  | _, .inr h₂ => .inr (.inr h₂)

theorem Rat.la_disequality {a b : Rat} : a = b ∨ ¬a ≤ b ∨ ¬b ≤ a :=
  match Classical.em (a ≤ b), Classical.em (b ≤ a) with
  | .inl h₁, .inl h₂ => .inl (Smt.Reconstruct.Rat.trichotomy₂ h₁ h₂)
  | .inr h₁, _ => .inr (.inl h₁)
  | _, .inr h₂ => .inr (.inr h₂)

/-- Alethe `la_totality`: `(cl (or (<= a b) (<= b a)))`. -/
theorem Int.la_totality {a b : Int} : a ≤ b ∨ b ≤ a :=
  match Classical.em (a ≤ b) with
  | .inl h => .inl h
  | .inr h => .inr (Int.le_of_lt (Int.not_le.mp h))

theorem Rat.la_totality {a b : Rat} : a ≤ b ∨ b ≤ a :=
  match Classical.em (a ≤ b) with
  | .inl h => .inl h
  | .inr h => .inr (Rat.le_of_lt (Rat.not_le.mp h))

/-! ### `poly_simp_rel` with two integer sides and a rational coefficient -/

namespace Rat

open Smt.Reconstruct.Rat in
theorem lt_of_sub_eq_pos_int {a₁ a₂ b₁ b₂ : Int} {c₁ c₂ : Rat} (hc₁ : c₁ > 0) (hc₂ : c₂ > 0)
    (h : c₁ * ↑(a₁ - a₂) = c₂ * ↑(b₁ - b₂)) : (a₁ < a₂) = (b₁ < b₂) := by
  rw [lt_of_sub_eq_pos_int_left hc₁ hc₂ (by rw [h, Rat.intCast_sub])]
  exact propext Rat.intCast_lt_intCast

open Smt.Reconstruct.Rat in
theorem lt_of_sub_eq_neg_int {a₁ a₂ b₁ b₂ : Int} {c₁ c₂ : Rat} (hc₁ : c₁ < 0) (hc₂ : c₂ < 0)
    (h : c₁ * ↑(a₁ - a₂) = c₂ * ↑(b₁ - b₂)) : (a₁ < a₂) = (b₁ < b₂) := by
  rw [lt_of_sub_eq_neg_int_left hc₁ hc₂ (by rw [h, Rat.intCast_sub])]
  exact propext Rat.intCast_lt_intCast

open Smt.Reconstruct.Rat in
theorem le_of_sub_eq_pos_int {a₁ a₂ b₁ b₂ : Int} {c₁ c₂ : Rat} (hc₁ : c₁ > 0) (hc₂ : c₂ > 0)
    (h : c₁ * ↑(a₁ - a₂) = c₂ * ↑(b₁ - b₂)) : (a₁ ≤ a₂) = (b₁ ≤ b₂) := by
  rw [le_of_sub_eq_pos_int_left hc₁ hc₂ (by rw [h, Rat.intCast_sub])]
  exact propext Rat.intCast_le_intCast

open Smt.Reconstruct.Rat in
theorem le_of_sub_eq_neg_int {a₁ a₂ b₁ b₂ : Int} {c₁ c₂ : Rat} (hc₁ : c₁ < 0) (hc₂ : c₂ < 0)
    (h : c₁ * ↑(a₁ - a₂) = c₂ * ↑(b₁ - b₂)) : (a₁ ≤ a₂) = (b₁ ≤ b₂) := by
  rw [le_of_sub_eq_neg_int_left hc₁ hc₂ (by rw [h, Rat.intCast_sub])]
  exact propext Rat.intCast_le_intCast

open Smt.Reconstruct.Rat in
theorem eq_of_sub_eq_int {a₁ a₂ b₁ b₂ : Int} {c₁ c₂ : Rat} (hc₁ : c₁ ≠ 0) (hc₂ : c₂ ≠ 0)
    (h : c₁ * ↑(a₁ - a₂) = c₂ * ↑(b₁ - b₂)) : (a₁ = a₂) = (b₁ = b₂) := by
  rw [eq_of_sub_eq_int_left hc₁ hc₂ (by rw [h, Rat.intCast_sub])]
  exact propext Rat.intCast_inj

open Smt.Reconstruct.Rat in
theorem ge_of_sub_eq_pos_int {a₁ a₂ b₁ b₂ : Int} {c₁ c₂ : Rat} (hc₁ : c₁ > 0) (hc₂ : c₂ > 0)
    (h : c₁ * ↑(a₁ - a₂) = c₂ * ↑(b₁ - b₂)) : (a₁ ≥ a₂) = (b₁ ≥ b₂) := by
  rw [ge_of_sub_eq_pos_int_left hc₁ hc₂ (by rw [h, Rat.intCast_sub])]
  exact propext Rat.intCast_le_intCast

open Smt.Reconstruct.Rat in
theorem ge_of_sub_eq_neg_int {a₁ a₂ b₁ b₂ : Int} {c₁ c₂ : Rat} (hc₁ : c₁ < 0) (hc₂ : c₂ < 0)
    (h : c₁ * ↑(a₁ - a₂) = c₂ * ↑(b₁ - b₂)) : (a₁ ≥ a₂) = (b₁ ≥ b₂) := by
  rw [ge_of_sub_eq_neg_int_left hc₁ hc₂ (by rw [h, Rat.intCast_sub])]
  exact propext Rat.intCast_le_intCast

open Smt.Reconstruct.Rat in
theorem gt_of_sub_eq_pos_int {a₁ a₂ b₁ b₂ : Int} {c₁ c₂ : Rat} (hc₁ : c₁ > 0) (hc₂ : c₂ > 0)
    (h : c₁ * ↑(a₁ - a₂) = c₂ * ↑(b₁ - b₂)) : (a₁ > a₂) = (b₁ > b₂) := by
  rw [gt_of_sub_eq_pos_int_left hc₁ hc₂ (by rw [h, Rat.intCast_sub])]
  exact propext Rat.intCast_lt_intCast

open Smt.Reconstruct.Rat in
theorem gt_of_sub_eq_neg_int {a₁ a₂ b₁ b₂ : Int} {c₁ c₂ : Rat} (hc₁ : c₁ < 0) (hc₂ : c₂ < 0)
    (h : c₁ * ↑(a₁ - a₂) = c₂ * ↑(b₁ - b₂)) : (a₁ > a₂) = (b₁ > b₂) := by
  rw [gt_of_sub_eq_neg_int_left hc₁ hc₂ (by rw [h, Rat.intCast_sub])]
  exact propext Rat.intCast_lt_intCast

end Rat

/-! ### Clause reindexing (`contraction`, `reordering`, resolution fix-ups)

From `orN ps`, where every literal of `ps` is a literal of `qs` (given by the index map `g`),
conclude `orN qs`. The hypothesis on `g` is a Boolean computation the kernel evaluates; the source
clause is stated as `g.map (qs.getD · False)`, which reduces to `ps` literal by literal. -/

theorem orN_of_getElem : ∀ {qs : List Prop} (i : Nat) (hi : i < qs.length), qs[i] → orN qs
  | [], _, hi, _ => absurd hi (Nat.not_lt_zero _)
  | q :: qs, 0, _, h => by rw [orN_cons_append]; exact .inl h
  | _ :: qs, i + 1, hi, h => by
    rw [orN_cons_append]
    exact .inr (orN_of_getElem (qs := qs) i (Nat.lt_of_succ_lt_succ hi) h)

theorem orN_of_map {qs : List Prop} : ∀ (g : List Nat),
    g.all (fun j => decide (j < qs.length)) = true →
    orN (g.map fun j => qs.getD j False) → orN qs
  | [], _, h => h.elim
  | j :: g, hb, h => by
    rw [List.map_cons, orN_cons_append] at h
    have hb' := List.all_eq_true.mp hb
    have hj : j < qs.length := of_decide_eq_true (hb' j (List.mem_cons_self ..))
    exact match h with
    | .inl hq => orN_of_getElem j hj (by rwa [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem hj] at hq)
    | .inr hg => orN_of_map g (List.all_eq_true.mpr fun k hk => hb' k (List.mem_cons_of_mem _ hk)) hg

/-! ### Skolemization (`sko_ex`, `sko_forall`) -/

theorem sko_ex_eq {α : Sort u} [h : Nonempty α] (p : α → Prop) :
    (∃ x, p x) = p (@Classical.epsilon α h p) :=
  propext ⟨fun hp => Classical.epsilon_spec hp, fun hp => ⟨_, hp⟩⟩

theorem sko_forall_eq {α : Sort u} [h : Nonempty α] (p : α → Prop) :
    (∀ x, p x) = p (@Classical.epsilon α h fun x => ¬p x) :=
  propext ⟨fun hp => hp _, fun hp => fun x => Classical.byContradiction fun hn =>
    (Classical.epsilon_spec (p := fun x => ¬p x) ⟨x, hn⟩) hp⟩

/-! ### `onepoint` -/

theorem onepoint_forall {α : Sort u} {t : α} {p : α → Prop} {q : Prop}
    (h : ∀ x, x ≠ t → p x) (heq : p t = q) : (∀ x, p x) = q :=
  propext ⟨fun hp => Eq.mp heq (hp t), fun hq x =>
    match Classical.em (x = t) with
    | .inl hx => Eq.mpr (congrArg p hx) (Eq.mpr heq hq)
    | .inr hx => h x hx⟩

theorem onepoint_exists {α : Sort u} {t : α} {p : α → Prop} {q : Prop}
    (h : ∀ x, p x → x = t) (heq : p t = q) : (∃ x, p x) = q :=
  propext ⟨fun ⟨x, hx⟩ => Eq.mp heq (Eq.mp (congrArg p (h x hx)) hx), fun hq => ⟨t, Eq.mpr heq hq⟩⟩

/-! ### RARE rules newer than lean-cvc5's enumeration -/

/-- `or-not-refl`: `(or (not (= t t)) xs) = (or xs)`. -/
theorem or_not_refl {α : Sort u} (t : α) (ps : List Prop) : orN ((¬t = t) :: ps) = orN ps := by
  cases ps with
  | nil => exact propext ⟨fun h => h rfl, fun h => h.elim⟩
  | cons p ps => exact propext ⟨fun h => h.elim (fun h => (h rfl).elim) id, fun h => .inr h⟩

/-! ### veriT rules: `la_rw_eq`, `comp_simplify` -/

theorem Int.la_rw_eq {a b : Int} : (a = b) = (a ≤ b ∧ b ≤ a) :=
  propext ⟨fun h => ⟨Int.le_of_eq h, Int.le_of_eq h.symm⟩, fun ⟨h₁, h₂⟩ => Int.le_antisymm h₁ h₂⟩

theorem Rat.la_rw_eq {a b : Rat} : (a = b) = (a ≤ b ∧ b ≤ a) :=
  propext ⟨fun h => ⟨h ▸ Rat.le_refl, h ▸ Rat.le_refl⟩,
    fun ⟨h₁, h₂⟩ => Smt.Reconstruct.Rat.trichotomy₂ h₁ h₂⟩

theorem Int.lt_eq_not_le {a b : Int} : (a < b) = ¬b ≤ a := propext Int.not_le.symm
theorem Rat.lt_eq_not_le {a b : Rat} : (a < b) = ¬b ≤ a := propext Rat.not_le.symm
theorem Int.le_eq_not_lt {a b : Int} : (a ≤ b) = ¬b < a := propext Int.not_lt.symm
theorem Rat.le_eq_not_lt {a b : Rat} : (a ≤ b) = ¬b < a := propext Rat.not_lt.symm
theorem Int.le_self_eq_true {a : Int} : (a ≤ a) = True := eq_true (Int.le_refl a)
theorem Rat.le_self_eq_true {a : Rat} : (a ≤ a) = True := eq_true Rat.le_refl
theorem Int.lt_self_eq_false {a : Int} : (a < a) = False := eq_false (Int.lt_irrefl a)
theorem Rat.lt_self_eq_false {a : Rat} : (a < a) = False := eq_false Rat.lt_irrefl

/-! ### Generalized `bind`: a clause derived under the bound variables -/

/-- From `∀ x, (cl ps (ψ x))`, where the literals `ps` do not depend on `x`, conclude
    `(cl ps (∀ x, ψ x))`. -/
theorem orN_forall {α : Sort u} : ∀ (ps : List Prop) {ψ : α → Prop},
    (∀ x, orN (ps ++ [ψ x])) → orN (ps ++ [∀ x, ψ x])
  | [], _, h => h
  | p :: ps, ψ, h => by
    show orN (p :: (ps ++ [∀ x, ψ x]))
    rw [orN_cons_append]
    exact match Classical.em p with
    | .inl hp => .inl hp
    | .inr hnp => .inr (orN_forall ps fun x => by
        have hx := h x
        rw [List.cons_append, orN_cons_append] at hx
        exact hx.resolve_left hnp)

/-! ### Tautologies and contradictions with complementary literals (`or_simplify`, `and_simplify`) -/

theorem orN_eq_true_of_compl {ps : List Prop} (i j : Nat) (hi : i < ps.length) (hj : j < ps.length)
    (h : ps[j] = ¬ps[i]) : orN ps = True :=
  eq_true (match Classical.em ps[i] with
    | .inl hp => orN_of_getElem i hi hp
    | .inr hn => orN_of_getElem j hj (h ▸ hn))

theorem orN_eq_true_of_true {ps : List Prop} (i : Nat) (hi : i < ps.length) (h : ps[i] = True) :
    orN ps = True :=
  eq_true (orN_of_getElem i hi (h ▸ trivial))

theorem andN_eq_false_of_compl {ps : List Prop} (i j : Nat) (hi : i < ps.length) (hj : j < ps.length)
    (h : ps[j] = ¬ps[i]) : andN ps = False :=
  eq_false fun hps => (h ▸ (Smt.Reconstruct.Prop.and_elim hps j (hi := hj))) (Smt.Reconstruct.Prop.and_elim hps i (hi := hi))

theorem andN_eq_false_of_false {ps : List Prop} (i : Nat) (hi : i < ps.length) (h : ps[i] = False) :
    andN ps = False :=
  eq_false fun hps => h ▸ (Smt.Reconstruct.Prop.and_elim hps i (hi := hi))

end Smt.Alethe
