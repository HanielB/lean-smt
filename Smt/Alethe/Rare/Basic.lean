/-
Copyright (c) 2021-2026 by the authors listed in the file AUTHORS and their
institutional affiliations. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Haniel Barbosa
-/

module

@[expose] public section

namespace Smt.Alethe

/-- Which instance of a RARE rule a Lean theorem states: `mono` for rules with a single
    statement (monomorphic, or polymorphic over any sort), `int`/`rat` for the two instances of
    a rule polymorphic over the arithmetic sorts. -/
inductive RareInst where
  | mono | int | rat
deriving Repr, BEq, Inhabited

/-- The kind of a rule argument: a term, or a list of terms (a `:list` parameter, given as
    `(rare-list …)` in the step's `:args`). -/
inductive RareArgKind where
  | term | list
deriving Repr, BEq, Inhabited

/-- A Lean theorem stating (an instance of) a RARE rule. It takes the rule's arguments and then
    its premises as explicit binders, in order. `proved` is false while the proof is `sorry`. -/
structure RareThm where
  inst : RareInst
  name : Lean.Name
  proved : Bool
deriving Repr, Inhabited

/-- One RARE rule: its name in the rule file, the kinds of its `:args`, the number of its
    `:premises`, and the Lean theorems stating it. -/
structure RareRule where
  name : String
  args : Array RareArgKind
  premises : Nat
  thms : Array RareThm
deriving Repr, Inhabited

end Smt.Alethe
