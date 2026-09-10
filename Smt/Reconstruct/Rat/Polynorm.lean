/-
Copyright (c) 2021-2024 by the authors listed in the file AUTHORS and their
institutional affiliations. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Abdalrhman Mohamed, Harun Khan
-/

module

public import Lean.Meta.Native
public meta import Lean.Meta.Native
public import Smt.Reconstruct.Rat.Core
public meta import Smt.Reconstruct.Rat.Core
public import Smt.Recognizers
public meta import Smt.Recognizers
public import Lean
public meta import Lean
public import Qq
public meta import Qq

@[expose] public section

namespace Smt.Reconstruct.Rat.PolyNorm

structure Var where
  type : Bool
  val  : Nat
deriving DecidableEq, Repr

instance : LE Var where
  le v₁ v₂ := v₁.type < v₂.type ∨ (v₁.type = v₂.type ∧ v₁.val ≤ v₂.val)

instance : LT Var where
  lt v₁ v₂ := v₁.type < v₂.type ∨ (v₁.type = v₂.type ∧ v₁.val < v₂.val)

instance (v₁ v₂ : Var) : Decidable (v₁ ≤ v₂) :=
  if h : v₁.type < v₂.type ∨ (v₁.type = v₂.type ∧ v₁.val ≤ v₂.val) then isTrue h else isFalse h

instance (v₁ v₂ : Var) : Decidable (v₁ < v₂) :=
  if h : v₁.type < v₂.type ∨ (v₁.type = v₂.type ∧ v₁.val < v₂.val) then isTrue h else isFalse h

abbrev Context := Var → Rat

def IntContext := Nat → Int
def RatContext := Nat → Rat

structure Monomial where
  coeff : Rat
  vars : List Var
deriving Inhabited, Repr, DecidableEq

namespace Monomial

open Qq in
def toExpr (m : Monomial) (ppCtx : Var → Q(Rat)) : Q(Rat) :=
  if h : m.vars = [] then
    toExprCoeff m.coeff
  else
    if m.coeff = 1 then
      (m.vars.drop 1).foldl (fun acc v => q($acc * $(ppCtx v))) (ppCtx (m.vars.head h))
    else
      m.vars.foldl (fun acc v => q($acc * $(ppCtx v))) (toExprCoeff m.coeff)
where
  toExprCoeff (c : Rat) : Q(Rat) :=
  let num : Q(Rat) := mkRatLit c.num.natAbs
  if c.den == 1 then
    if c.num ≥ 0 then
      q($num)
    else
      q(-$num)
  else
    let den : Q(Rat) := mkRatLit c.den
    if c.num ≥ 0 then
      q($num / $den)
    else
      q(-$num / $den)
  mkRatLit (n : Nat) : Q(Rat) :=
    let l : Q(Nat) := Lean.mkRawNatLit n
    q(OfNat.ofNat $l)

def neg (m : Monomial) : Monomial :=
  { m with coeff := -m.coeff }

def add (m₁ m₂ : Monomial) (_ : m₁.vars = m₂.vars) : Monomial :=
  { coeff := m₁.coeff + m₂.coeff, vars := m₁.vars }

-- Invariant: monomial variables remain sorted.
def mul (m₁ m₂ : Monomial) : Monomial :=
  let coeff := m₁.coeff * m₂.coeff
  let vars := m₁.vars.foldr insert m₂.vars
  { coeff, vars }
where
  insert (x : Var) : List Var → List Var
    | [] => [x]
    | y :: ys => if x ≤ y then x :: y :: ys else y :: insert x ys

def divConst (m : Monomial) (c : Rat) : Monomial :=
  { m with coeff := m.coeff / c }

def denote (ctx : Context) (m : Monomial) : Rat :=
  m.coeff * m.vars.foldl (fun acc v => acc * ctx v) 1

theorem denote_neg {m : Monomial} : m.neg.denote ctx = -m.denote ctx := by
  simp only [neg, denote, Rat.neg_mul]

section

variable {op : α → α → α}

-- Can be generalized to `List.foldl_assoc`.
theorem foldl_assoc {g : β → α} (assoc : ∀ a b c, op (op a b) c = op a (op b c)) (z1 z2 : α):
  List.foldl (fun z a => op z (g a)) (op z1 z2) l =
  op z1 (List.foldl (fun z a => op z (g a)) z2 l) := by
  induction l generalizing z1 z2 with
  | nil => rfl
  | cons y ys ih =>
    simp only [List.foldl_cons, ih, assoc]

theorem foldr_assoc {g : β → α} (assoc : ∀ a b c, op (op a b) c = op a (op b c)) (z1 z2 : α):
  List.foldr (fun z a => op a (g z)) (op z1 z2) l =
  op z1 (List.foldr (fun z a => op a (g z)) z2 l) := by
  induction l generalizing z1 z2 with
  | nil => rfl
  | cons y ys ih =>
    simp only [List.foldr_cons, ih, assoc]

end
-- Can be generalized.
theorem foldl_mul_insert {ctx : Context} :
  List.foldl (fun z a => z * (ctx a)) 1 (mul.insert y ys) =
  (ctx y) * List.foldl (fun z a => z * (ctx a)) 1 ys := by
  induction ys with
  | nil => simp [mul.insert]
  | cons x ys ih =>
    by_cases h : y ≤ x
    · simp [mul.insert, h, foldl_assoc Rat.mul_assoc (ctx y) (ctx x)]
    · simp only [mul.insert, h, List.foldl_cons, ite_false, Rat.mul_comm,
                 foldl_assoc Rat.mul_assoc, ih]
      rw [← Rat.mul_assoc, Rat.mul_comm (ctx x) (ctx y), Rat.mul_assoc]

theorem denote_add {m n : Monomial} (h : m.vars = n.vars) :
  (m.add n h).denote ctx = m.denote ctx + n.denote ctx := by
  simp only [add, denote, Rat.add_mul, h]

theorem denote_mul {m₁ m₂ : Monomial} : (m₁.mul m₂).denote ctx = m₁.denote ctx * m₂.denote ctx := by
  simp only [denote, mul, Rat.mul_assoc]; congr 1
  rw [← Rat.mul_assoc, Rat.mul_comm _ m₂.coeff, Rat.mul_assoc]; congr 1
  induction m₁.vars with
  | nil => simp
  | cons y ys ih =>
    simp [foldl_mul_insert, ←foldl_assoc Rat.mul_assoc, ih]

theorem denote_divConst {m : Monomial} : (m.divConst c).denote ctx = m.denote ctx / c := by
  simp only [denote, divConst, Rat.mul_div_right_comm]

end Monomial

abbrev Polynomial := List Monomial

namespace Polynomial

open Qq in
def toExpr (p : Polynomial) (ppCtx : Var → Q(Rat)) : Q(Rat) :=
  go p
where
  go : Polynomial → Q(Rat)
    | [] => q(0)
    | [m] => m.toExpr ppCtx
    | m :: ms =>q($(m.toExpr ppCtx) + $(go ms))

def neg (p : Polynomial) : Polynomial :=
  p.map Monomial.neg

/-- Merge `m` into the sorted polynomial it is given, and hand what is left of that polynomial to
    `k`, which merges the monomials that come after `m`. -/
def addAux (m : Monomial) (k : Polynomial → Polynomial) : Polynomial → Polynomial
  | [] => m :: k []
  | n :: ns =>
    if m.vars < n.vars then
      m :: k (n :: ns)
    else if h : m.vars = n.vars then
      let m' := m.add n h
      if m'.coeff = 0 then k ns else m' :: k ns
    else
      n :: addAux m k ns

-- NOTE: implementation merges monomials with same variables.
-- Invariant: monomials remain sorted.
-- The two polynomials are merged in a single pass. Inserting the monomials of one into the other
-- one at a time, as this used to do, makes a sum of `n` terms cost `O(n³)` steps of the *kernel*,
-- which is what evaluates this.
def add : Polynomial → Polynomial → Polynomial
  | [] => fun q => q
  | m :: ms => addAux m (add ms)

def sub (p q : Polynomial) : Polynomial :=
  p.add q.neg

-- Invariant: monomials remain sorted.
def mulMonomial (m : Monomial) (p : Polynomial) : Polynomial :=
  p.foldr (fun n acc => Polynomial.add [m.mul n] acc) []

-- Invariant: monomials remain sorted.
def mul (p q : Polynomial) : Polynomial :=
  p.foldl (fun acc m => (q.mulMonomial m).add acc) []

def divConst (p : Polynomial) (c : Rat) : Polynomial :=
  p.map (·.divConst c)

def denote (ctx : Context) (p : Polynomial) : Rat :=
  p.foldl (fun acc m => acc + m.denote ctx) 0

theorem denote_nil : denote ctx ([] : Polynomial) = 0 := rfl

theorem denote_cons {p : List Monomial} {ctx : Context} : denote ctx (m :: p) = m.denote ctx + denote ctx p := by
  simp only [denote, List.foldl_cons, Rat.add_comm 0, Monomial.foldl_assoc Rat.add_assoc]

theorem denote_singleton {m : Monomial} : denote ctx [m] = m.denote ctx := by
  simp [denote_cons, denote_nil, Rat.add_zero]

theorem denote_neg {p : Polynomial} : p.neg.denote ctx = -p.denote ctx := by
  simp only [denote, neg]
  induction p with
  | nil => simp
  | cons m p ih =>
    simp only [List.foldl_cons, Rat.add_comm 0, Monomial.foldl_assoc Rat.add_assoc, Rat.neg_add, ←ih, List.map, Monomial.denote_neg]

theorem denote_addAux {ctx : Context} {m : Monomial} {ms : Polynomial}
    (ih : ∀ r, denote ctx (add ms r) = denote ctx ms + denote ctx r) (q : Polynomial) :
    denote ctx (addAux m (add ms) q) = m.denote ctx + denote ctx ms + denote ctx q := by
  induction q with
  | nil => simp only [addAux, denote_cons, denote_nil, ih, Rat.add_zero]
  | cons n ns ihq =>
    simp only [addAux]
    split
    · simp only [denote_cons, ih, Rat.add_assoc]
    · split
      · rename_i h
        have hmn := Monomial.denote_add (ctx := ctx) h
        split
        · rename_i hz
          have : Monomial.denote ctx (m.add n h) = 0 := by
            simp only [Monomial.denote, hz, Rat.zero_mul]
          rw [this] at hmn
          simp only [denote_cons, ih]
          rw [show m.denote ctx + denote ctx ms + (n.denote ctx + denote ctx ns)
                = (m.denote ctx + n.denote ctx) + (denote ctx ms + denote ctx ns) by
                simp only [Rat.add_assoc, Rat.add_left_comm],
              ← hmn, Rat.zero_add]
        · simp only [denote_cons, ih, hmn]
          simp only [Rat.add_assoc, Rat.add_left_comm]
      · simp only [denote_cons, ihq]
        simp only [Rat.add_assoc, Rat.add_left_comm]

theorem denote_add {p q : Polynomial} : (p.add q).denote ctx = p.denote ctx + q.denote ctx := by
  induction p generalizing q with
  | nil => simp [add, denote_nil, Rat.zero_add]
  | cons m ms ih =>
    rw [show add (m :: ms) q = addAux m (add ms) q from rfl, denote_addAux (fun r => ih), denote_cons]

theorem denote_sub {p q : Polynomial} : (p.sub q).denote ctx = p.denote ctx - q.denote ctx := by
  simp only [sub, denote_neg, denote_add, Rat.sub_eq_add_neg]

theorem denote_mulMonomial {p : Polynomial} : (p.mulMonomial m).denote ctx = m.denote ctx * p.denote ctx := by
  induction p with
  | nil => simp [mulMonomial, denote_nil]
  | cons n p ih =>
    simp only [mulMonomial, List.foldr_cons] at *
    rw [denote_add, ih, denote_singleton, Monomial.denote_mul, denote_cons, Rat.mul_add]

theorem denote_foldl_mul {q : Polynomial} : ∀ (p acc : Polynomial),
    denote ctx (p.foldl (fun acc m => (q.mulMonomial m).add acc) acc)
      = denote ctx acc + denote ctx p * denote ctx q := by
  intro p
  induction p with
  | nil => intro acc; simp [denote_nil, Rat.add_zero]
  | cons m ms ih =>
    intro acc
    simp only [List.foldl_cons, ih, denote_add, denote_mulMonomial, denote_cons, Rat.add_mul]
    simp only [Rat.add_assoc, Rat.add_left_comm]

theorem denote_mul {p q : Polynomial} : (p.mul q).denote ctx = p.denote ctx * q.denote ctx := by
  simp only [mul, denote_foldl_mul, denote_nil, Rat.zero_add]

theorem denote_divConst {p : Polynomial} : (p.divConst c).denote ctx = p.denote ctx / c := by
  simp only [denote, divConst]
  induction p with
  | nil => simp [Rat.zero_div]
  | cons x ys ih =>
    simp only [List.map_cons, List.foldl_cons, Rat.add_comm 0, Monomial.foldl_assoc Rat.add_assoc]
    rw [Monomial.denote_divConst, ih, Rat.add_div]

/-- The sum of a list of polynomials. -/
def denoteAll (ctx : Context) (ps : List Polynomial) : Rat :=
  ps.foldr (fun p acc => denote ctx p + acc) 0

theorem denoteAll_nil : denoteAll ctx [] = 0 := rfl

theorem denoteAll_cons {p : Polynomial} {ps : List Polynomial} :
    denoteAll ctx (p :: ps) = denote ctx p + denoteAll ctx ps := rfl

/-- One pass of a bottom-up merge sort: merge the sorted polynomials pairwise. -/
def mergePairs : List Polynomial → List Polynomial
  | p :: q :: ps => add p q :: mergePairs ps
  | ps => ps

/-- Merge sorted polynomials into one. `n` bounds the number of passes; `ps.length` is always
    enough, and the result denotes their sum whatever `n` is. -/
def mergeAll : Nat → List Polynomial → Polynomial
  | _, [] => []
  | _, [p] => p
  | 0, ps => ps.foldr add []
  | n + 1, ps => mergeAll n (mergePairs ps)

theorem denote_mergePairs {ps : List Polynomial} :
    denoteAll ctx (mergePairs ps) = denoteAll ctx ps := by
  induction ps using mergePairs.induct with
  | case1 p q ps ih =>
    simp only [mergePairs, denoteAll_cons, denote_add, ih, Rat.add_assoc]
  | case2 ps h =>
    cases ps with
    | nil => rfl
    | cons p ps =>
      cases ps with
      | nil => rfl
      | cons q ps => exact (h p q ps rfl).elim

theorem denote_foldr_add {ps : List Polynomial} :
    denote ctx (ps.foldr add []) = denoteAll ctx ps := by
  induction ps with
  | nil => rfl
  | cons p ps ih => simp only [List.foldr_cons, denote_add, ih, denoteAll_cons]

theorem denote_mergeAll {n : Nat} {ps : List Polynomial} :
    denote ctx (mergeAll n ps) = denoteAll ctx ps := by
  induction n generalizing ps with
  | zero =>
    match ps with
    | [] => rfl
    | [p] => simp [mergeAll, denoteAll_cons, denoteAll_nil, Rat.add_zero]
    | p :: q :: ps => simp only [mergeAll, denote_foldr_add]
  | succ n ih =>
    match ps with
    | [] => rfl
    | [p] => simp [mergeAll, denoteAll_cons, denoteAll_nil, Rat.add_zero]
    | p :: q :: ps => simp only [mergeAll, ih, denote_mergePairs]

/-- The singletons a flat list of monomials sorts from. -/
def singletons (l : Polynomial) : List Polynomial :=
  l.map fun m => if m.coeff = 0 then [] else [m]

theorem denoteAll_singletons {l : Polynomial} : denoteAll ctx (singletons l) = denote ctx l := by
  induction l with
  | nil => rfl
  | cons m l ih =>
    simp only [singletons, List.map_cons, denoteAll_cons, denote_cons] at *
    rw [ih]
    split
    · rename_i hz
      have : Monomial.denote ctx m = 0 := by simp only [Monomial.denote, hz, Rat.zero_mul]
      simp [denote_nil, this]
    · simp [denote_singleton]

/-- Sort and merge a flat list of monomials into a polynomial. -/
def normalize (l : Polynomial) : Polynomial :=
  mergeAll l.length (singletons l)

theorem denote_normalize {l : Polynomial} : denote ctx (normalize l) = denote ctx l := by
  simp only [normalize, denote_mergeAll, denoteAll_singletons]

end Polynomial

inductive IntExpr where
  | val (v : Int)
  | var (v : Nat)
  | neg (a : IntExpr)
  | add (a b : IntExpr)
  | sub (a b : IntExpr)
  | mul (a b : IntExpr)
deriving Inhabited, Repr

namespace IntExpr

def denote (ctx : IntContext) : IntExpr → Int
  | .val v => v
  | .var v => ctx v
  | .neg a => -a.denote ctx
  | .add a b => a.denote ctx + b.denote ctx
  | .sub a b => a.denote ctx - b.denote ctx
  | .mul a b => a.denote ctx * b.denote ctx

/-- Every product of a monomial of `p` with one of `q`, prepended to `acc`. -/
def appendMul (p q : Polynomial) (acc : Polynomial) : Polynomial :=
  p.foldr (fun m acc => q.foldr (fun n acc => m.mul n :: acc) acc) acc

/-- The monomials of `k` times an expression, in the order they occur and without merging,
    prepended to `acc`. Collecting them in one pass and sorting once is what keeps the normal form
    cheap for the kernel to compute: folding a sum of `n` terms through a sorted insertion, as
    this used to do, copies the partial polynomial `n` times. -/
def flatten (k : Rat) : IntExpr → Polynomial → Polynomial
  | .val v, acc =>
    let c := k * v
    if c = 0 then acc else { coeff := c, vars := [] } :: acc
  | .var v, acc => { coeff := k, vars := [⟨false, v⟩] } :: acc
  | .neg a, acc => flatten (-k) a acc
  | .add a b, acc => flatten k a (flatten k b acc)
  | .sub a b, acc => flatten k a (flatten (-k) b acc)
  | .mul a b, acc => appendMul (flatten k a []) (flatten 1 b []) acc

theorem denote_foldr_mulCons {m : Monomial} {q acc : Polynomial} :
    Polynomial.denote ctx (q.foldr (fun n acc => m.mul n :: acc) acc)
      = m.denote ctx * Polynomial.denote ctx q + Polynomial.denote ctx acc := by
  induction q with
  | nil => simp [Polynomial.denote_nil, Rat.zero_add]
  | cons n q ihq =>
    simp only [List.foldr_cons, Polynomial.denote_cons, ihq, Monomial.denote_mul, Rat.mul_add,
      Rat.add_assoc]

theorem appendMul_cons {m : Monomial} {p q acc : Polynomial} :
    appendMul (m :: p) q acc = q.foldr (fun n acc => m.mul n :: acc) (appendMul p q acc) := rfl

theorem denote_appendMul {p q acc : Polynomial} :
    Polynomial.denote ctx (appendMul p q acc)
      = Polynomial.denote ctx p * Polynomial.denote ctx q + Polynomial.denote ctx acc := by
  induction p generalizing acc with
  | nil => simp [appendMul, Polynomial.denote_nil, Rat.zero_add]
  | cons m p ih =>
    rw [appendMul_cons, denote_foldr_mulCons, ih, Polynomial.denote_cons, Rat.add_mul, Rat.add_assoc]

theorem denote_flatten {rctx : RatContext} (k : Rat) (e : IntExpr) (acc : Polynomial) :
    Polynomial.denote (fun ⟨b, n⟩ => if b then rctx n else ictx n) (e.flatten k acc)
      = k * (e.denote ictx : Rat)
        + Polynomial.denote (fun ⟨b, n⟩ => if b then rctx n else ictx n) acc := by
  induction e generalizing k acc with
  | val v =>
    simp only [flatten, denote]
    split
    · rename_i hz; simp [hz, Rat.zero_add]
    · simp [Polynomial.denote_cons, Monomial.denote]
  | var v =>
    simp [flatten, denote, Polynomial.denote_cons, Monomial.denote]
  | neg a ih =>
    simp only [flatten, denote, ih, Rat.intCast_neg, Rat.neg_mul, Rat.mul_neg]
  | add a b iha ihb =>
    simp only [flatten, denote, iha, ihb, Rat.intCast_add, Rat.mul_add, Rat.add_assoc]
  | sub a b iha ihb =>
    simp only [flatten, denote, iha, ihb, Rat.intCast_sub, Rat.sub_eq_add_neg, Rat.mul_add,
      Rat.neg_mul, Rat.mul_neg, Rat.add_assoc]
  | mul a b iha ihb =>
    simp only [flatten, denote, denote_appendMul, iha k [], ihb 1 [], Polynomial.denote_nil,
      Rat.add_zero, Rat.intCast_mul, Rat.one_mul, Rat.mul_assoc]

end IntExpr

inductive RatExpr where
  | val (v : Rat)
  | var (v : Nat)
  | neg (a : RatExpr)
  | add (a b : RatExpr)
  | sub (a b : RatExpr)
  | mul (a b : RatExpr)
  | divConst (a : RatExpr) (c : Rat)
  | cast (a : IntExpr)
deriving Inhabited, Repr

namespace RatExpr

def denote (ictx : IntContext) (rctx : RatContext)  : RatExpr → Rat
  | .val v => v
  | .var v => rctx v
  | .neg a => -a.denote ictx rctx
  | .add a b => a.denote ictx rctx + b.denote ictx rctx
  | .sub a b => a.denote ictx rctx - b.denote ictx rctx
  | .mul a b => a.denote ictx rctx * b.denote ictx rctx
  | .divConst a c => a.denote ictx rctx / c
  | .cast a => a.denote ictx

/-- The monomials of `k` times an expression, in the order they occur and without merging,
    prepended to `acc` (see `IntExpr.flatten`). A division by a constant divides `k`. -/
def flatten (k : Rat) : RatExpr → Polynomial → Polynomial
  | .val v, acc =>
    let c := k * v
    if c = 0 then acc else { coeff := c, vars := [] } :: acc
  | .var v, acc => { coeff := k, vars := [⟨true, v⟩] } :: acc
  | .neg a, acc => flatten (-k) a acc
  | .add a b, acc => flatten k a (flatten k b acc)
  | .sub a b, acc => flatten k a (flatten (-k) b acc)
  | .mul a b, acc => IntExpr.appendMul (flatten k a []) (flatten 1 b []) acc
  | .divConst a c, acc => flatten (k / c) a acc
  | .cast a, acc => a.flatten k acc

def toPolynomial (e : RatExpr) : Polynomial :=
  Polynomial.normalize (e.flatten 1 [])

theorem denote_flatten (k : Rat) (e : RatExpr) (acc : Polynomial) :
    Polynomial.denote (fun ⟨b, n⟩ => if b then rctx n else ictx n) (e.flatten k acc)
      = k * e.denote ictx rctx
        + Polynomial.denote (fun ⟨b, n⟩ => if b then rctx n else ictx n) acc := by
  induction e generalizing k acc with
  | val v =>
    simp only [flatten, denote]
    split
    · rename_i hz; simp [hz, Rat.zero_add]
    · simp [Polynomial.denote_cons, Monomial.denote]
  | var v =>
    simp [flatten, denote, Polynomial.denote_cons, Monomial.denote]
  | neg a ih =>
    simp only [flatten, denote, ih, Rat.neg_mul, Rat.mul_neg]
  | add a b iha ihb =>
    simp only [flatten, denote, iha, ihb, Rat.mul_add, Rat.add_assoc]
  | sub a b iha ihb =>
    simp only [flatten, denote, iha, ihb, Rat.sub_eq_add_neg, Rat.mul_add, Rat.neg_mul,
      Rat.mul_neg, Rat.add_assoc]
  | mul a b iha ihb =>
    simp only [flatten, denote, IntExpr.denote_appendMul, iha k [], ihb 1 [],
      Polynomial.denote_nil, Rat.add_zero, Rat.one_mul, Rat.mul_assoc]
  | divConst a c ih =>
    simp only [flatten, denote, ih, Rat.div_def, Rat.mul_assoc, Rat.mul_comm c⁻¹]
  | cast a =>
    simp only [flatten, denote, IntExpr.denote_flatten]

theorem denote_toPolynomial {e : RatExpr} : e.denote ictx rctx = e.toPolynomial.denote (fun ⟨b, n⟩ => if b then rctx n else ictx n) := by
  simp only [toPolynomial, Polynomial.denote_normalize, denote_flatten, Polynomial.denote_nil,
    Rat.add_zero, Rat.one_mul]

theorem denote_eq_from_toPolynomial_eq {e₁ e₂ : RatExpr} (h : e₁.toPolynomial = e₂.toPolynomial) : e₁.denote ictx rctx = e₂.denote ictx rctx := by
  rw [denote_toPolynomial, denote_toPolynomial, h]

end PolyNorm.RatExpr

public meta section

open Lean
open Qq

abbrev PolyM := StateT (Array Q(Int) × Array Q(Rat)) MetaM

def getIntIndex (e : Q(Int)) : PolyM Nat := do
  let ⟨is, rs⟩ ← get
  if let some i := is.findIdx? (· == e) then
    return i
  else
    let size := is.size
    set (is.push e, rs)
    return size

def getRatIndex (e : Q(Rat)) : PolyM Nat := do
  let ⟨is, rs⟩ ← get
  if let some i := rs.findIdx? (· == e) then
    return i
  else
    let size := rs.size
    set (is, rs.push e)
    return size

partial def reifyRatVal (e : Q(Rat)) : PolyM Rat := do
  if let some n := e.natLitOf? q(Rat) then
    return n
  else if let some e := e.negOf? q(Rat) then
    return -(← reifyRatVal e)
  else if let some (x, y) := e.hAddOf? q(Rat) q(Rat) then
    return (← reifyRatVal x) + (← reifyRatVal y)
  else if let some (x, y) := e.hSubOf? q(Rat) q(Rat) then
    return (← reifyRatVal x) - (← reifyRatVal y)
  else if let some (x, y) := e.hMulOf? q(Rat) q(Rat) then
    return (← reifyRatVal x) * (← reifyRatVal y)
  else if let some (x, y) := e.hDivOf? q(Rat) q(Rat) then
    return (← reifyRatVal x) / (← reifyRatVal y)
  else
    throwError "[poly_norm] expected a rational number, got {e}"

partial def reifyInt (e : Q(Int)) : PolyM Q(PolyNorm.IntExpr) := do
  if let some n := e.natLitOf? q(Int) then
    return q(.val (OfNat.ofNat $n))
  else if let some e := e.negOf? q(Int) then
    return q(.neg $(← reifyInt e))
  else if let some (x, y) := e.hAddOf? q(Int) q(Int) then
    return q(.add $(← reifyInt x) $(← reifyInt y))
  else if let some (x, y) := e.hSubOf? q(Int) q(Int) then
    return q(.sub $(← reifyInt x) $(← reifyInt y))
  else if let some (x, y) := e.hMulOf? q(Int) q(Int) then
    return q(.mul $(← reifyInt x) $(← reifyInt y))
  else
    let v : Nat ← getIntIndex e
    return q(.var $v)

-- `reifyRat` calls this module's own non-`meta` `PolyNorm.Monomial.toExpr.toExprCoeff`, which the
-- phase-distinction check only allows within a single module under this option.
set_option compiler.relaxedMetaCheck true in
partial def reifyRat (e : Q(Rat)) : PolyM Q(PolyNorm.RatExpr) := do
  if let some n := e.natLitOf? q(Rat) then
    return q(.val (OfNat.ofNat $n))
  else if let some e := e.negOf? q(Rat) then
    return q(.neg $(← reifyRat e))
  else if let some (x, y) := e.hAddOf? q(Rat) q(Rat) then
    return q(.add $(← reifyRat x) $(← reifyRat y))
  else if let some (x, y) := e.hSubOf? q(Rat) q(Rat) then
    return q(.sub $(← reifyRat x) $(← reifyRat y))
  else if let some (x, y) := e.hMulOf? q(Rat) q(Rat) then
    return q(.mul $(← reifyRat x) $(← reifyRat y))
  else if let some (x, y) := e.hDivOf? q(Rat) q(Rat) then
    return q(.divConst $(← reifyRat x) $(PolyNorm.Monomial.toExpr.toExprCoeff (← reifyRatVal y)))
  else if let some e := e.intCastOf? q(Rat) then
    return q(.cast $(← reifyInt e))
  else
    let v : Nat ← getRatIndex e
    return q(.var $v)

def polyNorm (mv : MVarId) : MetaM Unit := do
  let some (_, l, r) := (← mv.getType).eq?
    | throwError "[poly_norm] expected an equality, got {← mv.getType}"
  let (l, (is, rs)) ← (reifyRat l).run (#[], #[])
  let (r, (is, rs)) ← (reifyRat r).run (is, rs)
  let ictx : Q(PolyNorm.IntContext) ← if h : 0 < is.size
    then do let is : Q(RArray Int) ← (RArray.ofArray is h).toExpr q(Int) id; pure q(«$is».get)
    else pure q(fun _ => 0)
  let rctx : Q(PolyNorm.RatContext) ← if h : 0 < rs.size
    then do let rs : Q(RArray Rat) ← (RArray.ofArray rs h).toExpr q(Rat) id; pure q(«$rs».get)
    else pure q(fun _ => 0)
  let h : Q(«$l».toPolynomial = «$r».toPolynomial) := .app q(@Eq.refl.{1} PolyNorm.Polynomial) q(«$l».toPolynomial)
  mv.assign q(@PolyNorm.RatExpr.denote_eq_from_toPolynomial_eq $ictx $rctx $l $r $h)

def nativePolyNorm (mv : MVarId) : MetaM Unit := do
  let some (_, l, r) := (← mv.getType).eq?
    | throwError "[poly_norm] expected an equality, got {← mv.getType}"
  let (l, (is, rs)) ← (reifyRat l).run (#[], #[])
  let (r, (is, rs)) ← (reifyRat r).run (is, rs)
  let ictx : Q(PolyNorm.IntContext) ← if h : 0 < is.size
    then do let is : Q(RArray Int) ← (RArray.ofArray is h).toExpr q(Int) id; pure q(«$is».get)
    else pure q(fun _ => 0)
  let rctx : Q(PolyNorm.RatContext) ← if h : 0 < rs.size
    then do let rs : Q(RArray Rat) ← (RArray.ofArray rs h).toExpr q(Rat) id; pure q(«$rs».get)
    else pure q(fun _ => 0)
  let h ← nativeDecide q(«$l».toPolynomial = «$r».toPolynomial)
  mv.assign q(@PolyNorm.RatExpr.denote_eq_from_toPolynomial_eq $ictx $rctx $l $r $h)
where
  nativeDecide (p : Q(Prop)) : MetaM Q($p) := do
    let hp : Q(Decidable $p) ← Meta.synthInstance q(Decidable $p)
    match ← Meta.nativeEqTrue `Smt.polynorm q(decide $p) with
    | .notTrue =>
      throwError m!"[poly_norm] evaluated that the proposition
        {indentExpr q(decide $p)}\n\
        is false"
    | .success hdp =>
      -- get instance from `d`
      return .app q(@of_decide_eq_true $p $hp) hdp

namespace Tactic

syntax (name := polyNorm) "poly_norm" : tactic

open Lean.Elab Tactic in
@[tactic polyNorm] def evalPolyNorm : Tactic := fun _ =>
  withMainContext do
    let mv ← Tactic.getMainGoal
    Rat.polyNorm mv
    replaceMainGoal []

syntax (name := nativePolyNorm) "native_poly_norm" : tactic

open Lean.Elab Tactic in
@[tactic nativePolyNorm] def evalNativePolyNorm : Tactic := fun _ =>
  withMainContext do
    let mv ← Tactic.getMainGoal
    Rat.nativePolyNorm mv
    replaceMainGoal []

end Tactic

end

end Smt.Reconstruct.Rat

example (x y z : Rat) : 1 * (x + y) * z / 4 = 1 / (2 * 2) * (z * y + x * z) := by
  poly_norm

example (x y : Int) (z : Rat) : 1 * (↑x + ↑y) * z / 4 = 1 / (2 * 2) * (z * ↑y + ↑x * z) := by
  poly_norm

example (x y : Int) (z : Rat) : 1 * ↑(x + y) * z / 4 = 1 / (2 * 2) * (z * ↑y + ↑x * z) := by
  native_poly_norm
