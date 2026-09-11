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

public meta section

/-!
# Equality of terms modulo representation (Carcara's `polyeq`)

An `assume` of a proof must be an assertion of the problem, but the solver may spell the same
assertion differently: cvc5 prints every rational as `n/d` (`0/1` for the problem's `0.0`), an
equality may come flipped, bound variables renamed, an associative application regrouped. Carcara
accepts an `assume` that matches an assertion up to these (`polyeq` with `mod_reordering`,
`mod_nary` and `alpha_equiv`, in `checker/shared.rs`). `polyeq` below does the same on cvc5 terms,
and `polyeqProof?` then proves the two propositions equal, so that the assertion's hypothesis can
stand for the assumption.
-/

namespace Smt.Alethe

open Lean Meta

/-- The kinds whose applications are compared after flattening, so that `(+ (+ a b) c)` and
    `(+ a b c)` are the same term. -/
def assocKinds : List cvc5.Kind :=
  [.AND, .OR, .ADD, .MULT, .STRING_CONCAT,
   .BITVECTOR_ADD, .BITVECTOR_MULT, .BITVECTOR_AND, .BITVECTOR_OR, .BITVECTOR_XOR,
   .BITVECTOR_CONCAT]

/-- The kinds binding the variables of their first child (a `VARIABLE_LIST`). -/
def binderKinds : List cvc5.Kind := [.FORALL, .EXISTS, .LAMBDA]

/-- The children of the nested applications of kind `k` in `t`, in order. -/
partial def flattenKind (k : cvc5.Kind) (t : cvc5.Term) : Array cvc5.Term :=
  if t.getKind! == k then t.getChildren.flatMap (flattenKind k) else #[t]

/-- Carcara's `polyeq`: are `a` and `b` the same term up to the orientation of equalities, the
    regrouping of associative applications, the names of bound variables, and the spelling of
    numerals (`0.0`, `0/1`, `(- 0)`, `(to_real 0)`)? -/
partial def polyeq (a b : cvc5.Term) : Bool := go [] a b
where
  /-- `bound` pairs the variables bound so far in `a` with those bound in `b`, innermost first. -/
  go (bound : List (cvc5.Term × cvc5.Term)) (a b : cvc5.Term) : Bool := Id.run do
    -- a syntactically equal pair is equal, unless it mentions bound variables that were paired
    -- with something else
    if bound.isEmpty && a == b then return true
    -- numerals, by value
    if let some x := constValue? a then
      if let some y := constValue? b then
        return x == y
    let ka := a.getKind!
    let kb := b.getKind!
    -- bound variables, by position
    if ka == .VARIABLE || kb == .VARIABLE then
      return match bound.find? (fun (x, y) => x == a || y == b) with
        | some (x, y) => x == a && y == b
        | none => a == b
    if ka != kb then return false
    let n := a.getNumChildren
    if n == 0 then return a == b
    if a.hasOp && b.hasOp && a.getOp! != b.getOp! then return false
    -- binders: pair the variables, compare the bodies
    if binderKinds.contains ka then
      if n != b.getNumChildren then return false
      let xs := a[0]!.getChildren
      let ys := b[0]!.getChildren
      if xs.size != ys.size then return false
      for x in xs, y in ys do
        if x.getSort! != y.getSort! then return false
      let bound := (xs.zip ys).toList.reverse ++ bound
      for i in [1:n] do
        if !go bound a[i]! b[i]! then return false
      return true
    -- equalities, in either orientation
    if ka == .EQUAL && n == 2 && b.getNumChildren == 2 then
      return (go bound a[0]! b[0]! && go bound a[1]! b[1]!)
          || (go bound a[0]! b[1]! && go bound a[1]! b[0]!)
    -- applications: childwise, else after flattening an associative kind
    if n == b.getNumChildren then
      let mut eq := true
      for i in [0:n] do
        if !go bound a[i]! b[i]! then
          eq := false
          break
      if eq then return true
    if assocKinds.contains ka then
      let as := flattenKind ka a
      let bs := flattenKind ka b
      if as.size == bs.size && (as.size != n || bs.size != b.getNumChildren) then
        for x in as, y in bs do
          if !go bound x y then return false
        return true
    return false

/-- A proof of `a = b` for two propositions (or terms) that differ only in the orientation of
    equalities, the names of bound variables, and subterms that are definitionally equal once
    everything is unfolded (numerals: `0 / 1` and `0`). `none` when they cannot be reconciled;
    in particular a regrouped `∧`-chain is not handled.

    The proof is by congruence, one differing argument at a time, with `eq_symm_eq` for flipped
    equalities, `forall_congr` / `implies_congr` / `funext` under binders, and `Eq.refl` (checked
    by the kernel, which unfolds everything) at the leaves. -/
partial def polyeqProof? (a b : Expr) : MetaM (Option Expr) := do
  let some h ← go a b | return none
  return some (← mkExpectedTypeHint h (← mkEq a b))
where
  go (a b : Expr) : MetaM (Option Expr) := do
    if a == b then return some (← Meta.mkEqRefl a)
    let r ← match a, b with
      | .app .., .app .. => goApp a b
      | .forallE n d body bi, .forallE _ d' body' _ =>
        if body.hasLooseBVars || body'.hasLooseBVars then goForall n d body bi d' body'
        else goImplies d body d' body'
      | .lam n d body bi, .lam _ d' body' _ => goLam n d body bi d' body'
      | _, _ => pure none
    if r.isSome then return r
    leaf a b

  /-- `a = b` by `Eq.refl` when the two are definitionally equal with everything unfolded. -/
  leaf (a b : Expr) : MetaM (Option Expr) := do
    if ← withTransparency .all (isDefEq a b) then
      return some (← mkExpectedTypeHint (← Meta.mkEqRefl a) (← mkEq a b))
    return none

  goApp (a b : Expr) : MetaM (Option Expr) := do
    let f := a.getAppFn
    let as := a.getAppArgs
    let bs := b.getAppArgs
    if f != b.getAppFn || as.size != bs.size then return none
    if let some h ← goArgs f as bs then return some h
    -- `(x = y) = (y = x) = (u = v)`
    if let some (α, x, y) := a.eq? then
      if b.isEq then
        if let some h ← goArgs f #[α, y, x] bs then
          let hflip := mkApp3 (mkConst ``eq_symm_eq [← getLevel α]) α x y
          return some (← mkEqTrans hflip h)
    return none

  /-- `f as = f bs`, replacing one argument at a time. -/
  goArgs (f : Expr) (as bs : Array Expr) : MetaM (Option Expr) := do
    let mut cur := as
    let mut h : Option Expr := none
    for i in [0:as.size] do
      if cur[i]! == bs[i]! then continue
      let some hi ← go cur[i]! bs[i]! | return none
      let next := cur.set! i bs[i]!
      let lhs := mkAppN f cur
      let rhs := mkAppN f next
      let step ←
        try
          let motive := mkLambda `z .default (← inferType cur[i]!) (mkAppN f (cur.set! i (.bvar 0)))
          mkExpectedTypeHint (← mkCongrArg motive hi) (← mkEq lhs rhs)
        catch _ =>
          -- a dependent position (a type, an instance): only if the kernel can see it
          let some step ← leaf lhs rhs | return none
          pure step
      h := some (← match h with
        | some hprev => mkEqTrans hprev step
        | none => pure step)
      cur := next
    return h

  goForall (n : Name) (d body : Expr) (bi : BinderInfo) (d' body' : Expr) :
      MetaM (Option Expr) := do
    unless d == d' do return none
    withLocalDecl n bi d fun x => do
      let bx := body.instantiate1 x
      let bx' := body'.instantiate1 x
      let some h ← go bx bx' | return none
      let p ← mkLambdaFVars #[x] bx
      let q ← mkLambdaFVars #[x] bx'
      let hf ← mkLambdaFVars #[x] h
      return some (mkApp4 (mkConst ``forall_congr [← getLevel d]) d p q hf)

  goImplies (d body d' body' : Expr) : MetaM (Option Expr) := do
    let some h₁ ← go d d' | return none
    let some h₂ ← go body body' | return none
    return some (← mkAppM ``implies_congr #[h₁, h₂])

  goLam (n : Name) (d body : Expr) (bi : BinderInfo) (d' body' : Expr) : MetaM (Option Expr) := do
    unless d == d' do return none
    withLocalDecl n bi d fun x => do
      let bx := body.instantiate1 x
      let bx' := body'.instantiate1 x
      let some h ← go bx bx' | return none
      let f ← mkLambdaFVars #[x] bx
      let g ← mkLambdaFVars #[x] bx'
      let hf ← mkLambdaFVars #[x] h
      let τ ← inferType bx
      let β ← mkLambdaFVars #[x] τ
      return some (mkApp5 (mkConst ``funext [← getLevel d, ← getLevel τ]) d β f g hf)

end Smt.Alethe
