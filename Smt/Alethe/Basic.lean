/-
Copyright (c) 2021-2026 by the authors listed in the file AUTHORS and their
institutional affiliations. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Haniel Barbosa
-/

module

public import Smt.Reconstruct
public meta import Smt.Reconstruct
public import Smt.Alethe.Realize
public meta import Smt.Alethe.Realize

public meta section

/-!
# Alethe step reconstruction: shared definitions

What a rule reconstructor receives (`Step`), how clauses are represented (`mkClause`), and the
attribute-driven dispatch type `RuleReconstructor`.
-/

namespace Smt.Alethe

open Lean Qq
open Smt.Reconstruct

register_option smt.alethe.progress : Nat := {
  defValue := 0
  descr := "print a progress line to stderr every N steps, and slow or fallback steps (0: off)"
}

/-- A previously checked step (or an assumption), as seen by later steps. -/
structure Premise where
  id : String
  /-- The literals of the clause. -/
  lits : Array cvc5.Term
  /-- The clause as a proposition (an `Or` chain; `False` for the empty clause). -/
  concl : Expr
  /-- A proof of `concl`. -/
  proof : Expr
deriving Inhabited

/-- The context of the subproof closed by a step. -/
structure AnchorCtx where
  /-- Variables introduced by `(x S)` arguments: original name, cvc5 constant, Lean fvar. -/
  vars : Array (String × cvc5.Term × Expr) := #[]
  /-- Substitutions `(:= x t)`: original name, cvc5 constant for `x`, its fvar, `t`, and `t`'s
      reconstruction. -/
  assigns : Array (String × cvc5.Term × Expr × cvc5.Term × Expr) := #[]
  /-- The subproof's assumptions, in order. -/
  assums : Array Premise := #[]
  /-- The last step of the subproof. -/
  last : Option Premise := none
deriving Inhabited

/-- A step to reconstruct. -/
structure Step where
  id : String
  rule : String
  lits : Array cvc5.Term
  /-- The stated clause as a proposition; a reconstructor must return a proof of it. -/
  concl : Expr
  premises : Array Premise
  args : Array (Arg cvc5.Term)
  discharge : Array Premise
  /-- Present iff the step closes a subproof. -/
  anchor : Option AnchorCtx
deriving Inhabited

/-- A rule reconstructor returns a proof of `step.concl`, or `none` if it does not handle the
    rule. Register with `@[alethe_rule_reconstruct]`. -/
abbrev RuleReconstructor := Step → ReconstructM (Option Expr)

/-- The clause `(cl l₁ … lₙ)` as the proposition `l₁ ∨ (l₂ ∨ … lₙ)` (`False` when empty). -/
def mkClause (lits : Array cvc5.Term) : ReconstructM Expr := do
  if lits.isEmpty then
    return q(False)
  let mut curr ← reconstructTerm lits.back!
  for i in [1:lits.size] do
    curr := mkApp2 (mkConst ``Or) (← reconstructTerm lits[lits.size - i - 1]!) curr
  return curr

/-- A proof of `a = a`. -/
def mkEqRefl (a : cvc5.Term) : ReconstructM Expr := do
  let (u, (α : Q(Sort u))) ← reconstructSortLevelAndSort a.getSort!
  let x : Q($α) ← reconstructTerm a
  return q(Eq.refl $x)

/-- The propositions of a list of terms, as a `List Prop` expression. -/
def mkPropList (ts : Array cvc5.Term) : ReconstructM Q(List Prop) :=
  ts.foldrM (fun t ps => do
    let p : Q(Prop) ← reconstructTerm t
    return q($p :: $ps)) q([])

namespace Arg

def term? : Arg cvc5.Term → Option cvc5.Term
  | .term t => some t
  | _ => none

def term! (a : Arg cvc5.Term) : cvc5.Term :=
  a.term?.get!

def str? : Arg cvc5.Term → Option String
  | .str s => some s
  | _ => none

/-- The integer value of a numeral argument, also accepting `(- n)`. -/
def int? : Arg cvc5.Term → Option Int
  | .term t =>
    match t.getKind! with
    | .CONST_INTEGER => some t.getIntegerValue!
    | .NEG => match t[0]!.getKind! with
      | .CONST_INTEGER => some (-t[0]!.getIntegerValue!)
      | _ => none
    | _ => none
  | _ => none

/-- The rational value of a numeral argument, also accepting `(- c)` and `(/ c d)`. -/
partial def rat? : Arg cvc5.Term → Option Rat
  | .term t => go t
  | _ => none
where
  go (t : cvc5.Term) : Option Rat :=
    match t.getKind! with
    | .CONST_INTEGER => some t.getIntegerValue!
    | .CONST_RATIONAL => some t.getRationalValue!
    | .NEG => (- ·) <$> go t[0]!
    | .DIVISION => do
      let n ← go t[0]!
      let d ← go t[1]!
      if d == 0 then none else some (n / d)
    | .TO_REAL => go t[0]!
    | _ => none

def bool? : Arg cvc5.Term → Option Bool
  | .term t => if t.getKind! == .CONST_BOOLEAN then some t.getBooleanValue! else none
  | _ => none

end Arg

namespace Step

def premise! (s : Step) (i : Nat) : Premise := s.premises[i]!

/-- The index argument `:args (k)` of `and`, `not_or`, `and_pos`, `or_neg`. -/
def index? (s : Step) : Option Nat := do
  let a ← s.args[0]?
  let i ← a.int?
  if i < 0 then none else some i.toNat

end Step

/-- The children of an n-ary application of kind `k` (or the term itself). -/
def nary (k : cvc5.Kind) (t : cvc5.Term) : Array cvc5.Term := Id.run do
  if t.getKind! != k then
    return #[t]
  let mut ts := #[]
  for c in t do
    ts := ts.push c
  return ts

/-- Is `t₁` the negation of `t₂`? -/
def isNotOf (t₁ t₂ : cvc5.Term) : Bool :=
  t₁.getKind! == .NOT && t₁[0]! == t₂

end Smt.Alethe
