/-
Copyright (c) 2021-2026 by the authors listed in the file AUTHORS and their
institutional affiliations. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Haniel Barbosa
-/

module

public import Smt.Alethe.Basic
public meta import Smt.Alethe.Basic
public import Smt.Alethe.Rare.Rules
public meta import Smt.Alethe.Rare.Rules

/-!
# `rare_rewrite` steps

A `rare_rewrite` step names a rule of the RARE rule file Carcara was run with and gives the
rule's arguments (and premises, if any). The rule file is translated to Lean theorems by
`Smt/Alethe/Rare/gen.py` (one theorem per rule, or one per arithmetic sort for rules polymorphic
over Int/Real), together with the table `Smt.Alethe.Rare.rules` describing each rule's arguments.
Checking a step instantiates the theorem with the step's arguments and premises, and unifies the
result with the step's conclusion (which fixes implicit sorts and decidability instances).
-/

public meta section

namespace Smt.Alethe

open Lean Qq
open Smt.Reconstruct

/-- The table entry of a rule, by name. -/
def rareRule? (name : String) : Option RareRule :=
  Rare.rules.find? (·.name == name)

/-- Reconstruct a rule argument of the expected Lean type `β`: integer-sorted terms are cast to
    `Rat` where the rule is instantiated at `Rat` (as `reconstructTerm` does for mixed
    arithmetic; integer literals become rational literals). -/
def reconstructRareArg (t : cvc5.Term) (β : Expr) : ReconstructM Expr := do
  if β.isConstOf ``Rat && t.getSort!.isInteger then
    let lit (n : Nat) : Q(Rat) := let l : Q(Nat) := mkRawNatLit n; q(OfNat.ofNat $l)
    if t.getKind! == .CONST_INTEGER then
      let x := t.getIntegerValue!
      let e := lit x.natAbs
      return if x ≥ 0 then e else q(-$e)
    if t.getKind! == .NEG && t[0]!.getKind! == .CONST_INTEGER then
      let x := t[0]!.getIntegerValue!
      let e := lit x.natAbs
      return if x ≥ 0 then q(-$e) else e
    let x : Q(Int) ← reconstructTerm t
    return q(($x : Rat))
  reconstructTerm t

/-- The arithmetic instance to use for a step: `rat` when some argument is real-sorted. -/
def rareInstOf (s : Step) : RareInst :=
  let isReal (t : cvc5.Term) := t.getSort!.isReal
  let real := s.args[1:].any fun
    | .term t => isReal t
    | .list ts => ts.any isReal
    | _ => false
  if real then .rat else .int

/-- Check a `rare_rewrite` step against the generated theorem of its rule. -/
def reconstructRareRule (s : Step) : ReconstructM (Option Expr) := do
  let some (Arg.str name) := s.args[0]? | throwError "rare_rewrite: missing rule name"
  let some rule := rareRule? name | throwError "rare_rewrite: rule {name} is not in the rule table"
  if rule.thms.isEmpty then throwError "rare_rewrite: rule {name} has no Lean statement"
  let inst := if rule.thms.size == 1 then rule.thms[0]!.inst else rareInstOf s
  let some { name := thm, proved, .. } := rule.thms.find? (·.inst == inst)
    | throwError "rare_rewrite: rule {name} has no {repr inst} instance"
  unless proved do throwError "rare_rewrite: rule {name} is not proved ({thm})"
  if s.args.size != rule.args.size + 1 then
    throwError "rare_rewrite: rule {name} takes {rule.args.size} arguments, got {s.args.size - 1}"
  if s.premises.size != rule.premises then
    throwError "rare_rewrite: rule {name} takes {rule.premises} premises, got {s.premises.size}"
  let e ← Meta.mkConstWithFreshMVarLevels thm
  let (mvars, binfos, type) ← Meta.forallMetaTelescopeReducing (← Meta.inferType e)
  let mut i := 0
  let mut j := 0
  for mv in mvars, bi in binfos do
    unless bi.isExplicit do continue
    let ty ← instantiateMVars (← Meta.inferType mv)
    if i < rule.args.size then
      let v ← match s.args[i + 1]!, rule.args[i]! with
        | .term t, .term => reconstructRareArg t ty
        | .list ts, .list => do
          let β := ty.appArg!
          Meta.mkListLit β (← ts.mapM (reconstructRareArg · β)).toList
        | _, .term => throwError "rare_rewrite: argument {i} of {name} should be a term"
        | _, .list => throwError "rare_rewrite: argument {i} of {name} should be a list"
      unless ← Meta.isDefEq mv v do
        throwError "rare_rewrite: argument {i} of {name} ({v}) does not have type {ty}"
      i := i + 1
    else if j < rule.premises then
      let p := s.premises[j]!
      unless ← Meta.isDefEq mv p.proof do
        throwError "rare_rewrite: premise {j} of {name} ({p.concl}) does not have type {ty}"
      j := j + 1
    else
      throwError "rare_rewrite: {thm} has more explicit binders than {name} has arguments"
  unless ← Meta.isDefEq type s.concl do
    throwError "rare_rewrite: {name} instantiates to{indentExpr type}\nbut the step concludes{indentExpr s.concl}"
  let pf ← instantiateMVars (mkAppN e mvars)
  if pf.hasExprMVar then
    throwError "rare_rewrite: {name}: unassigned metavariables in{indentExpr pf}"
  return some (← addThm s.concl pf)

end Smt.Alethe
