/-
Copyright (c) 2021-2026 by the authors listed in the file AUTHORS and their
institutional affiliations. All rights reserved.
Authors: Haniel Barbosa
-/

module

public import Smt.Alethe.Clause
public meta import Smt.Alethe.Clause
public import Smt.Reconstruct.Int
public meta import Smt.Reconstruct.Int
public import Smt.Reconstruct.Rat
public meta import Smt.Reconstruct.Rat

public meta section

/-!
# Linear arithmetic rules

`la_generic` is replayed as a Farkas combination: the negations of the clause's literals are
assumed, oriented into bounds, strengthened (strict integer bounds), scaled by the coefficients
given as `:args`, summed with the `sum_ub` lemmas, and refuted through the normalized difference
of the two sides (`poly_norm`) and a decidable fact about the resulting constant.

`poly_simp`, `poly_simp_rel`, `la_mult_pos`/`la_mult_neg`, `la_disequality`, `la_totality` map
onto `Smt.Reconstruct.Int` and `Smt.Reconstruct.Rat`.
-/

namespace Smt.Alethe

open Lean Qq
open Smt.Reconstruct

/-- The relation of a bound. -/
inductive Rel where
  | lt | le | eq
deriving BEq, Repr, Inhabited

/-- A hypothesis `a ⋈ b`. -/
structure Bound where
  rel : Rel
  a : Expr
  b : Expr
  proof : Expr
deriving Inhabited

/-- Read a bound off the type of a proof (`a < b`, `a ≤ b`, `a = b`, `a > b`, `a ≥ b`). -/
def boundOf (h : Expr) : MetaM Bound := do
  let t ← Meta.whnfR (← Meta.inferType h)
  match t.getAppFnArgs with
  | (``LT.lt, #[_, _, a, b]) => return { rel := .lt, a, b, proof := h }
  | (``LE.le, #[_, _, a, b]) => return { rel := .le, a, b, proof := h }
  | (``GT.gt, #[_, _, a, b]) => return { rel := .lt, a := b, b := a, proof := h }
  | (``GE.ge, #[_, _, a, b]) => return { rel := .le, a := b, b := a, proof := h }
  | (``Eq, #[_, a, b]) => return { rel := .eq, a, b, proof := h }
  | _ => throwError "not a bound: {t}"

/-- Linear combinations over cvc5 terms (atoms) with rational coefficients, plus a constant. -/
structure LinComb where
  coeffs : Std.HashMap cvc5.Term Rat := {}
  const : Rat := 0
deriving Inhabited

namespace LinComb

def add (p q : LinComb) : LinComb :=
  { coeffs := q.coeffs.fold (fun m t c => m.insert t (m.getD t 0 + c)) p.coeffs,
    const := p.const + q.const }

def scale (c : Rat) (p : LinComb) : LinComb :=
  { coeffs := p.coeffs.fold (fun m t k => m.insert t (c * k)) {}, const := c * p.const }

def neg (p : LinComb) : LinComb := scale (-1) p

def isConstant (p : LinComb) : Bool :=
  p.coeffs.fold (fun b _ c => b && c == 0) true

end LinComb

/-- The constant value of a numeral term, if it is one. -/
partial def constValue? (t : cvc5.Term) : Option Rat :=
  match t.getKind! with
  | .CONST_INTEGER => some t.getIntegerValue!
  | .CONST_RATIONAL => some t.getRationalValue!
  | .NEG => (- ·) <$> constValue? t[0]!
  | .TO_REAL => constValue? t[0]!
  | .DIVISION => do
    let n ← constValue? t[0]!
    let d ← constValue? t[1]!
    if d == 0 then none else some (n / d)
  | _ => none

/-- The linear combination denoted by an arithmetic term. -/
partial def linComb (t : cvc5.Term) : LinComb :=
  if let some c := constValue? t then { const := c } else
  match t.getKind! with
  | .ADD => (nary .ADD t).foldl (fun p u => p.add (linComb u)) {}
  | .SUB =>
    let cs := nary .SUB t
    cs[1:].foldl (fun p u => p.add (linComb u).neg) (linComb cs[0]!)
  | .NEG => (linComb t[0]!).neg
  | .TO_REAL => linComb t[0]!
  | .DIVISION =>
    match constValue? t[1]!, t.getNumChildren with
    | some d, 2 => if d == 0 then { coeffs := (∅ : Std.HashMap cvc5.Term Rat).insert t 1 } else (linComb t[0]!).scale (1 / d)
    | _, _ => { coeffs := (∅ : Std.HashMap cvc5.Term Rat).insert t 1 }
  | .MULT =>
    let cs := nary .MULT t
    -- a product is linear if all factors but one are constants
    let (consts, others) := cs.partition (constValue? · |>.isSome)
    let k := consts.foldl (fun k u => k * (constValue? u).get!) (1 : Rat)
    match others with
    | #[] => { const := k }
    | #[u] => (linComb u).scale k
    | _ => { coeffs := (∅ : Std.HashMap cvc5.Term Rat).insert t 1 }
  | _ => { coeffs := (∅ : Std.HashMap cvc5.Term Rat).insert t 1 }

/-- The linear combination `lhs - rhs` and relation of a (possibly negated) literal, as the bound
    obtained by *negating* the literal: `¬(a < b)` gives `b ≤ a`, etc. -/
def negatedLiteral (l : cvc5.Term) : Option (Rel × cvc5.Term × cvc5.Term) :=
  let pos (u : cvc5.Term) : Option (Rel × cvc5.Term × cvc5.Term) :=
    match u.getKind! with
    | .LT => some (.lt, u[0]!, u[1]!)
    | .LEQ => some (.le, u[0]!, u[1]!)
    | .GT => some (.lt, u[1]!, u[0]!)
    | .GEQ => some (.le, u[1]!, u[0]!)
    | .EQUAL => some (.eq, u[0]!, u[1]!)
    | _ => none
  match l.getKind! with
  | .NOT => pos l[0]!
  | .LT => some (.le, l[1]!, l[0]!)
  | .LEQ => some (.lt, l[1]!, l[0]!)
  | .GT => some (.le, l[0]!, l[1]!)
  | .GEQ => some (.lt, l[0]!, l[1]!)
  | _ => none

/-- Lemma names for one sort. -/
structure ArithNames where
  int : Bool
  notLt : Name
  notLe : Name
  mulPos : Rel → Name
  mulNegEq : Name
  sumUb : Rel → Rel → Name
  farkas : Rel → Name
  polyNorm : MVarId → MetaM Unit

def intNames : ArithNames :=
  { int := true, notLt := ``Int.not_lt, notLe := ``Int.not_le,
    mulPos := fun | .lt => ``Int.mul_pos_lt | .le => ``Int.mul_pos_le | .eq => ``Int.mul_pos_eq,
    mulNegEq := ``Int.mul_neg_eq,
    sumUb := sumUbName `Smt.Reconstruct.Int,
    farkas := fun | .lt => ``Int.farkas_lt | .le => ``Int.farkas_le | .eq => ``Int.farkas_eq,
    polyNorm := Int.polyNorm }
where
  sumUbName (ns : Name) : Rel → Rel → Name
    | .lt, .lt => ns ++ `sum_ub₁ | .lt, .le => ns ++ `sum_ub₂ | .lt, .eq => ns ++ `sum_ub₃
    | .le, .lt => ns ++ `sum_ub₄ | .le, .le => ns ++ `sum_ub₅ | .le, .eq => ns ++ `sum_ub₆
    | .eq, .lt => ns ++ `sum_ub₇ | .eq, .le => ns ++ `sum_ub₈ | .eq, .eq => ns ++ `sum_ub₉

def ratNames : ArithNames :=
  { int := false, notLt := ``Rat.not_lt, notLe := ``Rat.not_le,
    mulPos := fun | .lt => ``Rat.mul_pos_lt | .le => ``Rat.mul_pos_le | .eq => ``Rat.mul_pos_eq,
    mulNegEq := ``Rat.mul_neg_eq,
    sumUb := intNames.sumUbName `Smt.Reconstruct.Rat,
    farkas := fun | .lt => ``Rat.farkas_lt | .le => ``Rat.farkas_le | .eq => ``Rat.farkas_eq,
    polyNorm := Rat.polyNorm }

def relJoin : Rel → Rel → Rel
  | .lt, _ | _, .lt => .lt
  | .le, _ | _, .le => .le
  | .eq, .eq => .eq

/-- The numeral `c` as an expression of the sort. -/
def numeral (names : ArithNames) (c : Rat) : Expr :=
  if names.int then toExpr c.num else toExpr c

/-- A proof of a decidable fact by kernel evaluation. -/
def decideProof' (p : Expr) : MetaM Expr := do
  let inst ← Meta.synthInstance (mkApp (mkConst ``Decidable) p)
  return mkApp3 (mkConst ``of_decide_eq_true) p inst (mkApp2 (mkConst ``Eq.refl [.succ .zero]) (mkConst ``Bool) (mkConst ``Bool.true))

/-- An argument of a real-sorted operation: integer-sorted terms are cast (cvc5's Alethe proofs mix
    integer and real terms). -/
def ratArg (t : cvc5.Term) : ReconstructM Expr := do
  if t.getSort!.isInteger then
    if let some c := constValue? t then
      return toExpr c
    let x : Q(Int) ← reconstructTerm t
    return q($x : Rat)
  reconstructTerm t

/-- Whether every side of every arithmetic literal of the clause is integer-sorted. -/
def allInt (lits : Array cvc5.Term) : Bool :=
  lits.all fun l => match negatedLiteral l with
    | some (_, a, b) => a.getSort!.isInteger && b.getSort!.isInteger
    | none => true

/-- `la_generic`. -/
def reconstructLaGeneric (s : Step) : ReconstructM Expr := do
  if s.lits.isEmpty then throwError "la_generic: empty clause"
  if (s.lits.findSome? negatedLiteral).isNone then throwError "la_generic: no arithmetic literal"
  let int := allInt s.lits
  let names := if int then intNames else ratNames
  -- coefficients (missing ones are 1); over the integers, clear denominators
  let mut coeffs : Array Rat := #[]
  for i in [0:s.lits.size] do
    coeffs := coeffs.push ((s.args[i]? >>= Arg.rat?).getD 1)
  if int then
    let l := coeffs.foldl (fun l c => Nat.lcm l c.den) 1
    coeffs := coeffs.map (· * l)
  -- Carcara's convention: a negated inequality is oriented as `s > 0`/`s ≥ 0` and multiplied by
  -- `|c|`; a negated equality stays `s1 - s2 = 0` and is multiplied by the signed `c`. Here the
  -- inequalities are oriented the other way (`a - b < 0`), so equalities take `-c`.
  coeffs := (s.lits.zip coeffs).map fun (l, c) =>
    match negatedLiteral l with
    | some (.eq, _, _) => -c
    | _ => c.abs
  -- the combination must be contradictory: compute it first
  let mut comb : LinComb := {}
  let mut rel : Rel := .eq
  let mut used := #[]
  for l in s.lits, c in coeffs do
    match negatedLiteral l with
    | none => used := used.push false
    | some (r, a, b) =>
      if c == 0 then used := used.push false; continue
      let mut p := (linComb a).add (linComb b).neg  -- a - b ⋈ 0
      let mut r := r
      if int && r == .lt then
        -- a < b  ⟹  a + 1 ≤ b
        p := { p with const := p.const + 1 }
        r := .le
      comb := comb.add (p.scale c)
      rel := relJoin rel r
      used := used.push true
  if !comb.isConstant then
    let left := comb.coeffs.toList.filter (·.2 != 0) |>.map fun (t, c) => s!"{c} · {t}"
    throwError "la_generic: the combination does not cancel: leftover {", ".intercalate left}"
  let k := comb.const  -- Σ cᵢ (aᵢ - bᵢ) = k, with Σ cᵢ aᵢ ⋈ Σ cᵢ bᵢ
  let contradictory := match rel with
    | .lt => k ≥ 0
    | .le => k > 0
    | .eq => k != 0
  if !contradictory then throwError "la_generic: the combination is not contradictory ({repr rel} with constant {k})"
  -- the hypotheses ¬lᵢ
  let ps ← mkPropList s.lits
  let decls ← s.lits.mapIdxM fun i l => do
    let p ← reconstructTerm l
    return (Name.num `h i, fun (_ : Array Expr) => pure (mkApp (mkConst ``Not) p))
  let h ← Meta.withLocalDeclsD decls fun hs => do
    let mut acc : Option Bound := none
    for l in s.lits, c in coeffs, u in used, hneg in hs do
      if !u then continue
      let some (r, _, _) := negatedLiteral l | continue
      -- orient the hypothesis into a positive bound: `¬(a < b)` gives `b ≤ a`, etc.
      let mut h : Expr ← match l.getKind! with
        | .NOT => Meta.mkAppM ``Prop.notNotElim #[hneg]
        | .LT | .GT | .LEQ | .GEQ => do
          let ty ← Meta.whnfR (← Meta.inferType hneg)
          let some p := ty.not? | throwError "la_generic: expected a negated literal"
          let (n, a, b) ← match p.getAppFnArgs with
            | (``LT.lt, #[_, _, a, b]) => pure (names.notLt, a, b)
            | (``GT.gt, #[_, _, a, b]) => pure (names.notLt, b, a)
            | (``LE.le, #[_, _, a, b]) => pure (names.notLe, a, b)
            | (``GE.ge, #[_, _, a, b]) => pure (names.notLe, b, a)
            | _ => throwError "la_generic: unexpected literal {l}"
          Meta.mkAppM ``Iff.mp #[← Meta.mkAppOptM n #[a, b], hneg]
        | _ => throwError "la_generic: unexpected literal {l}"
      -- an integer literal in a rational combination: cast the bound to `Rat`
      if !int then
        if let some (_, a, b) := negatedLiteral l then
          if a.getSort!.isInteger && b.getSort!.isInteger then
            let ty ← Meta.whnfR (← Meta.inferType h)
            let n ← match ty.getAppFn.constName? with
              | some ``LE.le => pure ``Rat.intCast_le_intCast
              | some ``LT.lt => pure ``Rat.intCast_lt_intCast
              | some ``Eq => pure ``Rat.intCast_inj
              | _ => throwError "la_generic: unexpected integer bound {ty}"
            let (x, y) := (ty.appFn!.appArg!, ty.appArg!)
            h ← Meta.mkAppM ``Iff.mpr #[← Meta.mkAppOptM n #[x, y], h]
      let mut bd ← boundOf h
      -- strengthen strict integer bounds
      if int && r == .lt then
        h ← Meta.mkAppM ``Iff.mpr #[← Meta.mkAppOptM ``Int.add_one_le_iff #[bd.a, bd.b], h]
        bd ← boundOf h
      -- scale
      if c != 1 then
        let ce := numeral names c
        let hc ← decideProof' (← Meta.mkAppM (if c > 0 then ``GT.gt else ``LT.lt) #[ce, numeral names 0])
        let lemma := if c > 0 then names.mulPos bd.rel else names.mulNegEq
        h ← Meta.mkAppM lemma #[← Meta.mkAppM ``And.intro #[hc, h]]
        bd ← boundOf h
      -- sum
      acc := some (← match acc with
        | none => pure bd
        | some prev => do
          let h' ← Meta.mkAppM (names.sumUb prev.rel bd.rel) #[prev.proof, h]
          boundOf h')
    let some sum := acc | throwError "la_generic: no usable literal"
    -- refute: sum.a - sum.b = k by poly_norm, and the sign of k by evaluation
    let ke := numeral names k
    let eqGoal ← Meta.mkAppM ``Eq #[← Meta.mkAppM ``HSub.hSub #[sum.a, sum.b], ke]
    let hk ← Meta.mkFreshExprMVar eqGoal
    names.polyNorm hk.mvarId!
    let signGoal ← match sum.rel with
      | .lt => Meta.mkAppM ``LE.le #[numeral names 0, ke]
      | .le => Meta.mkAppM ``LT.lt #[numeral names 0, ke]
      | .eq => Meta.mkAppM ``Ne #[ke, numeral names 0]
    let hk0 ← decideProof' signGoal
    let hfalse ← Meta.mkAppM (names.farkas sum.rel) #[sum.proof, hk, hk0]
    Meta.mkLambdaFVars hs hfalse
  return mkApp2 (mkConst ``orN_of_impliesN_not) ps h

/-- `la_mult_pos` / `la_mult_neg`: `(=> (and (⋈₀ m 0) (⋈ a b)) (⋈' (* m a) (* m b)))`. -/
def reconstructLaMult (s : Step) (pos : Bool) : ReconstructM Expr := do
  let t := s.lits[0]!
  if t.getKind! != .IMPLIES then throwError "la_mult: expected an implication"
  let conj := t[0]!
  if conj.getKind! != .AND || conj.getNumChildren != 2 then throwError "la_mult: expected a conjunction"
  let m := conj[0]![0]!
  let rel := conj[1]!
  let int := m.getSort!.isInteger && rel[0]!.getSort!.isInteger && rel[1]!.getSort!.isInteger
  let ns : Name := if int then `Smt.Reconstruct.Int else `Smt.Reconstruct.Rat
  let suffix := match rel.getKind! with
    | .LT => "lt" | .LEQ => "le" | .GT => "gt" | .GEQ => "ge" | .EQUAL => "eq" | _ => ""
  if suffix.isEmpty then throwError "la_mult: unexpected relation {rel}"
  let n := ns ++ Name.mkSimple ((if pos then "mul_pos_" else "mul_neg_") ++ suffix)
  let arg := if int then reconstructTerm else ratArg
  let a ← arg rel[0]!
  let b ← arg rel[1]!
  let me ← arg m
  addThm s.concl (← Meta.mkAppOptM n #[a, b, me])

@[alethe_rule_reconstruct] def reconstructArith : RuleReconstructor := fun s => do
  match s.rule with
  | "la_generic" | "la_tautology" => addThm s.concl (← reconstructLaGeneric s)
  | "la_rw_eq" =>
    -- (cl (= (= t u) (and (<= t u) (<= u t))))
    let eq := s.lits[0]![0]!
    let int := eq[0]!.getSort!.isInteger && eq[1]!.getSort!.isInteger
    let n : Name := (if int then `Smt.Alethe.Int else `Smt.Alethe.Rat) ++ `la_rw_eq
    let arg := if int then reconstructTerm else ratArg
    addThm s.concl (← Meta.mkAppOptM n #[← arg eq[0]!, ← arg eq[1]!])
  | "la_mult_sign" =>
    -- (cl (=> hyps (⋈ monomial 0))): the sign of a monomial from the signs of its factors
    let t := s.lits[0]!
    if t.getKind! != .IMPLIES then throwError "la_mult_sign: expected an implication"
    let (_, h) ← if allInt #[t[1]!] then Int.reconstructMulSignTerms t[0]! t[1]!
      else Rat.reconstructMulSignTerms t[0]! t[1]!
    addThm s.concl h
  | "div_intro" =>
    let t := s.lits[0]!
    match t.getKind! with
    | .AND =>
      if t[0]!.getKind! == .IMPLIES then
        -- (and (=> (> b 0) (and …)) (=> (< b 0) (and …))): the bounds under each sign of `b`
        let bound := t[0]![1]![0]!   -- (<= (* b (div a b)) a)
        let b ← reconstructTerm bound[0]![0]!
        let a ← reconstructTerm bound[1]!
        let pos ← Meta.mkAppOptM ``div_intro_pos #[a, b]
        let neg ← Meta.mkAppOptM ``div_intro_neg #[a, b]
        addThm s.concl (← Meta.mkAppM ``And.intro #[pos, neg])
      else
        -- division by a constant: (and (<= (* b (div a b)) a) (< a (* b (+ (div a b) ±1))))
        addTac s.concl fun mv => do
          let some g ← mv.falseOrByContra | return
          g.withContext do Lean.Elab.Tactic.Omega.omega (← Lean.getLocalHyps).toList g {}
    | .IMPLIES =>
      -- (=> (not (= b 0)) (= (* b (/ a b)) a)), real division
      let div := t[1]![0]![1]!
      if div[0]!.getSort!.isInteger || div[1]!.getSort!.isInteger then
        throwError "div_intro: real division of integer terms is not supported"
      let a ← reconstructTerm div[0]!
      let b ← reconstructTerm div[1]!
      addThm s.concl (← Meta.mkAppOptM ``div_intro_real #[a, b])
    | _ => throwError "div_intro: unexpected shape {t}"
  | "div_by_zero_intro" =>
    -- (= (op a b) (ite (= b 0) (choice ((y T)) (= y (op a 0))) (op a b)))
    let t := s.lits[0]!
    let lhs ← reconstructTerm t[0]!
    let b ← reconstructTerm t[0]![1]!
    let z ← reconstructTerm t[1]![0]![1]!
    let rhs ← reconstructTerm t[1]!
    -- the `Nonempty` instance of the reconstructed epsilon term
    let iteArgs := rhs.getAppArgs
    unless iteArgs.size == 5 do throwError "div_by_zero_intro: unexpected right-hand side {rhs}"
    let epsArgs := iteArgs[3]!.getAppArgs
    unless epsArgs.size == 3 do throwError "div_by_zero_intro: unexpected epsilon term {iteArgs[3]!}"
    let inst := epsArgs[1]!
    let f := Expr.lam `x (← Meta.inferType b) (lhs.abstract #[b]) .default
    addThm s.concl (← Meta.mkAppOptM ``div_by_zero_intro #[none, none, inst, f, b, z, none])
  | "la_mult_pos" => reconstructLaMult s true
  | "la_mult_neg" => reconstructLaMult s false
  | "la_disequality" | "la_totality" =>
    -- a single `or` literal
    let t := s.lits[0]!
    let eqt := (nary .OR t)[0]!
    let int := eqt[0]!.getSort!.isInteger && eqt[1]!.getSort!.isInteger
    let n : Name := (if int then `Smt.Alethe.Int else `Smt.Alethe.Rat) ++ Name.mkSimple s.rule
    let arg := if int then reconstructTerm else ratArg
    let ae ← arg eqt[0]!
    let be ← arg eqt[1]!
    addThm s.concl (← Meta.mkAppOptM n #[ae, be])
  | "poly_simp" =>
    let t := s.lits[0]!
    if t.getKind! != .EQUAL then throwError "poly_simp: expected an equality"
    let tac := if t[0]!.getSort!.isInteger then Int.polyNorm else Rat.polyNorm
    addTac s.concl tac
  | "poly_simp_rel" =>
    let pr := s.premise! 0
    let rel := s.lits[0]![0]!
    let rel' := s.lits[0]![1]!
    let cx := pr.lits[0]![0]![0]!
    let cy := pr.lits[0]![1]![0]!
    let bothInt := rel[0]!.getSort!.isInteger && rel[1]!.getSort!.isInteger
      && rel'[0]!.getSort!.isInteger && rel'[1]!.getSort!.isInteger
    if bothInt && pr.lits[0]![0]!.getSort!.isInteger then
      let some e ← Int.reconstructArithPolyNormRel pr.lits[0]! pr.proof s.lits[0]! | return none
      return ← addThm s.concl e
    if bothInt then
      -- integer sides, rational coefficients
      let some lcx := constValue? cx | throwError "poly_simp_rel: non-constant coefficient"
      let pos := lcx > 0
      let k := rel.getKind!
      let base := if k == .LT then "lt" else if k == .LEQ then "le" else if k == .GEQ then "ge"
        else if k == .GT then "gt" else "eq"
      let n : Name := `Smt.Alethe.Rat ++ Name.mkSimple
        (if base == "eq" then "eq_of_sub_eq_int"
         else base ++ (if pos then "_of_sub_eq_pos_int" else "_of_sub_eq_neg_int"))
      let x₁ ← reconstructTerm rel[0]!
      let x₂ ← reconstructTerm rel[1]!
      let y₁ ← reconstructTerm rel'[0]!
      let y₂ ← reconstructTerm rel'[1]!
      let cxE ← ratArg cx
      let cyE ← ratArg cy
      let zero : Expr := toExpr (0 : Rat)
      let side (c : Expr) : ReconstructM Expr := do
        if k == .EQUAL then decideProof' (← Meta.mkAppM ``Ne #[c, zero])
        else if pos then decideProof' (← Meta.mkAppM ``GT.gt #[c, zero])
        else decideProof' (← Meta.mkAppM ``LT.lt #[c, zero])
      let hcx ← side cxE
      let hcy ← side cyE
      return ← addThm s.concl (← Meta.mkAppOptM n #[x₁, x₂, y₁, y₂, cxE, cyE, hcx, hcy, pr.proof])
    let some e ← Rat.reconstructArithPolyNormRel pr.lits[0]! pr.proof s.lits[0]! | return none
    addThm s.concl e
  | _ => return none

end Smt.Alethe
