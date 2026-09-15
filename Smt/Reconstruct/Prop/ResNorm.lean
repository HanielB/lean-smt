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
public import Smt.Reconstruct.Prop.AciNorm
public meta import Smt.Reconstruct.Prop.AciNorm

/-!
# A reflective checker for clausal steps

A verified checker for the clausal rules of Alethe — `resolution` and its variants, and the
containment rules `contraction`, `reordering`, `or` and `weakening` — in the style of `AciNorm`:
the clauses are reified, the whole chain is evaluated by the kernel in one pass, and a single
soundness theorem, applied as a term, turns the evaluation into a proof of the stated clause.

A literal is a `Nat`: `2 * i` for the `i`-th atom of a context, `2 * i + 1` for its negation. A
clause has two views: a `List Nat`, whose denotation unfolds *definitionally* to the clause's
proposition — `l₁ ∨ (l₂ ∨ … lₙ)`, `False` when empty, exactly the shape the Alethe checker builds
for a clause — and a `Nat` bitset, on which resolution and containment are single operations the
kernel evaluates with its accelerated `Nat.shiftLeft`/`lor`/`land`/`xor` on literals. A chain is
folded on the bitset view, one link per premise, and the one thing checked is the final
containment of the fold's result in the stated clause. The pivots are hints: resolving on a pivot
that does not occur removes nothing, so the fold is sound for any pivot sequence, and a wrong hint
surfaces once, as a failed containment, never as a side condition.

The encoding collapses negation to one bit, so a literal under two or more negations cannot be
expressed: the reifier declines such steps and the caller falls back.
-/

@[expose] public section

namespace Smt.Reconstruct.Prop.ResNorm

abbrev Context := Nat → Prop

/-- The proposition of a literal: atom `l / 2`, negated when `l` is odd. Matching on the `Bool`
keeps the unfolding free of `Decidable` instances. -/
def denoteLit (ctx : Context) (l : Nat) : Prop :=
  match Nat.beq (l % 2) 0 with
  | true => ctx (l / 2)
  | false => ¬ ctx (l / 2)

/-- The proposition of a clause, in the shape the checker states clauses: `False` when empty, the
last literal bare, right-nested `∨` otherwise. -/
def denoteCl (ctx : Context) : List Nat → Prop
  | [] => False
  | [l] => denoteLit ctx l
  | l :: ls => denoteLit ctx l ∨ denoteCl ctx ls

/-- `q` under the clauses `cs`, curried: `denoteCl c₁ → … → denoteCl cₙ → q`. -/
def denoteImp (ctx : Context) : List (List Nat) → Prop → Prop
  | [], q => q
  | c :: cs, q => denoteCl ctx c → denoteImp ctx cs q

/-- The complement of a literal. Spelled with arithmetic rather than `^^^ 1` so that `omega` can
see through it. -/
def negLit (l : Nat) : Nat :=
  match Nat.beq (l % 2) 0 with
  | true => l + 1
  | false => l - 1

/-- A clause as a bitset. -/
def mask : List Nat → Nat
  | [] => 0
  | l :: ls => (1 <<< l) ||| mask ls

/-- The bitset `m` without bit `l`. -/
def clearLit (m l : Nat) : Nat := m ^^^ (m &&& (1 <<< l))

/-- The bitset of a clause with every occurrence of `p` removed, in one pass. -/
def maskExcept (p : Nat) : List Nat → Nat
  | [] => 0
  | l :: ls =>
    match Nat.beq l p with
    | true => maskExcept p ls
    | false => (1 <<< l) ||| maskExcept p ls

/-- One link of the chain: the running clause resolved with `c` on `p`, which occurs in the
running clause and negated in `c`. Every occurrence of the pivot leaves the running clause and
every occurrence of its negation leaves `c`, which under the set view is Alethe's rule. -/
def step (acc : Nat) (c : List Nat) (p : Nat) : Nat :=
  clearLit acc p ||| maskExcept (negLit p) c

/-- The chain folded over the premises, one pivot per premise; premises without a pivot are left
unused. Structural recursion, so that the kernel unfolds it. -/
def chainMask : List (List Nat) → List Nat → Nat → Nat
  | c :: cs, p :: ps, acc => chainMask cs ps (step acc c p)
  | _, _, acc => acc

/-- Whether the chain from `c₀` through `cs` on the pivots `ps` concludes a subset of the clause
with bitset `m`. -/
def check (c₀ : List Nat) (cs : List (List Nat)) (ps : List Nat) (m : Nat) : Bool :=
  Nat.beq (chainMask cs ps (mask c₀) ||| m) m

/-- Some literal of the bitset holds. -/
def denoteMask (ctx : Context) (m : Nat) : Prop := ∃ l, m.testBit l = true ∧ denoteLit ctx l

/-! ### Soundness -/

theorem testBit_one_shiftLeft {i j : Nat} : (1 <<< j).testBit i = true ↔ i = j := by
  rw [Nat.one_shiftLeft, Nat.testBit_two_pow, decide_eq_true_iff]
  exact ⟨Eq.symm, Eq.symm⟩

theorem denoteCl_cons_elim {ctx : Context} {l : Nat} {ls : List Nat} :
    denoteCl ctx (l :: ls) → denoteLit ctx l ∨ denoteCl ctx ls := by
  cases ls with
  | nil => intro h; exact .inl h
  | cons l' ls => intro h; exact h

theorem denoteCl_of_lit {ctx : Context} {l : Nat} {ls : List Nat} (h : denoteLit ctx l) :
    denoteCl ctx (l :: ls) := by
  cases ls with
  | nil => exact h
  | cons l' ls => exact .inl h

theorem denoteCl_of_rest {ctx : Context} {l : Nat} {ls : List Nat} (h : denoteCl ctx ls) :
    denoteCl ctx (l :: ls) := by
  cases ls with
  | nil => exact False.elim h
  | cons l' ls => exact .inr h

theorem denoteCl_exists_mem {ctx : Context} : ∀ {c : List Nat},
    denoteCl ctx c → ∃ l, l ∈ c ∧ denoteLit ctx l
  | [], h => False.elim h
  | l :: ls, h => by
    rcases denoteCl_cons_elim h with hl | hls
    · exact ⟨l, List.mem_cons_self .., hl⟩
    · obtain ⟨l', hmem, hl'⟩ := denoteCl_exists_mem hls
      exact ⟨l', List.mem_cons_of_mem _ hmem, hl'⟩

theorem denoteCl_mask {ctx : Context} : ∀ {c : List Nat},
    denoteCl ctx c → denoteMask ctx (mask c)
  | [], h => False.elim h
  | l :: ls, h => by
    rcases denoteCl_cons_elim h with hl | hls
    · refine ⟨l, ?_, hl⟩
      rw [mask, Nat.testBit_or, testBit_one_shiftLeft.mpr rfl, Bool.true_or]
    · obtain ⟨l', hb, hl'⟩ := denoteCl_mask hls
      refine ⟨l', ?_, hl'⟩
      rw [mask, Nat.testBit_or, hb, Bool.or_true]

theorem denoteMask_cl {ctx : Context} : ∀ {t : List Nat},
    denoteMask ctx (mask t) → denoteCl ctx t
  | [], ⟨_, hb, _⟩ => by
    rw [mask, Nat.zero_testBit] at hb
    exact absurd hb Bool.false_ne_true
  | l :: ls, ⟨l', hb, hl'⟩ => by
    rw [mask, Nat.testBit_or, Bool.or_eq_true] at hb
    rcases hb with hb | hb
    · rw [testBit_one_shiftLeft.mp hb] at hl'
      exact denoteCl_of_lit hl'
    · exact denoteCl_of_rest (denoteMask_cl ⟨l', hb, hl'⟩)

theorem denoteMask_mono {ctx : Context} {m m' : Nat} (h : (m ||| m') = m') :
    denoteMask ctx m → denoteMask ctx m'
  | ⟨l, hb, hl⟩ => ⟨l, by rw [← h, Nat.testBit_or, hb, Bool.true_or], hl⟩

theorem testBit_clearLit_of_ne {m l p : Nat} (h : l ≠ p) :
    (clearLit m p).testBit l = m.testBit l := by
  unfold clearLit
  rw [Nat.testBit_xor, Nat.testBit_and]
  have hp : (1 <<< p).testBit l = false := by
    cases hb : (1 <<< p).testBit l
    · rfl
    · exact absurd (testBit_one_shiftLeft.mp hb) h
  rw [hp, Bool.and_false, Bool.xor_false]

theorem testBit_maskExcept : ∀ {c : List Nat} {l p : Nat}, l ≠ p → l ∈ c →
    (maskExcept p c).testBit l = true
  | [], _, _, _, h => nomatch h
  | l' :: ls, l, p, hne, hmem => by
    cases hb : Nat.beq l' p with
    | true =>
      simp only [maskExcept, hb]
      have hlp : l' = p := Nat.eq_of_beq_eq_true hb
      rcases List.mem_cons.mp hmem with heq | hmem'
      · exact absurd (heq.trans hlp) hne
      · exact testBit_maskExcept hne hmem'
    | false =>
      simp only [maskExcept, hb]
      rw [Nat.testBit_or]
      rcases List.mem_cons.mp hmem with heq | hmem'
      · rw [heq, testBit_one_shiftLeft.mpr rfl, Bool.true_or]
      · rw [testBit_maskExcept hne hmem', Bool.or_true]

theorem beq_one_zero : Nat.beq 1 0 = false := rfl
theorem beq_zero_zero : Nat.beq 0 0 = true := rfl

/-- A literal and its complement cannot both hold. Two arithmetic facts, `negLit l / 2 = l / 2` and
the parity flip, both by `omega`. -/
theorem denoteLit_negLit {ctx : Context} {l : Nat} :
    denoteLit ctx (negLit l) → denoteLit ctx l → False := by
  unfold negLit
  cases hb : Nat.beq (l % 2) 0 with
  | true =>
    have h0 : l % 2 = 0 := Nat.eq_of_beq_eq_true hb
    have h1 : (l + 1) % 2 = 1 := by omega
    have h2 : (l + 1) / 2 = l / 2 := by omega
    simp only [denoteLit, hb, h1, h2, beq_one_zero]
    exact fun hn hp => hn hp
  | false =>
    have h0 : l % 2 = 1 := by
      have := Nat.ne_of_beq_eq_false hb
      omega
    have h1 : (l - 1) % 2 = 0 := by omega
    have h2 : (l - 1) / 2 = l / 2 := by omega
    simp only [denoteLit, hb, h1, h2, beq_zero_zero]
    exact fun hp hn => hn hp

/-- One link is sound for any pivot: a literal of the running clause other than the pivot
survives, and if the pivot itself held then the premise supplies a literal — which is either kept
or is the pivot's complement, contradicting it. -/
theorem step_sound {ctx : Context} {acc : Nat} {c : List Nat} {p : Nat}
    (hacc : denoteMask ctx acc) (hc : denoteCl ctx c) : denoteMask ctx (step acc c p) := by
  obtain ⟨l, hb, hl⟩ := hacc
  cases hlp : Nat.beq l p with
  | false =>
    have hne : l ≠ p := Nat.ne_of_beq_eq_false hlp
    refine ⟨l, ?_, hl⟩
    unfold step
    rw [Nat.testBit_or, testBit_clearLit_of_ne hne, hb, Bool.true_or]
  | true =>
    have heq : l = p := Nat.eq_of_beq_eq_true hlp
    subst heq
    obtain ⟨l', hmem, hl'⟩ := denoteCl_exists_mem hc
    cases hln : Nat.beq l' (negLit l) with
    | false =>
      have hne : l' ≠ negLit l := Nat.ne_of_beq_eq_false hln
      refine ⟨l', ?_, hl'⟩
      unfold step
      rw [Nat.testBit_or, testBit_maskExcept hne hmem, Bool.or_true]
    | true =>
      have heq : l' = negLit l := Nat.eq_of_beq_eq_true hln
      subst heq
      exact (denoteLit_negLit hl' hl).elim

theorem denoteImp_of {ctx : Context} {q : Prop} : ∀ (cs : List (List Nat)), q → denoteImp ctx cs q
  | [], h => h
  | _ :: cs, h => fun _ => denoteImp_of cs h

theorem denoteImp_mono {ctx : Context} {q q' : Prop} (f : q → q') :
    ∀ (cs : List (List Nat)), denoteImp ctx cs q → denoteImp ctx cs q'
  | [], h => f h
  | _ :: cs, h => fun hc => denoteImp_mono f cs (h hc)

theorem chainMask_sound {ctx : Context} : ∀ (cs : List (List Nat)) (ps : List Nat) {acc : Nat},
    denoteMask ctx acc → denoteImp ctx cs (denoteMask ctx (chainMask cs ps acc))
  | [], _, _, h => h
  | _ :: cs, [], _, h => fun _ => denoteImp_of cs h
  | _ :: cs, _ :: ps, _, h => fun hc => chainMask_sound cs ps (step_sound h hc)

/-- The soundness theorem the proof terms apply: when the chain from `c₀` through `cs` on the
pivots `ps` ends inside the stated clause `tgt` (both `Bool` conditions evaluated by the kernel),
the stated clause follows from the premises. -/
theorem check_sound (ctx : Context) (c₀ : List Nat) (cs : List (List Nat)) (ps : List Nat)
    (tgt : List Nat) (m : Nat) (hm : Nat.beq (mask tgt) m = true)
    (hc : check c₀ cs ps m = true) :
    denoteCl ctx c₀ → denoteImp ctx cs (denoteCl ctx tgt) := fun h₀ =>
  have hm' : mask tgt = m := Nat.eq_of_beq_eq_true hm
  have hc' : (chainMask cs ps (mask c₀) ||| m) = m := Nat.eq_of_beq_eq_true hc
  denoteImp_mono (fun h => denoteMask_cl (hm' ▸ denoteMask_mono hc' h)) cs
    (chainMask_sound cs ps (denoteCl_mask h₀))

end Smt.Reconstruct.Prop.ResNorm

end

public meta section

namespace Smt.Reconstruct.Prop.ResNorm

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

/-- The literal of a proposition: `2 * i` for the atom `i`, `2 * i + 1` for `¬` of it. `none` for a
proposition under two negations, which the encoding cannot express. -/
def reifyLit (e : Expr) : ReifyM (Option Nat) := do
  match_expr e with
  | Not a =>
    match_expr a with
    | Not _ => return none
    | _ => return some (2 * (← getAtom a) + 1)
  | _ => return some (2 * (← getAtom e))

/-- The clause of a proposition: the literals down the right spine of its `∨`s, as the checker
states a clause, with `False` alone the empty clause. `none` if some literal has a stacked
negation. -/
partial def reifyClause (e : Expr) : ReifyM (Option (List Nat)) := do
  if e.isConstOf ``False then
    return some []
  go e
where
  go (e : Expr) : ReifyM (Option (List Nat)) := do
    match_expr e with
    | Or a b =>
      let some l ← reifyLit a | return none
      let some ls ← go b | return none
      return some (l :: ls)
    | _ => return (← reifyLit e).map ([·])

-- Raw literals throughout, so that the kernel computes on them directly.
def natListExpr (ls : List Nat) : Expr :=
  ls.foldr (fun l acc => mkApp3 (mkConst ``List.cons [.zero]) (mkConst ``Nat) (mkRawNatLit l) acc)
    (mkApp (mkConst ``List.nil [.zero]) (mkConst ``Nat))

def natListListExpr (cs : List (List Nat)) : Expr :=
  let ty := mkApp (mkConst ``List [.zero]) (mkConst ``Nat)
  cs.foldr (fun c acc => mkApp3 (mkConst ``List.cons [.zero]) ty (natListExpr c) acc)
    (mkApp (mkConst ``List.nil [.zero]) ty)

/-- A pivot hint for one link: the pivot's proposition, and whether it occurs positively in the
running clause (and negated in the premise) or the other way around. -/
structure Hint where
  pivot : Expr
  pol : Bool

-- `mask`, `step`, `check` and `negLit` are this module's own non-`meta` functions, which the phase
-- distinction check only allows within a single module under this option.
set_option compiler.relaxedMetaCheck true in
/-- Prove `target` from the `premises`, given as `(proof, proposition)` pairs, by the reflective
chain: the first premise is the running clause, each further premise is resolved into it on a
pivot — the hint for that link when it applies, a search otherwise, and none (the premise is
merged) when there is none — and the result must be contained in `target`. Returns `none`, so that
the caller can fall back, when a literal carries a stacked negation or the chain does not reach
`target`. -/
def proveClause (premises : Array (Expr × Expr)) (hints : Array (Option Hint)) (target : Expr) :
    MetaM (Option Expr) := do
  if premises.isEmpty then
    return none
  let (r, s) ← (do
      let mut cls : Array (List Nat) := #[]
      for (_, p) in premises do
        let some c ← reifyClause p | return none
        cls := cls.push c
      let some tgt ← reifyClause target | return none
      let mut hs : Array (Option Nat) := #[]
      for h? in hints do
        match h? with
        | none => hs := hs.push none
        | some h =>
          match ← reifyLit h.pivot with
          | some l => hs := hs.push (some (if h.pol then l else negLit l))
          | none => hs := hs.push none
      return some (cls, tgt, hs)).run {}
  let some (cls, tgt, hs) := r | return none
  -- the chain, link by link on the bitset, mirroring `chainMask`
  let fresh := 2 * s.atoms.size
  let mut acc := mask cls[0]!
  let mut ps : Array Nat := #[]
  for i in [1:cls.size] do
    let c := cls[i]!
    let hinted := match hs[i - 1]? with
      | some (some p) => if acc.testBit p && c.contains (negLit p) then some p else none
      | _ => none
    let p := match hinted with
      | some p => p
      | none =>
        match c.find? (fun l => acc.testBit (negLit l)) with
        | some l => negLit l
        | none => fresh
    ps := ps.push p
    acc := step acc c p
  let m := mask tgt
  unless check cls[0]! (cls.toList.drop 1) ps.toList m do
    return none
  let ctx ← AciNorm.mkContext s.atoms
  let reflTrue := mkApp2 (mkConst ``Eq.refl [.succ .zero]) (mkConst ``Bool) (mkConst ``Bool.true)
  let h := mkAppN (mkConst ``check_sound)
    #[ctx, natListExpr cls[0]!, natListListExpr (cls.toList.drop 1), natListExpr ps.toList,
      natListExpr tgt, mkRawNatLit m, reflTrue, reflTrue]
  return some (mkAppN h (premises.map (·.1)))

end Smt.Reconstruct.Prop.ResNorm

end
