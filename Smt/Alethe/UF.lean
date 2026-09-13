/-
Copyright (c) 2021-2026 by the authors listed in the file AUTHORS and their
institutional affiliations. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Haniel Barbosa
-/

module

public import Smt.Alethe.Clause
public meta import Smt.Alethe.Clause
public import Smt.Reconstruct.UF
public meta import Smt.Reconstruct.UF
public import Smt.Reconstruct.Builtin
public meta import Smt.Reconstruct.Builtin
public import Smt.Reconstruct.Prop
public meta import Smt.Reconstruct.Prop
public import Smt.Reconstruct.Int
public meta import Smt.Reconstruct.Int
public import Smt.Reconstruct.Rat
public meta import Smt.Reconstruct.Rat
public import Smt.Reconstruct.Quant
public meta import Smt.Reconstruct.Quant
public import Smt.Alethe.Rare
public meta import Smt.Alethe.Rare
public import Lean.Meta.Native
public meta import Lean.Meta.Native

public meta section

/-!
# Equality and rewriting rules

`refl`, `symm`, `trans`, `cong`, their clausal variants, and the term-level rewriting rules
(`semilattice_simp`, `boolean_group_simp`, `assoc_simp`, `evaluate`, `rare_rewrite`), mapped onto
`Smt.Reconstruct.UF` and
`Smt.Reconstruct.Builtin`.
-/

namespace Smt.Alethe

open Lean Qq
open Smt.Reconstruct

/-- The Boolean atoms of a term that stand in the way of deciding it: the propositional leaves
    whose own `Decidable` instance is classical, an uninterpreted Boolean symbol being the usual
    case. The propositional connectives are descended through, everything else is a leaf. -/
partial def opaqueAtoms (e : Expr) (acc : Array Expr) : ReconstructM (Array Expr) := do
  match e.getAppFnArgs with
  | (``And, #[a, b]) | (``Or, #[a, b]) | (``Iff, #[a, b]) => opaqueAtoms b (← opaqueAtoms a acc)
  | (``Not, #[a]) => opaqueAtoms a acc
  | (``Eq, #[ty, a, b]) =>
    if ty.isProp then opaqueAtoms b (← opaqueAtoms a acc) else pure acc
  | (``ite, #[_, c, _, a, b]) => opaqueAtoms b (← opaqueAtoms a (← opaqueAtoms c acc))
  | _ =>
    unless ← Meta.isProp e do return acc
    if e.isConstOf ``True || e.isConstOf ``False then return acc
    let computable ← match ← Meta.trySynthInstance (← Meta.mkAppM ``Decidable #[e]) with
      | .some inst => pure !(inst.getUsedConstants.any (isNoncomputable (← getEnv)))
      | _ => pure false
    if computable || acc.contains e then return acc
    return acc.push e

/-- The sides of an equality term. -/
def eqSides (t : cvc5.Term) : ReconstructM (cvc5.Term × cvc5.Term) := do
  if t.getKind! != .EQUAL then throwError "expected an equality, got {t}"
  return (t[0]!, t[1]!)

/-- Whether two terms are equal, syntactically or (inside a context with substitutions, where the
    left-hand side's variables are `let`-bound to the right-hand side's) definitionally. -/
def termEq (a b : cvc5.Term) : ReconstructM Bool := do
  if a == b then return true
  if a.getSort! != b.getSort! then return false
  Meta.isDefEq (← reconstructTerm a) (← reconstructTerm b)

/-- A proof of `a = b` by `Eq.refl` for terms that are definitionally equal. -/
def mkEqRefl' (a b : cvc5.Term) : ReconstructM Expr := do
  let (u, (α : Q(Sort u))) ← reconstructSortLevelAndSort a.getSort!
  let x : Q($α) ← reconstructTerm a
  let y : Q($α) ← reconstructTerm b
  return ← Meta.mkExpectedTypeHint q(Eq.refl $x) q($x = $y)

/-- A proof of `a = b` from a premise proving either `a = b` or `b = a`. -/
def orient (pr : Premise) (a b : cvc5.Term) : ReconstructM Expr := do
  let (l, r) ← eqSides pr.lits[0]!
  if l == a && r == b then
    return pr.proof
  let (u, (α : Q(Sort u))) ← reconstructSortLevelAndSort l.getSort!
  let x : Q($α) ← reconstructTerm l
  let y : Q($α) ← reconstructTerm r
  let h : Q($x = $y) := pr.proof
  if l == b && r == a then
    return q(Eq.symm $h)
  -- up to the context's substitutions (`<&&>` keeps the second defeq check behind the first;
  -- `(← …) && (← …)` would run both)
  if ← termEq l a <&&> termEq r b then
    let a : Q($α) ← reconstructTerm a
    let b : Q($α) ← reconstructTerm b
    return ← Meta.mkExpectedTypeHint h q($a = $b)
  if ← termEq l b <&&> termEq r a then
    let a : Q($α) ← reconstructTerm a
    let b : Q($α) ← reconstructTerm b
    return ← Meta.mkExpectedTypeHint q(Eq.symm $h) q($a = $b)
  throwError "premise {pr.lits[0]!} does not prove {a} = {b} in either direction"

/-- A proof of `a = a`. -/
def mkRefl (a : cvc5.Term) : ReconstructM Expr := mkEqRefl a

/-- `rare_rewrite` with `distinct-false`: `(= (distinct … t … t …) false)`. The reconstruction of
    `distinct` is a conjunction of pairwise disequalities, one of which is `t ≠ t`. -/
def reconstructDistinctFalse (s : Step) : ReconstructM Expr := do
  let (l, _) ← eqSides s.lits[0]!
  let le ← reconstructTerm l
  let ps ← collectPropsInAndChain le
  let sidesOf (p : Expr) : Option (Expr × Expr) :=
    match p.ne? with
    | some (_, a, b) => some (a, b)
    | none => match p.not? >>= Expr.eq? with
      | some (_, a, b) => some (a, b)
      | none => none
  let some i := ps.findIdx? (fun p => match sidesOf p with | some (a, b) => a == b | none => false)
    | throwError "distinct-false: no reflexive disequality in {le}"
  let some (a, _) := sidesOf ps[i]! | unreachable!
  let h ← Meta.withLocalDeclD `h le fun h => do
    let pr ← Prop.mkAndProj h le ps.length i
    Meta.mkLambdaFVars #[h] (mkApp pr (← Meta.mkEqRefl a))
  addThm s.concl (← Meta.mkAppM ``eq_false #[h])

/-- A proof of `a = c` from `hab : a = b` and `hbc : b = c`. -/
def mkTrans (a b c : cvc5.Term) (hab hbc : Expr) : ReconstructM Expr := do
  let (u, (α : Q(Sort u))) ← reconstructSortLevelAndSort a.getSort!
  let x : Q($α) ← reconstructTerm a
  let y : Q($α) ← reconstructTerm b
  let z : Q($α) ← reconstructTerm c
  let hab : Q($x = $y) := hab
  let hbc : Q($y = $z) := hbc
  return q(Eq.trans $hab $hbc)

/-- `l = r` for two terms that differ only where one of `eqs` applies, by congruence on their
    application structure. Rewriting by term instead — abstracting an argument's occurrences and
    applying `congrArg` — is wrong when one argument occurs inside another, which is common among
    the arguments of an n-ary `distinct` (`x` and `f x` are both arguments). -/
partial def transportEq (eqs : Array (Expr × Expr × Expr)) (l r : Expr) : MetaM Expr := do
  if l == r then return ← Meta.mkEqRefl l
  if let some (_, _, h) := eqs.find? (fun (a, b, _) => a == l && b == r) then return h
  match l, r with
  | .app f x, .app g y =>
    if f == g then return ← Meta.mkCongrArg f (← transportEq eqs x y)
    if x == y then return ← Meta.mkCongrFun (← transportEq eqs f g) x
    Meta.mkCongr (← transportEq eqs f g) (← transportEq eqs x y)
  | _, _ => throwError "cong: cannot align{indentExpr l}\nwith{indentExpr r}"

/-- `l = r` for two conjunctions of disequalities that agree pairwise up to the orientation of
    each disequality (`x ≠ y` vs `y ≠ x`), by congruence on the `∧`-chain with `ne_symm_eq` at the
    flipped leaves. `none` when the two are not aligned this way (a genuine reordering), leaving
    the quadratic pairwise conversion as the fallback. -/
partial def distinctCongEq (a b : Expr) : MetaM (Option Expr) := do
  if a == b then return some (← Meta.mkEqRefl a)
  let pairOf (e : Expr) : Option (Expr × Expr) :=
    match e.ne? with
    | some (_, x, y) => some (x, y)
    | none => match e.not? >>= Expr.eq? with
      | some (_, x, y) => some (x, y)
      | none => none
  let leafEq (x y : Expr) : MetaM (Option Expr) := do
    if x == y then return some (← Meta.mkEqRefl x)
    match pairOf x, pairOf y with
    | some (p, q), some (u, v) =>
      if p == v && q == u then
        let α ← Meta.inferType p
        let lvl ← Meta.getLevel α
        return some (mkApp3 (mkConst ``ne_symm_eq [lvl]) α p q)
      return none
    | _, _ => return none
  match a.and?, b.and? with
  | some (la, lb), some (ra, rb) =>
    let some ha ← leafEq la ra | return none
    let some hb ← distinctCongEq lb rb | return none
    return some (← Meta.mkCongr (← Meta.mkCongrArg (mkConst ``And) ha) hb)
  | none, none => leafEq a b
  | _, _ => return none

/-- `f(l₁ … lₙ) = f(r₁ … rₙ)` from `hs : lᵢ = rᵢ` for reconstructions that are not applications of
    a function to the arguments (n-ary `distinct`, whose reconstruction is a conjunction of
    pairwise disequalities): transport the changed arguments through that structure. -/
def congByRewriting (s : Step) (l r : cvc5.Term) (start : Nat) (hs : Array Expr) : ReconstructM Expr := do
  let le ← reconstructTerm l
  let re ← reconstructTerm r
  let mut eqs := #[]
  for i in [start:l.getNumChildren] do
    if l[i]! == r[i]! then continue
    eqs := eqs.push (← reconstructTerm l[i]!, ← reconstructTerm r[i]!, hs[i - start]!)
  let h ← transportEq eqs le re
  addThm s.concl (← Meta.mkExpectedTypeHint h (← Meta.mkEq le re))

/-- `cong`: align the premises with the argument positions of the two applications (equal
    arguments get `Eq.refl`, flipped premises `Eq.symm`), then use `smtCongr`. -/
def reconstructCong (s : Step) : ReconstructM Expr := do
  let (l, r) ← eqSides s.lits[0]!
  let k := l.getKind!
  if k == .FORALL || k == .EXISTS || k == .LAMBDA || k == .WITNESS then
    throwError "cong under binders is not supported"
  if l.getKind! != r.getKind! || l.getNumChildren != r.getNumChildren then
    throwError "cong: {l} and {r} have different shapes"
  -- the function symbol of an application is child 0 in cvc5
  let start := if k == .APPLY_UF then 1 else 0
  if k == .APPLY_UF && l[0]! != r[0]! then
    throwError "cong: different function symbols"
  -- premises need not be one per argument nor in order (reflexive ones may be given or omitted)
  let matchesEq (pr : Premise) (a b : cvc5.Term) : Bool :=
    pr.lits.size == 1 && pr.lits[0]!.getKind! == .EQUAL &&
      ((pr.lits[0]![0]! == a && pr.lits[0]![1]! == b) || (pr.lits[0]![0]! == b && pr.lits[0]![1]! == a))
  -- the proof of `a = b` for each argument pair
  let align (pairs : Array (cvc5.Term × cvc5.Term)) : ReconstructM (Array Expr) := do
    let mut hs := #[]
    for (a, b) in pairs do
      if a == b then
        hs := hs.push (← mkRefl a)
      else if let some pr := s.premises.find? (matchesEq · a b) then
        hs := hs.push (← orient pr a b)
      else
        -- the defeq checks stay behind the syntactic ones (an `else if ← …` would hoist them out
        -- of the conditional and run them for every argument)
        if ← termEq a b then
          -- equal up to the context's substitutions
          hs := hs.push (← mkEqRefl' a b)
        else
          -- a premise equal to the pair up to the substitutions
          let mut found := none
          for pr in s.premises do
            if pr.lits.size == 1 && pr.lits[0]!.getKind! == .EQUAL then
              let (x, y) ← eqSides pr.lits[0]!
              if ← (termEq x a <&&> termEq y b) <||> (termEq x b <&&> termEq y a) then
                found := some pr
                break
          let some pr := found | throwError "cong: no premise for {a} = {b}"
          hs := hs.push (← orient pr a b)
    return hs
  let pairs := (List.range l.getNumChildren).toArray[start:].toArray.map fun i => (l[i]!, r[i]!)
  if k == .EQUAL && l.getNumChildren == 2 then
    -- Carcara's special case: between two binary equalities, either side's arguments may be
    -- flipped (veriT orders the arguments of an equality as it likes), so `(= (= a b) (= c d))`
    -- may be justified by `a = c, b = d`, `b = c, a = d`, `a = d, b = c` or `b = d, a = c`. The
    -- flipped sides are put straight by `eq_symm` around the congruence
    let (a, b, c, d) := (l[0]!, l[1]!, r[0]!, r[1]!)
    match ← (try some <$> align pairs catch _ => pure none) with
    | some hs => return ← addTac s.concl (UF.smtCongr · hs)
    | none =>
      let (u, (α : Q(Sort u))) ← reconstructSortLevelAndSort a.getSort!
      for (lf, rf) in [(true, false), (false, true), (true, true)] do
        let (l₁, l₂) := if lf then (b, a) else (a, b)
        let (r₁, r₂) := if rf then (d, c) else (c, d)
        let some hs ← (try some <$> align #[(l₁, r₁), (l₂, r₂)] catch _ => pure none) | continue
        let goal ← Meta.mkEq (← Meta.mkEq (← reconstructTerm l₁) (← reconstructTerm l₂))
          (← Meta.mkEq (← reconstructTerm r₁) (← reconstructTerm r₂))
        let mv ← Meta.mkFreshExprMVar goal
        UF.smtCongr mv.mvarId! hs
        let mut h ← instantiateMVars mv
        if lf then  -- (a = b) = (b = a), then (b = a) = …
          h ← Meta.mkEqTrans (mkApp3 (mkConst ``UF.eq_symm [u]) α (← reconstructTerm a) (← reconstructTerm b)) h
        if rf then  -- … = (d = c), then (d = c) = (c = d)
          h ← Meta.mkEqTrans h (mkApp3 (mkConst ``UF.eq_symm [u]) α (← reconstructTerm d) (← reconstructTerm c))
        return ← addThm s.concl h
      throwError "cong: no orientation of {l} and {r} matches the premises"
  let hs ← align pairs
  if k == .DISTINCT then
    -- `distinct` reconstructs to a conjunction of disequalities, not an application: rewrite the
    -- arguments one at a time
    return ← congByRewriting s l r start hs
  addTac s.concl (UF.smtCongr · hs)

/-- Prove a clause `(cl l₁ … lₙ)` by refuting the negations of its literals: `k` receives the
    hypotheses `hᵢ : ¬lᵢ` (with their terms) and must return a proof of `False`. -/
def byRefutation (s : Step) (k : Array (cvc5.Term × Expr) → ReconstructM Expr) : ReconstructM Expr := do
  let ps ← mkPropList s.lits
  let decls ← s.lits.mapIdxM fun i l => do
    let p ← reconstructTerm l
    return (Name.num `h i, fun (_ : Array Expr) => pure (mkApp (mkConst ``Not) p))
  let h ← Meta.withLocalDeclsD decls fun hs => do
    Meta.mkLambdaFVars hs (← k (s.lits.zip hs))
  return mkApp2 (mkConst ``orN_of_impliesN_not) ps h

/-- From `hneg : ¬¬(a = b)` (or `¬¬(b = a)`) a proof of `a = b`. -/
def eqOfNegNeg (hneg : Expr) (l : cvc5.Term) (a b : cvc5.Term) : ReconstructM Expr := do
  let h ← Meta.mkAppM ``Prop.notNotElim #[hneg]
  let (x, y) ← eqSides l[0]!
  if x == a && y == b then return h
  if x == b && y == a then return ← Meta.mkAppM ``Eq.symm #[h]
  throwError "premise {l} does not relate {a} and {b}"

/-- `eq_transitive`: `(cl (not (= t₁ t₂)) … (not (= tₙ₋₁ tₙ)) (= t₁ tₙ))`. -/
def reconstructEqTransitive (s : Step) : ReconstructM Expr := do
  let n := s.lits.size
  if n < 2 then throwError "eq_transitive: too few literals"
  let (a, b) ← eqSides s.lits[n-1]!
  byRefutation s fun hs => do
    -- chain the negated-negated equalities from `a`
    let mut curr := a
    let mut h : Option Expr := none
    for (l, hneg) in hs[:n-1] do
      let (x, y) ← eqSides l[0]!
      let next := if x == curr then y else if y == curr then x else
        curr
      if next == curr && !(x == curr && y == curr) then throwError "eq_transitive: chain broken at {l}"
      let hstep ← eqOfNegNeg hneg l curr next
      h := some (← match h with
        | none => pure hstep
        | some h₀ => Meta.mkAppM ``Eq.trans #[h₀, hstep])
      curr := next
    if curr != b then throwError "eq_transitive: chain ends at {curr}, expected {b}"
    let some hab := h | throwError "eq_transitive: no premises"
    return mkApp hs[n-1]!.2 hab  -- ¬(a = b) applied to a = b

/-- `eq_congruent`: `(cl (not (= t₁ u₁)) … (not (= tₙ uₙ)) (= (f ts) (f us)))`, and
    `eq_congruent_pred`: `… (not (P ts)) (P us)`. -/
def reconstructEqCongruent (s : Step) (pred : Bool) : ReconstructM Expr := do
  let n := s.lits.size
  byRefutation s fun hs => do
    let (l, r) ← if pred then pure (s.lits[n-2]![0]!, s.lits[n-1]!) else eqSides s.lits[n-1]!
    if l.getKind! != r.getKind! || l.getNumChildren != r.getNumChildren then
      throwError "eq_congruent: {l} and {r} have different shapes"
    let start := if l.getKind! == .APPLY_UF then 1 else 0
    let eqs := hs[:n - (if pred then 2 else 1)]
    let mut args := #[]
    for i in [start:l.getNumChildren] do
      if l[i]! == r[i]! then
        args := args.push (← mkRefl l[i]!)
      else
        let some (le, hneg) := eqs.toArray.find? (fun (le, _) =>
            let (x, y) := (le[0]![0]!, le[0]![1]!)
            (x == l[i]! && y == r[i]!) || (x == r[i]! && y == l[i]!))
          | throwError "eq_congruent: no premise for {l[i]!} = {r[i]!}"
        args := args.push (← eqOfNegNeg hneg le l[i]! r[i]!)
    let le ← reconstructTerm l
    let re ← reconstructTerm r
    let goal ← Meta.mkEq le re
    let mv ← Meta.mkFreshExprMVar goal
    UF.smtCongr mv.mvarId! args
    let hlr ← instantiateMVars mv
    if pred then
      -- hs[n-2] : ¬¬(P ts), hs[n-1] : ¬(P us)
      let hp ← Meta.mkAppM ``Prop.notNotElim #[hs[n-2]!.2]
      return mkApp hs[n-1]!.2 (← Meta.mkAppM ``Eq.mp #[hlr, hp])
    else
      return mkApp hs[n-1]!.2 hlr

@[alethe_rule_reconstruct] def reconstructUF : RuleReconstructor := fun s => do
  match s.rule with
  | "eq_transitive" => addThm s.concl (← reconstructEqTransitive s)
  | "eq_congruent" => addThm s.concl (← reconstructEqCongruent s false)
  | "eq_congruent_pred" => addThm s.concl (← reconstructEqCongruent s true)
  | "refl" | "eq_reflexive" =>
    let (a, b) ← eqSides s.lits[0]!
    if a == b then
      addThm s.concl (← mkRefl a)
    else
      -- `(= x t)` under the context's `x := t`: `Eq.refl` closes it by unfolding the `let`, but
      -- the proof's type must be pinned to the stated `x = t`. Once the closing step of the block
      -- zeta-reduces the `let`, an unpinned `Eq.refl x` would read `t = t`, and a step that
      -- used this one as a premise for `x = t` (a `cong`) would no longer typecheck
      addThm s.concl (← mkEqRefl' a b)
  | "symm" =>
    let pr := s.premise! 0
    if s.lits[0]!.getKind! == .EQUAL then
      let (a, b) ← eqSides s.lits[0]!
      addThm s.concl (← orient pr a b)
    else
      -- (cl (not (= a b))) ⊢ (cl (not (= b a)))
      let (b, a) ← eqSides (← unNotTerm s.lits[0]!)
      let (u, (α : Q(Sort u))) ← reconstructSortLevelAndSort a.getSort!
      let x : Q($α) ← reconstructTerm a
      let y : Q($α) ← reconstructTerm b
      let h : Q($x ≠ $y) := pr.proof
      addThm s.concl q(Ne.symm $h)
  | "not_symm" =>
    let pr := s.premise! 0
    let (b, a) ← eqSides (← unNotTerm s.lits[0]!)
    let (u, (α : Q(Sort u))) ← reconstructSortLevelAndSort a.getSort!
    let x : Q($α) ← reconstructTerm a
    let y : Q($α) ← reconstructTerm b
    let h : Q($x ≠ $y) := pr.proof
    addThm s.concl q(Ne.symm $h)
  | "eq_symmetric" =>
    if s.lits.size == 1 then
      -- Carcara's form: (cl (= (= a b) (= b a)))
      let (l, _) ← eqSides s.lits[0]!
      let (a, b) ← eqSides l
      let (u, (α : Q(Sort u))) ← reconstructSortLevelAndSort a.getSort!
      let x : Q($α) ← reconstructTerm a
      let y : Q($α) ← reconstructTerm b
      addThm s.concl q(@UF.eq_symm $α $x $y)
    else
      -- (cl (not (= a b)) (= b a))
      let (b, a) ← eqSides s.lits[1]!
      let (u, (α : Q(Sort u))) ← reconstructSortLevelAndSort a.getSort!
      let x : Q($α) ← reconstructTerm a
      let y : Q($α) ← reconstructTerm b
      addThm s.concl q(Prop.impliesElim (@Eq.symm $α $x $y))
  | "trans" =>
    let (a, b) ← eqSides s.lits[0]!
    -- a reflexive conclusion (a chain that returns to its start) needs no premise
    if a == b then return ← addThm s.concl (← mkEqRefl a)
    -- chain the premises from `a`, orienting each one (reflexive premises do not advance it);
    -- links are matched up to the context's substitutions
    let mut curr := a
    let mut h : Option Expr := none
    for pr in s.premises do
      let (l, r) ← eqSides pr.lits[0]!
      if l == r then continue
      -- (`(← …)` in a condition is hoisted out of the `if`: the defeq checks must stay behind
      -- the syntactic ones, or every link costs an `isDefEq` on the whole terms)
      let next ←
        if l == curr then pure r
        else if r == curr then pure l
        else do
          if ← termEq l curr then pure r
          else if ← termEq r curr then pure l
          else throwError "trans: premise {pr.lits[0]!} does not continue from {curr}"
      let hstep ← orient pr curr next
      h := some (← match h with
        | none => pure hstep
        | some h₀ => mkTrans a curr next h₀ hstep)
      curr := next
    if curr != b then
      unless ← termEq curr b do throwError "trans: chain ends at {curr}, expected {b}"
    let some hab := h | throwError "trans without premises"
    addThm s.concl hab
  | "cong" => reconstructCong s
  | "distinct_elim" =>
    -- (= (distinct xs) (and (not (= xᵢ xⱼ)) …)): definitional when the pairs come in the order
    -- and orientation of the reconstruction; otherwise match the pairs up to symmetry
    let (l, r) ← eqSides s.lits[0]!
    let le ← reconstructTerm l
    let re ← reconstructTerm r
    if r.getKind! == .CONST_BOOLEAN && !r.getBooleanValue! then
      -- three or more Boolean arguments cannot be pairwise distinct: `(= (distinct ps) false)`.
      -- The reconstruction lists the pairs `(i, j)` with `i < j` in lexicographic order, so the
      -- disequalities of the first three arguments are the conjuncts 0, 1 and n - 1
      let n := l.getNumChildren
      if n < 3 then throwError "distinct_elim: {l} is not false"
      let ps ← collectPropsInAndChain le
      let h ← Meta.withLocalDeclD `h le fun h => do
        -- one chain for the three projections, so the spine to conjunct `n - 1` is built once
        let c := Prop.ProjChain.of .and h le ps.length
        let (c₀, c) ← c.proj 0
        let (c₁, c) ← c.proj 1
        let (c₂, _) ← c.proj (n - 1)
        Meta.mkLambdaFVars #[h] (← Meta.mkAppM ``distinct_bool_false #[c₀, c₁, c₂])
      return ← addThm s.concl (← Meta.mkAppM ``eq_false #[h])
    if ← Meta.isDefEq le re then return ← addThm s.concl (← mkRefl l)
    let pairOf (e : Expr) : Option (Expr × Expr) :=
      match e.ne? with
      | some (_, a, b) => some (a, b)
      | none => match e.not? >>= Expr.eq? with
        | some (_, a, b) => some (a, b)
        | none => none
    -- fast path: the two conjunctions have the same pairs in the same positions, differing only
    -- in the orientation of some disequalities (Carcara's `polyeq` canonicalizes `(= a b)` vs
    -- `(= b a)`). Prove `le = re` by congruence on the `∧`-chain — O(#pairs) proof nodes — instead
    -- of the pairwise conversion below, which embeds the whole conjunct list in each `and_elim`
    -- and so is quadratic in the term (out of memory on the large `distinct`s of ESC-Java proofs).
    if let some h ← distinctCongEq le re then
      return ← addThm s.concl h
    let ls ← collectPropsInAndChain le
    let rs ← collectPropsInAndChain re
    -- from `h : andN src` prove `andN tgt`, pairing each target conjunct with a source one.
    -- The projections share one chain: a `distinct` over n arguments has n(n-1)/2 conjuncts
    -- and every one of them is projected, so a chain per conjunct would be quartic in n (it
    -- was, and ran out of memory on the ESC-Java proofs).
    let convert (src tgt : List Expr) (sty : Expr) (h : Expr) : ReconstructM Expr := do
      let mut c := Prop.ProjChain.of .and h sty src.length
      let mut proofs := #[]
      for t in tgt do
        let some (a, b) := pairOf t | throwError "distinct_elim: unexpected conjunct {t}"
        let some i := src.findIdx? (fun e => match pairOf e with
            | some (c, d) => (c == a && d == b) || (c == b && d == a)
            | none => false) | throwError "distinct_elim: no pair for {t}"
        let (pr, c') ← c.proj i
        c := c'
        let some (c₀, _) := pairOf src[i]! | unreachable!
        let pr' ← if c₀ == a then pure pr else Meta.mkAppM ``Ne.symm #[pr]
        proofs := proofs.push pr'
      -- andN tgt as a right-nested conjunction
      let mut acc := proofs.back!
      for pr in proofs.pop.reverse do
        acc ← Meta.mkAppM ``And.intro #[pr, acc]
      return acc
    let mp ← Meta.withLocalDeclD `h le fun h => do Meta.mkLambdaFVars #[h] (← convert ls rs le h)
    let mpr ← Meta.withLocalDeclD `h re fun h => do Meta.mkLambdaFVars #[h] (← convert rs ls re h)
    addThm s.concl (← Meta.mkAppM ``propext #[← Meta.mkAppM ``Iff.intro #[mp, mpr]])
  | "semilattice_simp" =>
    -- One `∧`/`∨` layer normalized by the verified `AciNorm` normalizer (kernel evaluation):
    -- associativity, commutativity, idempotence, the neutral element and the annihilator of the
    -- connective. Every non-`∧`/`∨` subterm (an arithmetic comparison, a nested opposite
    -- connective) is an opaque atom; Carcara's core pass decomposes nested layers into one
    -- `semilattice_simp` per layer lifted by `cong`. The bitvector semilattices (`bvand`,
    -- `bvor`) are out of the reconstruction's scope.
    let some (_, l, r) := s.concl.eq? | throwError "semilattice_simp: expected an equality"
    -- a layer that collapses to one atom (veriT's `(and x)`) reconstructs to the same term on
    -- both sides, and there is no operator left for the normalizer to see
    if ← Meta.isDefEq l r then
      addThm s.concl (← Meta.mkExpectedTypeHint (← Meta.mkEqRefl l) s.concl)
    else if (Prop.AciNorm.topConnective? l r).isSome then
      addThm s.concl (← Prop.AciNorm.proveEq l r)
    else
      throwError "semilattice_simp: neither side is a conjunction or a disjunction:{indentExpr l}\n={indentExpr r}"
  | "boolean_group_simp" =>
    -- One `xor` layer normalized by the parity normalizer of `AciNorm` (kernel evaluation):
    -- associativity, commutativity, the neutral element `false` and `x ⊕ x = false`. `bvxor` is
    -- out of the reconstruction's scope.
    let some (_, l, r) := s.concl.eq? | throwError "boolean_group_simp: expected an equality"
    if ← Meta.isDefEq l r then
      addThm s.concl (← Meta.mkExpectedTypeHint (← Meta.mkEqRefl l) s.concl)
    else
      addThm s.concl (← Prop.AciNorm.proveXorEq l r)
  | "assoc_simp" =>
    -- Associativity and the neutral element of a non-commutative operator (`concat`, `str.++`).
    -- Neither is in the reconstruction's scope; the generic associative rewriter closes whatever
    -- instance an in-scope operator with an `Std.Associative` instance produces.
    addTac s.concl Meta.AC.rewriteUnnormalizedTop
  | "evaluate" =>
    let (l, r) ← eqSides s.lits[0]!
    let (u, (α : Q(Sort u))) ← reconstructSortLevelAndSort l.getSort!
    let t : Q($α) ← reconstructTerm l
    let t' : Q($α) ← reconstructTerm r
    if l == r then
      return some (← addThm q($t = $t') q(Eq.refl $t))
    let hp : Q(Decidable ($t = $t')) ← Meta.synthDecidableInstance q(($t = $t'))
    if hp.getUsedConstants.any (isNoncomputable (← getEnv)) then
      -- an uninterpreted Boolean symbol in the term makes the instance classical, so `decide`
      -- cannot run; the equality holds for either truth value of such an atom, so split
      let atoms ← opaqueAtoms q($t = $t') #[]
      if atoms.isEmpty then
        -- no opaque atom: a ground Boolean formula whose only non-computable part is `=` between
        -- propositions. Rewrite those to `↔` and evaluate.
        return some (← addTac q($t = $t') decideGround)
      if atoms.size > 8 then throwError "evaluate: {atoms.size} opaque Boolean atoms"
      return some (← addTac q($t = $t') fun mv => proveByCases mv atoms.toList #[])
    addThm q($t = $t') (← decideProofOfNative q($t = $t') hp)
  | "rare_rewrite" =>
    match s.args[0]? with
    | some (.str "distinct-false") => reconstructDistinctFalse s
    | _ => reconstructRareRule s
  | _ => return none
where
  unNotTerm (t : cvc5.Term) : ReconstructM cvc5.Term := do
    if t.getKind! != .NOT then throwError "expected a negation, got {t}"
    return t[0]!

end Smt.Alethe
