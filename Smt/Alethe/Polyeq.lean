/-
Copyright (c) 2021-2026 by the authors listed in the file AUTHORS and their
institutional affiliations. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Haniel Barbosa
-/

module

public import Smt.Alethe.Basic
public meta import Smt.Alethe.Basic

public meta section

/-!
# Equality of terms modulo the spelling of numerals

An `assume` of a proof must be an assertion of the problem. Carcara's `polyeq` elaboration pass
makes that syntactic: an `assume` that matches an assertion only up to the orientation of
equalities, the regrouping of associative applications or the names of bound variables is
replaced by the assertion itself, with explicit steps deriving the proof's spelling. So after the
pass every `assume` is an assertion of the problem *as Carcara identifies terms*.

Carcara identifies numerals by value: `0.0`, `0/1` and `(/ 0 1)` are one constant to it, so an
`assume` differing from its assertion only there is an exact match on the Carcara side, nothing is
elaborated, and its printer picks its own spelling for the output. The checker realizes both sides
through cvc5's parser, which is syntactic, and so sees two different terms. That is the one
difference this module accepts: `polyeq` compares two cvc5 terms structurally, numerals by value,
and `polyeqProof?` proves the two propositions equal by congruence down to the numerals, where the
kernel unfolds one spelling to the other. Anything beyond that (a flipped equality, a regrouped
application, a renamed binder) is not accepted, since the pass removes it before the proof reaches
the checker.
-/

namespace Smt.Alethe

open Lean Meta

/-- Are `a` and `b` the same cvc5 term up to the spelling of numerals (`0.0`, `0/1`, `(- 0)`,
    `(to_real 0)`, `(/ 1.0 3.0)`)? Everything else is compared syntactically: kinds, operators,
    arity, and the children in order. -/
partial def polyeq (a b : cvc5.Term) : Bool := Id.run do
  if a == b then return true
  if let some x := constValue? a then
    if let some y := constValue? b then
      return x == y
  if a.getKind! != b.getKind! then return false
  let n := a.getNumChildren
  if n == 0 || n != b.getNumChildren then return false
  if a.hasOp && b.hasOp && a.getOp! != b.getOp! then return false
  for i in [0:n] do
    if !polyeq a[i]! b[i]! then return false
  return true

/-- A proof of `a = b` for two propositions (or terms) that differ only in subterms that are
    definitionally equal once everything is unfolded, which is what two spellings of one numeral
    are (`0 / 1` and `0`). `none` when they cannot be reconciled.

    The proof is by congruence, one differing argument at a time, `forall_congr` /
    `implies_congr` / `funext` under binders, and `Eq.refl` (checked by the kernel, which unfolds
    everything) at the leaves. -/
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
    goArgs f as bs

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
