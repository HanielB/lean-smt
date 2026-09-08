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
  ctx.assigns.foldr (fun (_, _, fv, _, te) e => e.replaceFVar fv te) e

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

/-- Generalized `bind`: the subproof over the anchor's variables `xs` concludes a clause
    `(cl ls ψ)` whose literals `ls` do not mention `xs`; the closing step is `(cl ls (∀ xs, ψ))`. -/
def reconstructBindClause (s : Step) : ReconstructM Expr := do
  let some a := s.anchor | throwError "bind outside of an anchor"
  let some last := a.last | throwError "bind: empty subproof"
  let n := s.lits.size
  let quant := s.lits[n-1]!
  if quant.getKind! != .FORALL then throwError "bind: expected a universal quantifier last"
  if last.lits.size != n then throwError "bind: the subproof's clause has {last.lits.size} literals, expected {n}"
  let ps ← mkPropList (last.lits.extract 0 (n-1))
  -- the subproof's proof with the anchor's variables abstracted, innermost first
  let mut h := zetaAssigns a (← instantiateMVars last.proof)
  let mut body ← reconstructTerm last.lits[n-1]!
  for y in a.vars.reverse do
    let fv := y.2.2
    let hy ← Meta.mkLambdaFVars #[fv] h        -- ∀ y, orN (ps ++ [ψ y])
    let psi ← Meta.mkLambdaFVars #[fv] body     -- fun y => ψ y
    let u ← Meta.getLevel (← Meta.inferType fv)
    h := mkApp4 (mkConst ``orN_forall [u]) (← Meta.inferType fv) ps psi hy
    body ← Meta.mkForallFVars #[fv] body
  -- `orN (ps ++ [∀ xs, ψ])` is the stated clause up to the list structure
  let cc := (last.lits.extract 0 (n-1)).push quant
  concludeClause s cc h

/-- `bind`: from the subproof's `φ = ψ` conclude `(∀ xs, φ) = (∀ ys, ψ)`. -/
def reconstructBind (s : Step) : ReconstructM Expr := do
  if !(s.lits.size == 1 && s.lits[0]!.getKind! == .EQUAL) then
    return ← reconstructBindClause s
  let some a := s.anchor | throwError "bind outside of an anchor"
  let some last := a.last | throwError "bind: empty subproof"
  let k := s.lits[0]![0]!.getKind!
  if k != .FORALL && k != .EXISTS then throwError "bind: unsupported binder {k}"
  let ys := a.vars.map (·.2.2)
  let h ← instantiateMVars last.proof
  let h := zetaAssigns a h
  -- the recorded conclusion, not the proof term's type (a clause lemma may state it as an `orN`)
  let ty ← Meta.whnfR (zetaAssigns a last.concl)
  let some (_, p, q) := ty.eq? | throwError "bind: the subproof does not prove an equality"
  let p := zetaAssigns a p
  let q := zetaAssigns a q
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

/-- `onepoint`: `(∀ x, φ) = ψ` where `φ` contains the guard `¬(x = t)` (or `x = t → …`), resp.
    `(∃ x, φ) = ψ` where `φ` contains the conjunct `x = t`, with the subproof proving `φ[t] = ψ`
    under `x := t`. -/
def reconstructOnepoint (s : Step) : ReconstructM Expr := do
  let some a := s.anchor | throwError "onepoint: outside of an anchor"
  let some last := a.last | throwError "onepoint: empty subproof"
  if a.assigns.size != 1 then throwError "onepoint: {a.assigns.size} assignments (one variable is supported)"
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
          | .forallE _ d _ _ =>  -- x = t → B
            if !isGuard d then throwError "onepoint: no guard in {body}"
            let hd ← Meta.withLocalDeclD `hd d fun hd => do
              let hxt' := match d.eq? with
                | some (_, l₁, _) => if l₁ == x then hd else mkApp4 (mkConst ``Eq.symm [u]) α te x hd
                | none => hd
              Meta.mkLambdaFVars #[hd] (← Meta.mkAbsurd body hxt' hnx)
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
    addThm s.concl (← Meta.mkAppM ``Prop.impliesElim #[hf])
  | "bind" => addThm s.concl (← reconstructBind s)
  | "onepoint" => addThm s.concl (← reconstructOnepoint s)
  | "let" => addThm s.concl (← reconstructLet s)
  | "sko_ex" => addThm s.concl (← reconstructSko s true)
  | "sko_forall" => addThm s.concl (← reconstructSko s false)
  | "qnt_rm_unused" | "qnt_join" | "miniscope_distribute" | "miniscope_split" | "miniscope_ite" =>
    let some rule := rewriteRule s.rule | return none
    let result := s.lits[0]!
    let rw : RewriteStep := { rule, args := #[result], result, premises := #[] }
    match ← Quant.reconstructRewrite rw with
    | some e => addThm s.concl e
    | none => return none
  | _ => return none

end Smt.Alethe
