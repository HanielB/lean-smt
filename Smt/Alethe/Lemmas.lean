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

/-! ### `qnt_simplify`: a quantifier over a Boolean constant -/

theorem qnt_forall_true {α : Sort u} : (∀ _ : α, True) = True :=
  propext ⟨fun _ => trivial, fun _ _ => trivial⟩

theorem qnt_forall_false {α : Sort u} [h : Nonempty α] : (∀ _ : α, False) = False :=
  propext ⟨fun f => h.elim f, False.elim⟩

theorem qnt_exists_true {α : Sort u} [h : Nonempty α] : (∃ _ : α, True) = True :=
  propext ⟨fun _ => trivial, fun _ => h.elim fun x => ⟨x, trivial⟩⟩

theorem qnt_exists_false {α : Sort u} : (∃ _ : α, False) = False :=
  propext ⟨fun h => h.elim fun _ hf => hf, False.elim⟩

/-! ### veriT rules: `la_rw_eq`, `comp_simplify` -/

theorem Int.la_rw_eq {a b : Int} : (a = b) = (a ≤ b ∧ b ≤ a) :=
  propext ⟨fun h => ⟨Int.le_of_eq h, Int.le_of_eq h.symm⟩, fun ⟨h₁, h₂⟩ => Int.le_antisymm h₁ h₂⟩

theorem Rat.la_rw_eq {a b : Rat} : (a = b) = (a ≤ b ∧ b ≤ a) :=
  propext ⟨fun h => ⟨h ▸ Rat.le_refl, h ▸ Rat.le_refl⟩,
    fun ⟨h₁, h₂⟩ => Smt.Reconstruct.Rat.trichotomy₂ h₁ h₂⟩


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

/-! Integer strengthening in `la_generic`: a bound whose coefficients share a factor `g` is divided
by `g`, its constant rounded. -/

theorem le_of_sub_eq_sub {a b c d : Int} (h : a ≤ b) (heq : a - b = c - d) : c ≤ d := by omega
theorem eq_of_sub_eq_sub {a b c d : Int} (h : a = b) (heq : a - b = c - d) : c = d := by omega
theorem le_of_le_of_eq' {a b c : Int} (h : a ≤ b) (e : b = c) : a ≤ c := e ▸ h
theorem eq_of_eq_of_eq' {a b c : Int} (h : a = b) (e : b = c) : a = c := e ▸ h

/-! The `div_intro` and `div_by_zero_intro` rules (cvc5's introduction of integer division and
of division by a possibly-zero denominator). -/

theorem div_intro_pos {a b : Int} (h : b > 0) : b * (a / b) ≤ a ∧ a < b * (a / b + 1) :=
  ⟨Int.mul_ediv_self_le (Int.ne_of_gt h), by
    rw [Int.mul_add, Int.mul_one]; exact Int.lt_mul_ediv_self_add h⟩

theorem div_intro_neg {a b : Int} (h : b < 0) : b * (a / b) ≤ a ∧ a < b * (a / b + -1) := by
  have hc : -b > 0 := by omega
  have h1 := Int.mul_ediv_self_le (x := a) (Int.ne_of_gt hc)
  have h2 := Int.lt_mul_ediv_self_add (x := a) hc
  rw [Int.ediv_neg, Int.neg_mul_neg] at h1 h2
  exact ⟨h1, by rw [Int.mul_add, Int.mul_neg, Int.mul_one]; exact h2⟩

theorem div_intro_real {a b : Rat} (h : ¬b = 0) : b * (a / b) = a := by
  rw [Rat.mul_comm]; exact Rat.div_mul_cancel h

theorem div_by_zero_intro {α : Sort u} {β : Sort v} (inst : Nonempty α) (f : β → α) (b z : β)
    [Decidable (b = z)] : f b = ite (b = z) (@Classical.epsilon α inst fun y => y = f z) (f b) := by
  by_cases h : b = z
  · rw [if_pos h, h]
    exact (Classical.epsilon_spec_aux inst (fun y => y = f z) ⟨f z, rfl⟩).symm
  · rw [if_neg h]

/-! The `connective_def` rule. -/

theorem ite_then_intro {α : Sort u} (c : Prop) [h : Decidable c] (t e : α) :
    ¬c ∨ ite c t e = t :=
  if hc : c then Or.inr (if_pos hc) else Or.inl hc

theorem ite_else_intro {α : Sort u} (c : Prop) [h : Decidable c] (t e : α) :
    c ∨ ite c t e = e :=
  if hc : c then Or.inl hc else Or.inr (if_neg hc)

theorem connective_def_xor (a b : Prop) : XOr a b = ((¬a ∧ b) ∨ (a ∧ ¬b)) :=
  propext ⟨fun h => h.elim (fun ha hb => .inr ⟨ha, hb⟩) (fun ha hb => .inl ⟨ha, hb⟩),
           fun h => h.elim (fun ⟨ha, hb⟩ => .inr ha hb) (fun ⟨ha, hb⟩ => .inl ha hb)⟩

theorem connective_def_eq (a b : Prop) : (a = b) = ((a → b) ∧ (b → a)) :=
  propext ⟨fun h => ⟨fun ha => h ▸ ha, fun hb => h ▸ hb⟩, fun ⟨h₁, h₂⟩ => propext ⟨h₁, h₂⟩⟩

theorem connective_def_ite (c a b : Prop) [h : Decidable c] : ite c a b = ((c → a) ∧ (¬c → b)) :=
  h.byCases
    (fun hc => by simp only [if_pos hc]; exact propext ⟨fun ha => ⟨fun _ => ha, fun hn => (hn hc).elim⟩, fun ⟨h₁, _⟩ => h₁ hc⟩)
    (fun hc => by simp only [if_neg hc]; exact propext ⟨fun hb => ⟨fun h => (hc h).elim, fun _ => hb⟩, fun ⟨_, h₂⟩ => h₂ hc⟩)

end Smt.Alethe
