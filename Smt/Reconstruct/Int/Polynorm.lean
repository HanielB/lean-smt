/-
Copyright (c) 2021-2024 by the authors listed in the file AUTHORS and their
institutional affiliations. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Abdalrhman Mohamed, Harun Khan
-/

module

public import Lean.Meta.Native
public meta import Lean.Meta.Native
public import Lean
public meta import Lean
public import Qq
public meta import Qq

public import Smt.Recognizers
public meta import Smt.Recognizers

@[expose] public section

private theorem Int.neg_congr {x y : Int} (h : x = y) : -x = -y := by
  simp [h]

private theorem Int.add_congr {x₁ x₂ y₁ y₂ : Int} (h₁ : x₁ = x₂) (h₂ : y₁ = y₂) : x₁ + y₁ = x₂ + y₂ := by
  simp [h₁, h₂]

private theorem Int.sub_congr {x₁ x₂ y₁ y₂ : Int} (h₁ : x₁ = x₂) (h₂ : y₁ = y₂) : x₁ - y₁ = x₂ - y₂ := by
  simp [h₁, h₂]

private theorem Int.mul_congr {x₁ x₂ y₁ y₂ : Int} (h₁ : x₁ = x₂) (h₂ : y₁ = y₂) : x₁ * y₁ = x₂ * y₂ := by
  simp [h₁, h₂]

private theorem Eq.trans₂' (hba : b = a) (hbc : b = c) (hcd : c = d) : a = d := hba ▸ hbc ▸ hcd ▸ rfl

namespace Smt.Reconstruct.Int.PolyNorm

abbrev Var := Nat

abbrev Context := Var → Int

structure Monomial where
  coeff : Int
  vars : List Var
deriving Inhabited, Repr, DecidableEq

namespace Monomial

open Qq in
def toExpr (m : Monomial) (ppCtx : Var → Q(Int)) : Q(Int) :=
  if h : m.vars = [] then
    toExprCoeff m.coeff
  else
    if m.coeff = 1 then
      (m.vars.drop 1).foldl (fun acc v => q($acc * $(ppCtx v))) (ppCtx (m.vars.head h))
    else
      m.vars.foldl (fun acc v => q($acc * $(ppCtx v))) (toExprCoeff m.coeff)
where
  toExprCoeff (c : Int) : Q(Int) :=
    let l : Q(Nat) := Lean.mkRawNatLit c.natAbs
    if c ≥ 0 then
      q(OfNat.ofNat $l : Int)
    else
      q(-OfNat.ofNat $l : Int)

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

def denote (ctx : Context) (m : Monomial) : Int :=
  m.coeff * m.vars.foldl (fun acc v => acc * ctx v) 1

theorem denote_neg {m : Monomial} : m.neg.denote ctx = -m.denote ctx := by
  simp only [neg, denote, Int.neg_mul_eq_neg_mul]

section

variable {op : α → α → α}

-- Can be generalized to `List.foldl_assoc`.
theorem foldl_assoc {g : β → α} (assoc : ∀ a b c, op (op a b) c = op a (op b c))
  (z1 z2 : α) :
  List.foldl (fun z a => op z (g a)) (op z1 z2) l =
  op z1 (List.foldl (fun z a => op z (g a)) z2 l) := by
  induction l generalizing z1 z2 with
  | nil => rfl
  | cons y ys ih =>
    simp only [List.foldl_cons, ih, assoc]

theorem foldr_assoc {g : β → α} (assoc : ∀ a b c, op (op a b) c = op a (op b c))
  (z1 z2 : α) :
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
    · simp [mul.insert, h, foldl_assoc Int.mul_assoc (ctx y) (ctx x)]
    · simp only [mul.insert, h, List.foldl_cons, ite_false, Int.mul_comm,
                 foldl_assoc Int.mul_assoc, ih]
      rw [←Int.mul_assoc, Int.mul_comm (ctx x) (ctx y), Int.mul_assoc]

theorem denote_add {m n : Monomial} (h : m.vars = n.vars) :
  (m.add n h).denote ctx = m.denote ctx + n.denote ctx := by
  simp only [add, denote, Int.add_mul, h]

theorem denote_mul {m₁ m₂ : Monomial} : (m₁.mul m₂).denote ctx = m₁.denote ctx * m₂.denote ctx := by
  simp only [denote, mul, Int.mul_assoc]; congr 1
  rw [← Int.mul_assoc, Int.mul_comm _ m₂.coeff, Int.mul_assoc]; congr 1
  induction m₁.vars with
  | nil => simp
  | cons y ys ih =>
    simp [foldl_mul_insert, ←foldl_assoc Int.mul_assoc, ih]

end Monomial

abbrev Polynomial := List Monomial

namespace Polynomial

open Qq in
def toExpr (p : Polynomial) (ppCtx : Var → Q(Int)) : Q(Int) :=
  go p
where
  go : Polynomial → Q(Int)
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

def denote (ctx : Context) (p : Polynomial) : Int :=
  p.foldl (fun acc m => acc + m.denote ctx) 0

theorem denote_nil : denote ctx ([] : Polynomial) = 0 := rfl

theorem denote_cons {p : List Monomial} {ctx : Context} : denote ctx (m :: p) = m.denote ctx + denote ctx p := by
  simp only [denote, List.foldl_cons, Int.add_comm 0, Monomial.foldl_assoc Int.add_assoc]

theorem denote_neg {p : Polynomial} : p.neg.denote ctx = -p.denote ctx := by
  simp only [denote, neg]
  induction p with
  | nil => simp
  | cons m p ih =>
    simp only [List.foldl_cons, Int.add_comm 0, Monomial.foldl_assoc Int.add_assoc,Int.neg_add, ←ih, List.map, Monomial.denote_neg]

theorem denote_addAux {ctx : Context} {m : Monomial} {ms : Polynomial}
    (ih : ∀ r, denote ctx (add ms r) = denote ctx ms + denote ctx r) (q : Polynomial) :
    denote ctx (addAux m (add ms) q) = m.denote ctx + denote ctx ms + denote ctx q := by
  induction q with
  | nil => simp only [addAux, denote_cons, denote_nil, ih]; omega
  | cons n ns ihq =>
    simp only [addAux]
    split
    · simp only [denote_cons, ih]; omega
    · split
      · rename_i h
        have hmn := Monomial.denote_add (ctx := ctx) h
        split
        · rename_i hz
          have : Monomial.denote ctx (m.add n h) = 0 := by
            simp only [Monomial.denote, hz, Int.zero_mul]
          rw [this] at hmn
          simp only [denote_cons, ih]
          omega
        · simp only [denote_cons, ih, hmn]
          omega
      · simp only [denote_cons, ihq]
        omega

theorem denote_add {p q : Polynomial} : (p.add q).denote ctx = p.denote ctx + q.denote ctx := by
  induction p generalizing q with
  | nil => simp [add, denote_nil]
  | cons m ms ih =>
    rw [show add (m :: ms) q = addAux m (add ms) q from rfl, denote_addAux (fun r => ih), denote_cons]
    try omega

theorem denote_sub {p q : Polynomial} : (p.sub q).denote ctx = p.denote ctx - q.denote ctx := by
  simp only [sub, denote_neg, denote_add, Int.sub_eq_add_neg]

theorem denote_singleton {m : Monomial} : denote ctx [m] = m.denote ctx := by
  simp [denote_cons, denote_nil]

theorem denote_mulMonomial {p : Polynomial} : (p.mulMonomial m).denote ctx = m.denote ctx * p.denote ctx := by
  induction p with
  | nil => simp [mulMonomial, denote_nil]
  | cons n p ih =>
    simp only [mulMonomial, List.foldr_cons] at *
    rw [denote_add, ih, denote_singleton, Monomial.denote_mul, denote_cons, Int.mul_add]

theorem denote_foldl_mul {q : Polynomial} : ∀ (p acc : Polynomial),
    denote ctx (p.foldl (fun acc m => (q.mulMonomial m).add acc) acc)
      = denote ctx acc + denote ctx p * denote ctx q := by
  intro p
  induction p with
  | nil => intro acc; simp [denote_nil]
  | cons m ms ih =>
    intro acc
    simp only [List.foldl_cons, ih, denote_add, denote_mulMonomial, denote_cons, Int.add_mul]
    simp only [Int.add_assoc, Int.add_comm, Int.add_left_comm]

theorem denote_mul {p q : Polynomial} : (p.mul q).denote ctx = p.denote ctx * q.denote ctx := by
  simp only [mul, denote_foldl_mul, denote_nil, Int.zero_add]

/-- The sum of a list of polynomials. -/
def denoteAll (ctx : Context) (ps : List Polynomial) : Int :=
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
    simp only [mergePairs, denoteAll_cons, denote_add, ih]
    omega
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
    | [p] => simp [mergeAll, denoteAll_cons, denoteAll_nil]
    | p :: q :: ps => simp only [mergeAll, denote_foldr_add]
  | succ n ih =>
    match ps with
    | [] => rfl
    | [p] => simp [mergeAll, denoteAll_cons, denoteAll_nil]
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
      have : Monomial.denote ctx m = 0 := by simp only [Monomial.denote, hz, Int.zero_mul]
      simp [denote_nil, this]
    · simp [denote_singleton]

/-- Sort and merge a flat list of monomials into a polynomial. -/
def normalize (l : Polynomial) : Polynomial :=
  mergeAll l.length (singletons l)

theorem denote_normalize {l : Polynomial} : denote ctx (normalize l) = denote ctx l := by
  simp only [normalize, denote_mergeAll, denoteAll_singletons]

end Polynomial

inductive Expr where
  | val (v : Int)
  | var (v : Nat)
  | neg (a : Expr)
  | add (a b : Expr)
  | sub (a b : Expr)
  | mul (a b : Expr)
deriving Inhabited, Repr

namespace Expr

def denote (ctx : Context) : Expr → Int
  | val v => v
  | var v => ctx v
  | neg a => -a.denote ctx
  | add a b => a.denote ctx + b.denote ctx
  | sub a b => a.denote ctx - b.denote ctx
  | mul a b => a.denote ctx * b.denote ctx

/-- Every product of a monomial of `p` with one of `q`, prepended to `acc`. -/
def appendMul (p q : Polynomial) (acc : Polynomial) : Polynomial :=
  p.foldr (fun m acc => q.foldr (fun n acc => m.mul n :: acc) acc) acc

/-- The monomials of an expression (negated when `sgn`), in the order they occur and without
    merging, prepended to `acc`. Collecting them in one pass and sorting once is what keeps the
    normal form cheap for the kernel to compute: folding a sum of `n` terms through a sorted
    insertion, as this used to do, copies the partial polynomial `n` times. -/
def flatten (sgn : Bool) : Expr → Polynomial → Polynomial
  | val v, acc =>
    let c := if sgn then -v else v
    if c = 0 then acc else { coeff := c, vars := [] } :: acc
  | var v, acc => { coeff := if sgn then -1 else 1, vars := [v] } :: acc
  | Expr.neg a, acc => flatten (!sgn) a acc
  | add a b, acc => flatten sgn a (flatten sgn b acc)
  | sub a b, acc => flatten sgn a (flatten (!sgn) b acc)
  | mul a b, acc => appendMul (flatten sgn a []) (flatten false b []) acc

def toPolynomial (e : Expr) : Polynomial :=
  Polynomial.normalize (e.flatten false [])

theorem denote_foldr_mulCons {m : Monomial} {q acc : Polynomial} :
    Polynomial.denote ctx (q.foldr (fun n acc => m.mul n :: acc) acc)
      = m.denote ctx * Polynomial.denote ctx q + Polynomial.denote ctx acc := by
  induction q with
  | nil => simp [Polynomial.denote_nil]
  | cons n q ihq =>
    simp only [List.foldr_cons, Polynomial.denote_cons, ihq, Monomial.denote_mul, Int.mul_add]
    omega

theorem appendMul_cons {m : Monomial} {p q acc : Polynomial} :
    appendMul (m :: p) q acc = q.foldr (fun n acc => m.mul n :: acc) (appendMul p q acc) := rfl

theorem denote_appendMul {p q acc : Polynomial} :
    Polynomial.denote ctx (appendMul p q acc)
      = Polynomial.denote ctx p * Polynomial.denote ctx q + Polynomial.denote ctx acc := by
  induction p generalizing acc with
  | nil => simp [appendMul, Polynomial.denote_nil]
  | cons m p ih =>
    rw [appendMul_cons, denote_foldr_mulCons, ih, Polynomial.denote_cons, Int.add_mul]
    omega

theorem denote_flatten (sgn : Bool) (e : Expr) (acc : Polynomial) :
    Polynomial.denote ctx (e.flatten sgn acc)
      = (if sgn then -e.denote ctx else e.denote ctx) + Polynomial.denote ctx acc := by
  induction e generalizing sgn acc with
  | val v =>
    simp only [flatten, denote]
    cases sgn <;> simp only [Bool.false_eq_true, ite_false, ite_true] <;> split <;>
      simp_all [Polynomial.denote_cons, Monomial.denote]
  | var v =>
    simp only [flatten, denote, Polynomial.denote_cons, Monomial.denote]
    cases sgn <;> simp
  | neg a ih =>
    simp only [flatten, denote, ih]
    cases sgn <;> simp
  | add a b iha ihb =>
    simp only [flatten, denote, iha, ihb]
    cases sgn <;> simp <;> omega
  | sub a b iha ihb =>
    simp only [flatten, denote, iha, ihb]
    cases sgn <;> simp <;> omega
  | mul a b iha ihb =>
    simp only [flatten, denote, denote_appendMul, iha sgn [], ihb false [],
      Polynomial.denote_nil, Int.add_zero]
    cases sgn <;> simp [Int.neg_mul]

theorem denote_toPolynomial {e : Expr} : e.denote ctx = e.toPolynomial.denote ctx := by
  simp only [toPolynomial, Polynomial.denote_normalize, denote_flatten, Polynomial.denote_nil,
    Int.add_zero, Bool.false_eq_true, ite_false]

theorem denote_eq_from_toPolynomial_eq {e₁ e₂ : Expr} (h : e₁.toPolynomial = e₂.toPolynomial) : e₁.denote ctx = e₂.denote ctx := by
  rw [denote_toPolynomial, denote_toPolynomial, h]

end PolyNorm.Expr

public meta section

open Lean Qq

abbrev PolyM := StateT (Array Q(Int)) MetaM

def getIndex (e : Q(Int)) : PolyM Nat := do
  let is ← get
  if let some i := is.findIdx? (· == e) then
    return i
  else
    let size := is.size
    set (is.push e)
    return size

partial def reify (e : Q(Int)) : PolyM Q(PolyNorm.Expr) := do
  if let some n := e.natLitOf? q(Int) then
    return q(.val (OfNat.ofNat $n))
  else if let some e := e.negOf? q(Int) then
    return q(.neg $(← reify e))
  else if let some (x, y) := e.hAddOf? q(Int) q(Int) then
    return q(.add $(← reify x) $(← reify y))
  else if let some (x, y) := e.hSubOf? q(Int) q(Int) then
    return q(.sub $(← reify x) $(← reify y))
  else if let some (x, y) := e.hMulOf? q(Int) q(Int) then
    return q(.mul $(← reify x) $(← reify y))
  else
    let v : Nat ← getIndex e
    return q(.var $v)

-- `logPolynomial` below calls this module's own non-`meta` `PolyNorm` functions, which the
-- phase-distinction check only allows within a single module under this option.
set_option compiler.relaxedMetaCheck true in
def polyNorm (mv : MVarId) : MetaM Unit := do
  let some (_, (l : Q(Int)), (r : Q(Int))) := (← mv.getType).eq?
    | throwError "[poly_norm] expected an equality, got {← mv.getType}"
  let (l, is) ← (reify l).run #[]
  let (r, is) ← (reify r).run is
  let ctx : Q(PolyNorm.Context) ← if h : 0 < is.size
    then do let is : Q(RArray Int) ← (RArray.ofArray is h).toExpr q(Int) id; pure q(«$is».get)
    else pure q(fun _ => 0)
  -- `decide`, not `Eq.refl`: given two `toPolynomial` applications the kernel unifies them by
  -- unfolding both in lockstep instead of evaluating each, which is catastrophic once the
  -- coefficients are large. Deciding the equality forces evaluation.
  let inst : Q(Decidable («$l».toPolynomial = «$r».toPolynomial)) ←
    Meta.synthInstance q(Decidable («$l».toPolynomial = «$r».toPolynomial))
  -- `.app`, as `nativePolyNorm` does: the `rfl` is what the kernel checks, not the elaborator
  let hp : Q(«$l».toPolynomial = «$r».toPolynomial) :=
    .app q(@of_decide_eq_true («$l».toPolynomial = «$r».toPolynomial) $inst) q(Eq.refl true)
  let he := q(@PolyNorm.Expr.denote_eq_from_toPolynomial_eq $ctx $l $r $hp)
  mv.assign he
where
  logPolynomial (e : Q(PolyNorm.Expr)) (es : Array Q(Int)) := do
    let p ← unsafe Meta.evalExpr PolyNorm.Expr q(PolyNorm.Expr) e
    let ppCtx := (es.getD · q(0))
    logInfo m!"poly := {PolyNorm.Polynomial.toExpr p.toPolynomial ppCtx}"

-- `logPolynomial` below calls this module's own non-`meta` `PolyNorm` functions, which the
-- phase-distinction check only allows within a single module under this option.
set_option compiler.relaxedMetaCheck true in
def nativePolyNorm (mv : MVarId) : MetaM Unit := do
  let some (_, (l : Q(Int)), (r : Q(Int))) := (← mv.getType).eq?
    | throwError "[poly_norm] expected an equality, got {← mv.getType}"
  let (l, is) ← (reify l).run #[]
  let (r, is) ← (reify r).run is
  let ctx : Q(PolyNorm.Context) ← if h : 0 < is.size
    then do let is : Q(RArray Int) ← (RArray.ofArray is h).toExpr q(Int) id; pure q(«$is».get)
    else pure q(fun _ => 0)
  let hp ← nativeDecide q(«$l».toPolynomial = «$r».toPolynomial)
  let he := q(@PolyNorm.Expr.denote_eq_from_toPolynomial_eq $ctx $l $r $hp)
  mv.assign he
where
  logPolynomial (e : Q(PolyNorm.Expr)) (es : Array Q(Int)) := do
    let p ← unsafe Meta.evalExpr PolyNorm.Expr q(PolyNorm.Expr) e
    let ppCtx := (es.getD · q(0))
    logInfo m!"poly := {PolyNorm.Polynomial.toExpr p.toPolynomial ppCtx}"
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
    Int.polyNorm mv
    replaceMainGoal []

syntax (name := nativePolyNorm) "native_poly_norm" : tactic

open Lean.Elab Tactic in
@[tactic nativePolyNorm] def evalNativePolyNorm : Tactic := fun _ =>
  withMainContext do
    let mv ← Tactic.getMainGoal
    Int.nativePolyNorm mv
    replaceMainGoal []

end Tactic

end

end Smt.Reconstruct.Int

example (x y z : Int) : 1 * (x + y) * z  = z * y + x * z := by
  poly_norm

example (x y z : Int) : 1 * (x + y) * z  = z * y + x * z := by
  native_poly_norm
