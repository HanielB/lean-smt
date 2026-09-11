/-
Copyright (c) 2021-2026 by the authors listed in the file AUTHORS and their
institutional affiliations. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Haniel Barbosa
-/

module

public import Smt.Alethe.Clause
public meta import Smt.Alethe.Clause
public import Smt.Reconstruct.Quant
public meta import Smt.Reconstruct.Quant
public import Smt.Reconstruct.Util
public meta import Smt.Reconstruct.Util
public import Smt.Reconstruct.Prop
public meta import Smt.Reconstruct.Prop

public meta section

/-!
# Quantifier rules

`forall_inst`, the binder rules closing subproofs (`bind`, `sko_ex`, `sko_forall`; anchor
assignments are let-bound in the driver, so the substitution is definitional), and the
quantifier rewrites shared with `Smt.Reconstruct.Quant` (`qnt_rm_unused`, `qnt_join`,
`miniscope_*`).
-/

namespace Smt.Alethe

open Lean Qq
open Smt.Reconstruct

/-- Replace the let-bound anchor variables of `ctx` by their values in `e`. -/
def zetaAssigns (ctx : AnchorCtx) (e : Expr) : Expr :=
  -- in anchor order: a later assignment's value may mention an earlier assigned variable, and an
  -- earlier assignment's value may be a later one's variable (veriT's chained renamings
  -- `(:= x y) (:= y z)`); applying them innermost-first, once each, would leave the `y` that
  -- substituting `x` introduced un-reduced. Apply in order and repeat until nothing changes.
  let step (e : Expr) := ctx.assigns.foldl (fun e (_, _, fv, _, te) => e.replaceFVar fv te) e
  let rec go (e : Expr) (fuel : Nat) : Expr :=
    match fuel with
    | 0 => e
    | fuel + 1 => let e' := step e; if e' == e then e else go e' fuel
  go e (ctx.assigns.size + 1)

/-- `(∀ ys, p) = (∀ ys, q)` (or with `∃`) from `h : p = q` over the fvars `ys`. -/
def congrBinders (exists_ : Bool) (ys : Array Expr) (p q h : Expr) : MetaM (Expr × Expr × Expr) := do
  let f : Expr → Expr × Expr × Expr → MetaM (Expr × Expr × Expr) := fun x (p, q, h) => do
    let u ← Meta.getLevel (← Meta.inferType x)
    let α ← Meta.inferType x
    let lp ← Meta.mkLambdaFVars #[x] p
    let lq ← Meta.mkLambdaFVars #[x] q
    let hx ← Meta.mkLambdaFVars #[x] h
    if exists_ then
      let ep ← Meta.mkExistsFVars #[x] p
      let eq ← Meta.mkExistsFVars #[x] q
      return (ep, eq, mkApp4 (mkConst ``exists_congr_eq [u]) α lp lq hx)
    else
      let ap ← Meta.mkForallFVars #[x] p
      let aq ← Meta.mkForallFVars #[x] q
      return (ap, aq, mkApp4 (mkConst ``forall_congr [u]) α lp lq hx)
  ys.foldrM f (p, q, h)

/-- The variables the conclusion's quantifier binds, as the anchor's fvars in binder order. The
    anchor may declare more than those: when `bind` renames a variable, veriT lists both the old
    and the new one, and only the new one is bound by the quantifier the step concludes. -/
def bindVars (a : AnchorCtx) (quant : cvc5.Term) : ReconstructM (Array Expr) := do
  let mut ys := #[]
  for i in [0:quant[0]!.getNumChildren] do
    let name := quant[0]![i]!.getSymbol!
    -- (a kept variable the block also substitutes — veriT's chained renaming — is still bound
    -- by the conclusion's right-hand quantifier under its own name: the substitution applies to
    -- the left-hand side of the judgment only, and the close keeps the binder on the right)
    let some v := a.vars.find? (fun (m, _, _) => m == name)
      | throwError "bind: the anchor does not declare {name}, bound by {quant}"
    ys := ys.push v.2.2
  return ys

/-- Generalized `bind`: the subproof over the anchor's variables `xs` concludes a clause
    `(cl ls ψ)` whose literals `ls` do not mention `xs`; the closing step is `(cl ls (∀ xs, ψ))`. -/
def reconstructBindClause (s : Step) : ReconstructM Expr := do
  let some a := s.anchor | throwError "bind outside of an anchor"
  let some last := a.last | throwError "bind: empty subproof"
  let n := s.lits.size
  if last.lits.size != n then throwError "bind: the subproof's clause has {last.lits.size} literals, expected {n}"
  -- the literal the step closes as a quantifier: the others pass through untouched, and it need
  -- not be the last one (the core pass emits it wherever the subproof's clause has its body)
  let some k := (List.range n).find? (fun i => s.lits[i]!.getKind! == .FORALL && s.lits[i]! != last.lits[i]!)
    | throwError "bind: no quantified literal to close in {s.lits}"
  let quant := s.lits[k]!
  let others := last.lits.eraseIdx! k
  let ps ← mkPropList others
  -- the subproof's proof with the anchor's variables abstracted, innermost first, and its clause
  -- reordered so that the literal to close is last
  let mut h := zetaAssigns a (← instantiateMVars last.proof)
  let tgt := others.push last.lits[k]!
  if tgt != last.lits then
    let some h' ← reindexClause last.lits h tgt
      | throwError "bind: cannot move the quantified literal of {last.lits} to the end"
    h := h'
  let mut body ← reconstructTerm last.lits[k]!
  for fv in (← bindVars a quant).reverse do
    let hy ← Meta.mkLambdaFVars #[fv] h        -- ∀ y, orN (ps ++ [ψ y])
    let psi ← Meta.mkLambdaFVars #[fv] body     -- fun y => ψ y
    let u ← Meta.getLevel (← Meta.inferType fv)
    h := mkApp4 (mkConst ``orN_forall [u]) (← Meta.inferType fv) ps psi hy
    body ← Meta.mkForallFVars #[fv] body
  -- `orN (ps ++ [∀ xs, ψ])` is the stated clause up to the list structure
  let cc := others.push quant
  concludeClause s cc h

/-- `bind`: from the subproof's `φ = ψ` conclude `(∀ xs, φ) = (∀ ys, ψ)`. -/
def reconstructBind (s : Step) : ReconstructM Expr := do
  if !(s.lits.size == 1 && s.lits[0]!.getKind! == .EQUAL) then
    return ← reconstructBindClause s
  let some a := s.anchor | throwError "bind outside of an anchor"
  let some last := a.last | throwError "bind: empty subproof"
  let k := s.lits[0]![0]!.getKind!
  if k != .FORALL && k != .EXISTS then throwError "bind: unsupported binder {k}"
  -- A `bind` whose two sides are the same formula up to the names of bound variables is closed
  -- by reflexivity: `Expr` equality is α-equivalence, and so is the kernel's. This is every
  -- `bind` veriT writes with identity substitutions, and every pure renaming, and it is cheaper
  -- than a `forall_congr` chain. It also sidesteps the subproof, which for a chained renaming
  -- (`((y S) (z S) (:= x y) (:= y z))`) derives the equality by `symm`/`cong` steps that only
  -- hold name-syntactically — Carcara checks them as such — and have no single consistent
  -- reading as terms of the block.
  if let some (_, le, re) := s.concl.eq? then
    if le == re then
      return ← Meta.mkExpectedTypeHint (← Meta.mkEqRefl le) s.concl
  let ys ← bindVars a s.lits[0]![1]!
  let h ← instantiateMVars last.proof
  -- the recorded conclusion, not the proof term's type (a clause lemma may state it as an `orN`)
  let ty ← Meta.whnfR last.concl
  let some (_, p, q) := ty.eq? | throwError "bind: the subproof does not prove an equality"
  -- The judgment is `Γ ▷ p ≃ q` with the substitution applying to `p` only: zeta-reduce the
  -- block's lets in `p` and in the proof, but a kept variable the block also substitutes (veriT's
  -- chained renaming) stays itself in `q`, where the conclusion's right-hand quantifier binds it.
  -- Since the let of such a variable *is* that variable's node, zeta must leave `q` alone.
  let p := zetaAssigns a p
  let h := zetaAssigns a h
  -- in `q` the let that shadows such a kept variable stands for the variable itself: put the
  -- binder back where the let is
  let q := a.assigns.foldl (init := q) fun q (_, c, fv, _, _) =>
    match a.vars.find? (fun (_, c', _) => c' == c) with
    | some (_, _, kv) => q.replaceFVar fv kv
    | none => q
  let (_, _, h) ← congrBinders (k == .EXISTS) ys p q h
  return h

/-- `sko_ex` / `sko_forall`: from the subproof's `φ = ψ` under `x₁ := ε₁, …, xₙ := εₙ` conclude
    `(∃ xs, φ) = ψ` (resp. `(∀ xs, φ) = ψ`). The skolems are sequential: `εᵢ` is the choice for
    `xᵢ` in the quantifier over `xᵢ … xₙ` with the earlier variables already replaced. -/
def reconstructSko (s : Step) (exists_ : Bool) : ReconstructM Expr := do
  let some a := s.anchor | throwError "sko: outside of an anchor"
  let some last := a.last | throwError "sko: empty subproof"
  if a.assigns.isEmpty then throwError "sko: no assignment"
  let quant := s.lits[0]![0]!
  let mut cur ← reconstructTerm quant  -- ∀ x₁ … xₙ, φ  or  ∃ x₁ … xₙ, φ
  let mut h : Option Expr := none
  for (_, _, _, _, eps) in a.assigns do
    let (pred, body) ← match exists_, cur with
      | false, .forallE n t b bi => pure (Expr.lam n t b bi, b)
      | true, e => do
        let some (_, f) := e.app2? ``Exists | throwError "sko: unexpected quantified term {e}"
        let .lam _ _ b _ := f | throwError "sko: unexpected predicate {f}"
        pure (f, b)
      | _, e => throwError "sko: unexpected quantified term {e}"
    let α ← Meta.inferType (← Meta.mkFreshExprMVar none) |> fun _ => do
      let .lam _ t _ _ := pred | throwError "sko: unexpected predicate"
      pure t
    let u ← Meta.getLevel α
    let inst ← Meta.synthInstance (mkApp (mkConst ``Nonempty [u]) α)
    let hi := mkApp3 (mkConst (if exists_ then ``sko_ex_eq else ``sko_forall_eq) [u]) α inst pred
    h := some (← match h with
      | none => pure hi
      | some h₀ => Meta.mkEqTrans h₀ hi)
    cur := body.instantiate1 eps
  let some h₁ := h | throwError "sko: no assignment"
  -- the subproof, with the variables replaced by the epsilon terms
  let h₂ := zetaAssigns a (← instantiateMVars last.proof)
  Meta.mkEqTrans h₁ h₂

/-! `onepoint`: `(∀ x, φ) = ψ` where `φ` contains the guard `¬(x = t)` (or `x = t → …`), resp.
    `(∃ x, φ) = ψ` where `φ` contains the conjunct `x = t`, with the subproof proving `φ[t] = ψ`
    under `x := t`. -/
/-- Whether `e` is the guard equation `x = t` or `t = x`. -/
def isGuardEq (x t e : Expr) : Bool :=
  match e.eq? with
  | some (_, l, r) => (l == x && r == t) || (l == t && r == x)
  | none => false

/-- A proof of the guard `x = t` from `h : e`, when `e` is the guard (either orientation) or a
    conjunction containing it. -/
partial def guardOf (x t : Expr) (h e : Expr) : MetaM (Option Expr) := do
  if isGuardEq x t e then
    let some (_, l, _) := e.eq? | return none
    let hg ← if l == x then pure h else Meta.mkEqSymm h
    return some hg
  if let some (a, b) := e.and? then
    if let some g ← guardOf x t (← Meta.mkAppM ``And.left #[h]) a then return some g
    if let some g ← guardOf x t (← Meta.mkAppM ``And.right #[h]) b then return some g
  -- `∃ z, b` forces the guard whenever `b` does and `z` is not one of its variables (Carcara's
  -- `extract_points` descends through binders in the same way)
  if let some (α, p) := e.app2? ``Exists then
    let name := match p with | .lam n _ _ _ => n | _ => `z
    return ← Meta.withLocalDeclD name α fun z => do
      let b ← Meta.whnfR (mkApp p z)
      Meta.withLocalDeclD `hz b fun hz => do
        let some g ← guardOf x t hz b | return none
        if g.containsFVar z.fvarId! then return none
        return some (← Meta.mkAppM ``Exists.elim #[h, ← Meta.mkLambdaFVars #[z, hz] g])
  return none

/-- Prove `e` from `hnx : x ≠ t`, where `e` contains the guard `x = t` (in either orientation) as
    a premise of an implication, negated, or inside `∨`/`∧`, possibly under other binders. -/
partial def refuteGuard (x t hnx : Expr) (e : Expr) : MetaM Expr := do
  let hasGuard (e : Expr) : Bool := (e.find? (isGuardEq x t)).isSome
  match e with
  | .forallE n d b bi =>
    if isGuardEq x t d then
      Meta.withLocalDecl n bi d fun hd => do
        let some hg ← guardOf x t hd d | throwError "onepoint: malformed guard"
        Meta.mkLambdaFVars #[hd] (← Meta.mkAbsurd (b.instantiate1 hd) hg hnx)
    else
      Meta.withLocalDecl n bi d fun v => do
        -- a premise may also carry the guard inside a conjunction
        if let some hg ← guardOf x t v d then
          Meta.mkLambdaFVars #[v] (← Meta.mkAbsurd (b.instantiate1 v) hg hnx)
        else
          Meta.mkLambdaFVars #[v] (← refuteGuard x t hnx (b.instantiate1 v))
  | _ =>
    if let some p := e.not? then
      -- ¬p: from h : p, derive the guard and contradict
      return ← Meta.withLocalDeclD `hp p fun hp => do
        let some hg ← guardOf x t hp p | throwError "onepoint: no guard under the negation {e}"
        Meta.mkLambdaFVars #[hp] (mkApp hnx hg)
    if let some (a, b) := e.app2? ``Or then
      -- (`mkAppM` cannot infer the other disjunct)
      if hasGuard a then return mkApp3 (mkConst ``Or.inl) a b (← refuteGuard x t hnx a)
      if hasGuard b then return mkApp3 (mkConst ``Or.inr) a b (← refuteGuard x t hnx b)
      throwError "onepoint: no guard in {e}"
    if let some (a, b) := e.and? then
      return ← Meta.mkAppM ``And.intro #[← refuteGuard x t hnx a, ← refuteGuard x t hnx b]
    throwError "onepoint: no guard in {e}"

/-- Peel `n` nested `Exists` binders off `e`, running `k` on the bound variables and the body. -/
partial def existsTelescope (e : Expr) (n : Nat) (k : Array Expr → Expr → MetaM α) : MetaM α :=
  go e n #[]
where
  go (e : Expr) (n : Nat) (xs : Array Expr) : MetaM α := do
    if n == 0 then return ← k xs e
    let some (α, p) := e.app2? ``Exists | throwError "expected {n} more existential binders in {e}"
    let name := match p with | .lam m _ _ _ => m | _ => `x
    Meta.withLocalDeclD name α fun x => do go (← Meta.whnfR (mkApp p x)) (n - 1) (xs.push x)

/-- `h : ∃ x̄, φ` and `elim : ∀ x̄, φ → g` give `g`, by nested `Exists.elim`. -/
partial def existsElimN (h e : Expr) (n : Nat) (elim : Expr) : MetaM Expr :=
  go h e n #[]
where
  go (h e : Expr) (n : Nat) (xs : Array Expr) : MetaM Expr := do
    if n == 0 then return mkAppN elim (xs.push h)
    let some (α, p) := e.app2? ``Exists | throwError "expected {n} more existential binders in {e}"
    let name := match p with | .lam m _ _ _ => m | _ => `x
    let lam ← Meta.withLocalDeclD name α fun x => do
      let b ← Meta.whnfR (mkApp p x)
      Meta.withLocalDeclD `hx b fun hx => do
        Meta.mkLambdaFVars #[x, hx] (← go hx b (n - 1) (xs.push x))
    Meta.mkAppM ``Exists.elim #[h, lam]

/-- `⟨w₁, …, wₙ, h⟩ : ∃ x̄, φ` from `h : φ[w̄]`. -/
partial def existsIntroN (target : Expr) (ws : Array Expr) (h : Expr) : MetaM Expr :=
  go target 0
where
  go (target : Expr) (i : Nat) : MetaM Expr := do
    if i == ws.size then return h
    let some (_, p) := target.app2? ``Exists | throwError "expected an existential, got {target}"
    let inner ← go (← Meta.whnfR (mkApp p ws[i]!)) (i + 1)
    Meta.mkAppOptM ``Exists.intro #[none, some p, some ws[i]!, some inner]

/-- `φ = φ[x̄ := t̄]` from `hs : xᵢ = tᵢ`, by congruence on the abstraction of the positions the
    points occupy. -/
def onepointCongr (body : Expr) (xs hs : Array Expr) : MetaM Expr := do
  let lam ← Meta.mkLambdaFVars xs body
  let mut h ← Meta.mkCongrArg lam hs[0]!
  for i in [1:hs.size] do
    h ← Meta.mkCongr h hs[i]!
  return h

/-- The binder index of each assigned variable. `onepoint`'s left binders are the anchor's kept
    variables and its points together, and its right binders are the kept ones in order. -/
def onepointIndices (a : AnchorCtx) (quant : cvc5.Term) : ReconstructM (Array Nat) := do
  let n := quant[0]!.getNumChildren
  if a.vars.size + a.assigns.size != n then
    throwError "onepoint: the anchor declares {a.vars.size} variables and {a.assigns.size} \
      points, the quantifier binds {n}"
  let mut idx := #[]
  for (xname, _, _, _, _) in a.assigns do
    let some k := (List.range n).find? (fun i => quant[0]![i]!.getSymbol! == xname)
      | throwError "onepoint: the assigned variable {xname} is not bound by {quant}"
    idx := idx.push k
  return idx

/-- The arguments the left quantifier takes when the points are supplied: `ts[p]` at the position
    of the `p`th point, the kept values in order elsewhere. -/
def onepointArgs (n : Nat) (idx : Array Nat) (kept ts : Array Expr) : Array Expr := Id.run do
  let mut args := #[]
  let mut j := 0
  for i in [0:n] do
    match idx.findIdx? (· == i) with
    | some p => args := args.push ts[p]!
    | none   => args := args.push kept[j]!; j := j + 1
  return args

/-- `onepoint` on a universal quantifier: `(∀ x̄ ȳ, φ) = (∀ ȳ, ψ)` where the anchor assigns the
    points `x̄ := t̄` (a `t` may mention the kept binders) and keeps `ȳ`, the subproof proves
    `φ[t̄/x̄] = ψ` under it, and `φ` is trivially true when a guard `xᵢ = tᵢ` fails. -/
def reconstructOnepointForall (s : Step) (a : AnchorCtx) (last : Premise) : ReconstructM Expr := do
  let quant := s.lits[0]![0]!
  let n := quant[0]!.getNumChildren
  let idx ← onepointIndices a quant
  let m := idx.size
  let kept := a.vars.map (·.2.2)
  let ts := a.assigns.map fun (_, _, _, _, te) => zetaAssigns a te
  let heq := zetaAssigns a (← instantiateMVars last.proof)
  let ty ← Meta.whnfR (zetaAssigns a last.concl)
  let some (_, _, _) := ty.eq? | throwError "onepoint: the subproof does not prove an equality"
  let l ← reconstructTerm quant
  let r ← reconstructTerm s.lits[0]![1]!
  -- (→): instantiate the quantifier at the anchor's variables and the points
  let mp ← Meta.withLocalDeclD `h l fun h => do
    let body := mkAppN h (onepointArgs n idx kept ts)
    Meta.mkLambdaFVars (#[h] ++ kept) (← Meta.mkAppM ``Eq.mp #[heq, body])
  -- (←): for arbitrary binders, either every guard holds and the subproof applies, or one of
  -- them fails and the body is vacuously true
  let mpr ← Meta.withLocalDeclD `h r fun h => do
    Meta.forallBoundedTelescope l n fun xs body => do
      let os := (List.range n).toArray.filterMap fun i => if idx.contains i then none else some xs[i]!
      let subst (e : Expr) := e.replaceFVars kept os
      let ts' := ts.map subst
      let xps := idx.map (xs[·]!)
      let rec go (i : Nat) (hs : Array Expr) : MetaM Expr := do
        if i ≥ m then
          let hphi ← Meta.mkAppM ``Eq.mpr #[subst heq, mkAppN h os]
          Meta.mkAppM ``Eq.mpr #[← onepointCongr body xps hs, hphi]
        else
          let eq ← Meta.mkEq xps[i]! ts'[i]!
          let onEq ← Meta.withLocalDeclD `hx eq fun hx => do
            Meta.mkLambdaFVars #[hx] (← go (i + 1) (hs.push hx))
          let onNe ← Meta.withLocalDeclD `hnx (← Meta.mkAppM ``Ne #[xps[i]!, ts'[i]!]) fun hnx => do
            Meta.mkLambdaFVars #[hnx] (← refuteGuard xps[i]! ts'[i]! hnx body)
          Meta.mkAppM ``Or.elim #[← Meta.mkAppM ``Classical.em #[eq], onEq, onNe]
      Meta.mkLambdaFVars (#[h] ++ xs) (← go 0 #[])
  Meta.mkAppM ``propext #[← Meta.mkAppM ``Iff.intro #[mp, mpr]]

/-- `onepoint` on an existential: `(∃ x̄ ȳ, φ) = (∃ ȳ, ψ)` where the anchor assigns the points
    `x̄ := t̄` and keeps `ȳ`, the subproof proves `φ[t̄/x̄] = ψ` under it, and every guard
    `xᵢ = tᵢ` follows from `φ`. -/
def reconstructOnepointExists (s : Step) (a : AnchorCtx) (last : Premise) : ReconstructM Expr := do
  let quant := s.lits[0]![0]!
  let n := quant[0]!.getNumChildren
  let idx ← onepointIndices a quant
  let m := idx.size
  let kept := a.vars.map (·.2.2)
  let ts := a.assigns.map fun (_, _, _, _, te) => zetaAssigns a te
  let heq := zetaAssigns a (← instantiateMVars last.proof)
  let l ← reconstructTerm quant
  let r ← reconstructTerm s.lits[0]![1]!
  -- (→): take a witness, read the guards off the body, rewrite it and repack over the kept ones
  let mp ← Meta.withLocalDeclD `h l fun h => do
    let elim ← existsTelescope l n fun xs body =>
      Meta.withLocalDeclD `hb body fun hb => do
        let os := (List.range n).toArray.filterMap fun i => if idx.contains i then none else some xs[i]!
        let subst (e : Expr) := e.replaceFVars kept os
        let ts' := ts.map subst
        let xps := idx.map (xs[·]!)
        let mut hs := #[]
        for i in [0:m] do
          let some g ← guardOf xps[i]! ts'[i]! hb body
            | throwError "onepoint: no guard for {xps[i]!} = {ts'[i]!} in {body}"
          hs := hs.push g
        let hphi ← Meta.mkAppM ``Eq.mp #[← onepointCongr body xps hs, hb]
        let hpsi ← Meta.mkAppM ``Eq.mp #[subst heq, hphi]
        Meta.mkLambdaFVars (xs.push hb) (← existsIntroN r os hpsi)
    Meta.mkLambdaFVars #[h] (← existsElimN h l n elim)
  -- (←): supply the points as witnesses
  let mpr ← Meta.withLocalDeclD `h r fun h => do
    let elim ← existsTelescope r kept.size fun ys psi =>
      Meta.withLocalDeclD `hp psi fun hp => do
        let subst (e : Expr) := e.replaceFVars kept ys
        let hphi ← Meta.mkAppM ``Eq.mpr #[subst heq, hp]
        Meta.mkLambdaFVars (ys.push hp) (← existsIntroN l (onepointArgs n idx ys (ts.map subst)) hphi)
    Meta.mkLambdaFVars #[h] (← existsElimN h r kept.size elim)
  Meta.mkAppM ``propext #[← Meta.mkAppM ``Iff.intro #[mp, mpr]]

/-- `qnt_simplify`: `(Q x̄, c) = c` for a Boolean constant `c`. The binders are peeled one at a
    time; the two directions that need a witness — `(∀ x, False)` and `(∃ x, True)` — take it from
    the sort's `Nonempty` instance, which the problem's sorts carry. -/
partial def qntSimplifyProof (e : Expr) : ReconstructM Expr := do
  if e.isConstOf ``True || e.isConstOf ``False then return ← Meta.mkEqRefl e
  let (α, body, isForall) ← match e with
    | .forallE _ α b _ =>
      if b.hasLooseBVars then throwError "qnt_simplify: the body mentions the bound variable"
      pure (α, b, true)
    | _ => match e.app2? ``Exists with
      | some (α, .lam _ _ b _) =>
        if b.hasLooseBVars then throwError "qnt_simplify: the body mentions the bound variable"
        pure (α, b, false)
      | _ => throwError "qnt_simplify: not a quantifier over a constant: {e}"
  let hb ← qntSimplifyProof body                                  -- body = c
  let some (_, _, c) := (← Meta.inferType hb).eq?
    | throwError "qnt_simplify: malformed inner proof"
  let u ← Meta.getLevel α
  -- `Q x : α, body = Q x : α, c`, the binder being vacuous
  let motive ← Meta.withLocalDeclD `p (mkSort .zero) fun p => do
    let q ← if isForall then pure (Expr.forallE `x α p .default)
            else Meta.mkAppOptM ``Exists #[α, Expr.lam `x α p .default]
    Meta.mkLambdaFVars #[p] q
  let hcong ← Meta.mkCongrArg motive hb
  -- `Q x : α, c = c`
  let name : Name := match isForall, c.isConstOf ``True with
    | true,  true  => ``qnt_forall_true
    | true,  false => ``qnt_forall_false
    | false, true  => ``qnt_exists_true
    | false, false => ``qnt_exists_false
  let lemma ← if name == ``qnt_forall_true || name == ``qnt_exists_false then
      pure (mkApp (mkConst name [u]) α)
    else do
      let inst ← Meta.synthInstance (mkApp (mkConst ``Nonempty [u]) α)
      pure (mkApp2 (mkConst name [u]) α inst)
  Meta.mkEqTrans hcong lemma

def reconstructOnepoint (s : Step) : ReconstructM Expr := do
  let some a := s.anchor | throwError "onepoint: outside of an anchor"
  let some last := a.last | throwError "onepoint: empty subproof"
  if s.lits[0]![0]!.getKind! == .FORALL then return ← reconstructOnepointForall s a last
  if a.assigns.size != 1 || a.vars.size != 0 then
    return ← reconstructOnepointExists s a last
  let (_, _, fv, _, te) := a.assigns[0]!
  let quant := s.lits[0]![0]!
  let k := quant.getKind!
  let (u, (α : Q(Sort u))) ← reconstructSortLevelAndSort quant[0]![0]!.getSort!
  let lam ← reconstructTerm quant
  let pred : Expr ← match k, lam with
    | .FORALL, .forallE n t b bi => pure (.lam n t b bi)
    | .EXISTS, e => do
      let some (_, f) := e.app2? ``Exists | throwError "onepoint: unexpected quantified term"
      pure f
    | _, _ => throwError "onepoint: unsupported binder {k}"
  -- heq : p t = q, from the subproof (x is let-bound to t)
  let heq ← instantiateMVars last.proof
  let heq := heq.replaceFVar fv te
  let ty ← Meta.whnfR (last.concl.replaceFVar fv te)
  let some (_, _, q) := ty.eq? | throwError "onepoint: the subproof does not prove an equality"
  -- h : ∀ x, x ≠ t → p x   (resp. ∀ x, p x → x = t), from the guard literal
  let h ← Meta.withLocalDeclD `x α fun x => do
    let body ← Meta.whnfR (mkApp pred x)  -- β-reduced body with `x`
    let isGuard (l : Expr) : Bool :=
      match l.eq? with
      | some (_, l₁, l₂) => (l₁ == x && l₂ == te) || (l₁ == te && l₂ == x)
      | none => false
    if k == .FORALL then
      let hxt := mkApp (mkConst ``Ne [u]) α |>.app x |>.app te  -- x ≠ t
      Meta.withLocalDeclD `hx hxt fun hnx => do
        let lits ← collectPropsInOrChain body
        let proof ← match body with
          | .forallE _ d b _ =>  -- x = t → B: under x ≠ t the guard is refuted, giving B
            if !isGuard d then throwError "onepoint: no guard in {body}"
            if b.hasLooseBVars then throwError "onepoint: dependent guard in {body}"
            let hd ← Meta.withLocalDeclD `hd d fun hd => do
              let hxt' := match d.eq? with
                | some (_, l₁, _) => if l₁ == x then hd else mkApp4 (mkConst ``Eq.symm [u]) α te x hd
                | none => hd
              Meta.mkLambdaFVars #[hd] (← Meta.mkAbsurd b hxt' hnx)
            pure hd
          | _ =>
            let some i := lits.findIdx? (fun l => l.isAppOfArity ``Not 1 && isGuard l.appArg!)
              | throwError "onepoint: no guard literal in {body}"
            let guard := lits[i]!
            -- guard = ¬(x = t) or ¬(t = x)
            let hguard ← match guard.appArg!.eq? with
              | some (_, l₁, _) =>
                if l₁ == x then pure hnx
                else Meta.withLocalDeclD `h guard.appArg! fun h =>
                  Meta.mkLambdaFVars #[h] (mkApp hnx (mkApp4 (mkConst ``Eq.symm [u]) α te x h))
              | none => throwError "onepoint: malformed guard"
            let qs := listExpr lits (mkSort .zero)
            let hi ← Meta.mkDecideProof (← Meta.mkAppM ``LT.lt #[toExpr i, ← Meta.mkAppM ``List.length #[qs]])
            pure (mkApp4 (mkConst ``orN_of_getElem) qs (toExpr i) hi hguard)
        Meta.mkLambdaFVars #[x, hnx] proof
    else
      Meta.withLocalDeclD `hp body fun hp => do
        let conj ← collectPropsInAndChain body
        let some i := conj.findIdx? isGuard | throwError "onepoint: no guard conjunct in {body}"
        let ps := listExpr conj (mkSort .zero)
        let hi ← Meta.mkDecideProof (← Meta.mkAppM ``LT.lt #[toExpr i, ← Meta.mkAppM ``List.length #[ps]])
        let hc := mkApp4 (mkConst ``Prop.and_elim) ps hp (toExpr i) hi  -- : ps[i]
        let hxt := match conj[i]!.eq? with
          | some (_, l₁, _) => if l₁ == x then hc else mkApp4 (mkConst ``Eq.symm [u]) α te x hc
          | none => hc
        Meta.mkLambdaFVars #[x, hp] hxt
  let lemma := if k == .FORALL then ``onepoint_forall else ``onepoint_exists
  return mkAppN (mkConst lemma [u]) #[α, te, pred, q, h, heq]

/-- `let`: the anchor binds `xᵢ := tᵢ`, the premises prove `sᵢ = tᵢ` for the bindings of the
    `let` on the left (already expanded by the parser to `u[s/x]`), and the subproof proves
    `u = v` under the bindings; conclude `u[s/x] = v`. -/
def reconstructLet (s : Step) : ReconstructM Expr := do
  let some a := s.anchor | throwError "let: outside of an anchor"
  let some last := a.last | throwError "let: empty subproof"
  let h ← instantiateMVars last.proof
  let ty ← Meta.whnfR last.concl
  let some (_, u, _) := ty.eq? | throwError "let: the subproof does not prove an equality"
  -- `u[s/x] = u[t/x]` from the premises, one binding at a time (outermost first)
  let mut lhs := u        -- with the let-bound fvars
  let mut hcong : Option Expr := none
  for (_, _, fv, tTerm, te) in a.assigns do
    -- the premise for this binding: `s = t` (or `t = s`); `s` is what the conclusion's `let` bound
    let (_, hst) ← match s.premises.find? (fun p => p.lits.size == 1 && p.lits[0]!.getKind! == .EQUAL
        && (p.lits[0]![1]! == tTerm || p.lits[0]![0]! == tTerm)) with
      | some p =>
        let (l, r) := (p.lits[0]![0]!, p.lits[0]![1]!)
        if r == tTerm then pure (← reconstructTerm l, p.proof)
        else pure (← reconstructTerm r, ← Meta.mkEqSymm p.proof)
      | none => pure (te, ← Meta.mkEqRefl te)  -- `s` is `t` itself
    -- a genuine lambda over the let-bound variable (`mkLambdaFVars` would keep it a `let`)
    let some decl := (← getLCtx).find? fv.fvarId! | throwError "let: unknown variable"
    let fn := Expr.lam decl.userName decl.type (lhs.abstract #[fv]) .default
    let step ← Meta.mkCongrArg fn hst  -- (fun x => u) s = (fun x => u) t
    hcong := some (← match hcong with
      | none => pure step
      | some h₀ => Meta.mkEqTrans h₀ step)
    lhs := lhs.replaceFVar fv te
  let h := zetaAssigns a h
  match hcong with
  | some hc => Meta.mkEqTrans hc h
  | none => pure h

/-- `qnt_rm_unused` over an existential: `(∃ xs, φ) = (∃ ys, φ)` (or `= φ` when every binder is
    dropped), with `ys ⊆ xs` and `φ` not mentioning the dropped binders. The shared
    `QUANT_UNUSED_VARS` reconstruction is universal-only — it instantiates each side by *applying*
    the quantified proposition, which is a function only for `∀` — so the existential case is
    proved here by `Exists.elim`/`Exists.intro`, filling a dropped binder with an arbitrary
    inhabitant in the `←` direction. -/
def reconstructQntRmUnusedExists (s : Step) (lhs rhs : cvc5.Term) : ReconstructM Expr := do
  let l : Q(Prop) ← reconstructTerm lhs
  let r : Q(Prop) ← reconstructTerm rhs
  let xs := lhs[0]!.getChildren
  -- when a kept binder remains the result is an `∃`; when all are dropped it is the body itself
  let ys := if rhs.getKind! == .EXISTS then rhs[0]!.getChildren else #[]
  -- the innermost binder of `v` in `xs`: the one the body's occurrences refer to (a prefix may
  -- reuse a variable node for a repeated name)
  let innermost (v : cvc5.Term) : Option Nat := (List.range xs.size).reverse.find? (xs[·]! == v)
  let arbitrary (v : cvc5.Term) : ReconstructM Expr := do
    let (u, α) ← reconstructSortLevelAndSort v.getSort!
    let hα ← Meta.synthInstance (mkApp (mkConst ``Nonempty [u]) α)
    return mkApp2 (mkConst ``Classical.choice [u]) α hα
  -- (→): peel the `xs` witnesses, keep the `ys` ones
  let mp : Q($l → $r) ← Meta.withLocalDeclD `h l fun h => do
    let elim ← existsTelescope l xs.size fun xfs _ => do
      let body ← Meta.whnfR (← instExistsBody l xfs)
      Meta.withLocalDeclD `hb body fun hb => do
        let ws := ys.map fun y => xfs[(innermost y).getD 0]!
        Meta.mkLambdaFVars (xfs.push hb) (← existsIntroN r ws hb)
    Meta.mkLambdaFVars #[h] (← existsElimN h l xs.size elim)
  -- (←): peel the `ys` witnesses, fill the dropped binders with arbitrary inhabitants. The plan
  -- for each `xs` position — a `ys` index to keep, or a precomputed inhabitant to drop in — is
  -- built here, in `ReconstructM`, since `existsTelescope`'s callback runs in `MetaM` and cannot
  -- reconstruct a sort
  let plan : Array (Sum Nat Expr) ← xs.mapM fun x => match ys.findIdx? (· == x) with
    | some k => pure (Sum.inl k)
    | none => Sum.inr <$> arbitrary x
  let mpr : Q($r → $l) ← Meta.withLocalDeclD `h r fun h => do
    let elim ← existsTelescope r ys.size fun yfs _ => do
      let body ← Meta.whnfR (← instExistsBody r yfs)
      Meta.withLocalDeclD `hb body fun hb => do
        let ws := plan.map fun | Sum.inl k => yfs[k]! | Sum.inr e => e
        Meta.mkLambdaFVars (yfs.push hb) (← existsIntroN l ws hb)
    Meta.mkLambdaFVars #[h] (← existsElimN h r ys.size elim)
  addThm q($l = $r) q(propext (Iff.intro $mp $mpr))
where
  /-- The body of a nested `∃`/plain prop after supplying witnesses `ws` for its binders. -/
  instExistsBody (e : Expr) (ws : Array Expr) : MetaM Expr := do
    let mut cur := e
    for w in ws do
      let some (_, p) := cur.app2? ``Exists | throwError "qnt_rm_unused: expected an existential"
      cur ← Meta.whnfR (mkApp p w)
    return cur

/-- The quantifier rewrites of `Smt.Reconstruct.Quant`, driven by the result term only. -/
def rewriteRule (rule : String) : Option cvc5.ProofRewriteRule :=
  match rule with
  | "qnt_rm_unused" => some .QUANT_UNUSED_VARS
  | "qnt_join" => some .QUANT_MERGE_PRENEX
  | "miniscope_distribute" => some .QUANT_MINISCOPE_AND
  | "miniscope_split" => some .QUANT_MINISCOPE_OR
  | "miniscope_ite" => some .QUANT_MINISCOPE_ITE
  | _ => none

@[alethe_rule_reconstruct] def reconstructQuant : RuleReconstructor := fun s => do
  match s.rule with
  | "qnt_simplify" =>
    let t := s.lits[0]!
    if t.getKind! != .EQUAL then throwError "qnt_simplify: expected an equality"
    addThm s.concl (← qntSimplifyProof (← reconstructTerm t[0]!))
  | "forall_inst" =>
    -- (cl (or (not (forall xs φ)) φ[ts])) with :args ((:= x t) …)
    let t := s.lits[0]!
    if t.getKind! != .OR || t[0]!.getKind! != .NOT || t[0]![0]!.getKind! != .FORALL then
      throwError "forall_inst: unexpected conclusion"
    let q := t[0]![0]!
    let mut inst : Std.HashMap String cvc5.Term := {}
    let mut pos := #[]
    for a in s.args do
      match a with
      | .assign x _ v => inst := inst.insert x v
      | .term v => pos := pos.push v
      | _ => pure ()
    let mut es := #[]
    for i in [0:q[0]!.getNumChildren] do
      let x := q[0]![i]!
      let v ← match inst[x.getSymbol!]? with
        | some v => pure v
        | none => match pos[i]? with
          | some v => pure v
          | none => throwError "forall_inst: no instance for {x}"
      es := es.push (← reconstructTerm v)
    let hq ← reconstructTerm q
    let hf ← Meta.withLocalDeclD `h hq fun h => Meta.mkLambdaFVars #[h] (mkAppN h es)
    let mut pr ← Meta.mkAppM ``Prop.impliesElim #[hf]
    -- the instantiated body carries the instances of the quantified body, the stated conclusion
    -- those synthesis finds for the instance itself
    let ty ← Meta.inferType pr
    unless ← Meta.isDefEq ty s.concl do
      let some heq ← alignInstances ty s.concl
        | throwError "forall_inst: the instance differs from the stated conclusion:{indentExpr ty}\n≠{indentExpr s.concl}"
      pr ← Meta.mkAppM ``Eq.mp #[heq, pr]
    addThm s.concl pr
  | "bind" => addThm s.concl (← reconstructBind s)
  | "onepoint" => addThm s.concl (← reconstructOnepoint s)
  | "let" => addThm s.concl (← reconstructLet s)
  | "sko_ex" => addThm s.concl (← reconstructSko s true)
  | "sko_forall" => addThm s.concl (← reconstructSko s false)
  | "qnt_rm_unused" | "qnt_join" | "miniscope_distribute" | "miniscope_split" | "miniscope_ite" =>
    -- the shared `QUANT_UNUSED_VARS` reconstruction handles `∀` only; `∃` is proved here
    if s.rule == "qnt_rm_unused" && s.lits[0]!.getKind! == .EQUAL
        && s.lits[0]![0]!.getKind! == .EXISTS then
      return ← addThm s.concl (← reconstructQntRmUnusedExists s s.lits[0]![0]! s.lits[0]![1]!)
    let some rule := rewriteRule s.rule | return none
    let result := s.lits[0]!
    let rw : RewriteStep := { rule, args := #[result], result, premises := #[] }
    match ← Quant.reconstructRewrite rw with
    | some e => addThm s.concl e
    | none => return none
  | _ => return none

end Smt.Alethe
