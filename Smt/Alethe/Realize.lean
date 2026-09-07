/-
Copyright (c) 2021-2026 by the authors listed in the file AUTHORS and their
institutional affiliations. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Haniel Barbosa
-/

module

public import cvc5
public meta import cvc5
public import Smt.Alethe.Syntax
public meta import Smt.Alethe.Syntax
public import Smt.Alethe.Parser
public meta import Smt.Alethe.Parser
public import Std.Data.HashSet
public meta import Std.Data.HashSet

public meta section

/-!
# Realization of Alethe proofs into cvc5 terms

The SMT-LIB problem and every term of the proof are parsed by cvc5's own parser (through
lean-cvc5's `InputParser`), so that lean-smt's term reconstruction can be reused unchanged.
Shared closed subterms of the arena are sent to cvc5 once, bound with `:named`, and referred to
by name afterwards; open subterms (mentioning quantifier-bound variables) are printed inline.
-/

namespace Smt.Alethe

open cvc5

/-- The declarations and assertions of the SMT-LIB problem. -/
structure Problem where
  logic : Option String := none
  sorts : Array cvc5.Sort := #[]
  funs : Array Term := #[]
  asserts : Array Term := #[]

structure Realized where
  problem : Problem
  proof : Proof Term
  /-- Fresh anchor-variable symbols and their original names. -/
  renamed : Array (String × String)
  /-- Closed `choice` terms: the fresh constant and the `lambda` of its body. -/
  choices : Array (Term × Term) := #[]

namespace Realize

structure State where
  parser : InputParser
  solver : Solver
  sm : SymbolManager
  arena : Arena
  /-- Realized closed nodes. -/
  memo : Std.HashMap Nat Term := {}
  /-- Nodes bound to a symbol on the cvc5 side. -/
  named : Std.HashMap Nat String := {}
  /-- Nodes whose shared closed descendants have all been named. -/
  prepared : Std.HashSet Nat := {}
  fresh : Nat := 0
  /-- Number of `nextTerm` calls (diagnostics). -/
  parsed : Nat := 0

abbrev M := StateT State cvc5.Env

def feed (s : String) : M Unit := do
  let st ← get
  st.parser.appendIncrementalStringInput (s ++ "\n")

/-- Parse a term from text. -/
def parseText (s : String) : M Term := do
  feed s
  modify fun st => { st with parsed := st.parsed + 1 }
  (← get).parser.nextTerm

/-- Run an SMT-LIB command given as text. -/
def command (s : String) : M Unit := do
  feed s
  let st ← get
  let cmd ← st.parser.nextCommand
  if cmd.isNull then throw (.error s!"expected a command, got end of input after: {s}")
  _ ← cmd.invoke st.solver st.sm

/-- The text of a node, using the bound symbol of every named node. -/
partial def text (i : Nat) : M String := do
  let st ← get
  if let some s := st.named[i]? then return s
  match st.arena.get i with
  | .atom s _ => return s
  | .list cs _ _ =>
    let parts ← cs.mapM text
    return "(" ++ " ".intercalate parts.toList ++ ")"

/-- Name every shared closed list node below (and including) `i`, bottom-up, so that printing
    any term of the arena stays linear in its DAG size. -/
partial def prepare (i : Nat) : M Unit := do
  if (← get).prepared.contains i then return
  match (← get).arena.get i with
  | .atom _ _ => pure ()
  | .list cs isOpen _ =>
    for c in cs do prepare c
    let st ← get
    if !isOpen && st.arena.refs[i]! ≥ 2 && !st.named.contains i then
      let sym := s!"s!{st.fresh}"
      modify fun st => { st with fresh := st.fresh + 1 }
      let t ← parseText s!"(! {← text i} :named {sym})"
      modify fun st => { st with named := st.named.insert i sym, memo := st.memo.insert i t }
  modify fun st => { st with prepared := st.prepared.insert i }

/-- Realize a node as a cvc5 term. -/
def node (i : Nat) : M Term := do
  prepare i
  if let some t := (← get).memo[i]? then return t
  let t ← parseText (← text i)
  if !(← get).arena.isOpen i then
    modify fun st => { st with memo := st.memo.insert i t }
  return t

/-- Declare `var` (an atom node) as a constant of the given sort text. -/
def declare (var : Nat) (sort : String) : M Term := do
  let some sym := (← get).arena.atom? var
    | throw (.error s!"expected an anchor variable atom, got node {var}")
  command s!"(declare-const {sym} {sort})"
  node var

/-- The elements of a `rare-list` node, if `i` is one. -/
def rareList? (a : Arena) (i : Nat) : Option (Array Nat) :=
  match a.get i with
  | .atom "rare-list" _ => some #[]
  | .list cs _ _ =>
    match cs[0]? >>= a.atom? with
    | some "rare-list" => some (cs.extract 1 cs.size)
    | _ => none
  | _ => none

def arg : Arg Nat → M (Arg Term)
  | .term t => do
    if let some ts := rareList? (← get).arena t then
      return .list (← ts.mapM node)
    return .term (← node t)
  | .list ts => return .list (← ts.mapM node)
  | .str s => return .str s
  | .assign x v t =>
    -- `forall_inst` assignments: the variable is bound by the quantifier, not declared
    return .assign x (← node v) (← node t)
  | .binder x s v => return .binder x s (← node v)

/-- Realize the arguments of an anchor, declaring the variables it introduces. -/
def anchorArgs (args : Array (Arg Nat)) : M (Array (Arg Term)) := do
  let mut out := #[]
  for a in args do
    match a with
    | .binder x sort v =>
      let c ← declare v sort.serialize
      out := out.push (.binder x sort c)
    | .assign x v t =>
      let t ← node t
      let c ← declare v (toString t.getSort!)
      out := out.push (.assign x c t)
    | .term t => out := out.push (.term (← node t))
    | .list ts => out := out.push (.list (← ts.mapM node))
    | .str s => out := out.push (.str s)
  return out

def stepData (s : StepData Nat) : M (StepData Term) :=
  return { s with cl := ← s.cl.mapM node, args := ← s.args.mapM arg }

partial def cmd : Command Nat → M (Command Term)
  | .assume id t => return .assume id (← node t)
  | .step s => return .step (← stepData s)
  | .anchor id args body close =>
    return .anchor id (← anchorArgs args) (← body.mapM cmd) (← stepData close)
  | .raw c => do
    command c.serialize
    return .raw c

def skippedCommands : List String :=
  ["check-sat", "check-sat-assuming", "get-model", "get-proof", "get-unsat-core", "get-value",
   "get-info", "get-option", "get-assertions", "get-assignment", "get-unsat-assumptions", "exit",
   "set-info", "set-option", "echo", "reset", "reset-assertions", "push", "pop"]

/-- Load the problem: declarations are executed, assertions are realized (not asserted), and the
    logic is replaced by `HO_ALL`. -/
def problem (cmds : List Sexp) (asserts : Array Nat) : M Problem := do
  -- higher-order: `lambda` (the body of a `choice`) is only parsed under HO logics
  command "(set-logic HO_ALL)"
  let mut prob : Problem := {}
  for c in cmds do
    match c with
    | .expr [.atom "set-logic", .atom l] =>
      prob := { prob with logic := some l }
    | .expr (.atom h :: _) =>
      if !skippedCommands.contains h then command c.serialize
    | _ => pure ()
  let asserts ← asserts.mapM node
  let st ← get
  return { prob with asserts, sorts := ← st.sm.getDeclaredSorts, funs := ← st.sm.getDeclaredTerms }

end Realize

/-- Realize a parsed proof against its problem. -/
def realize (r : Parser.Result) : cvc5.Env Realized := do
  let tm ← TermManager.new
  let solver ← Solver.new tm
  let parser ← InputParser.new solver
  let sm ← parser.getSymbolManager
  parser.setIncrementalStringInput .SMT_LIB_2_6 "alethe"
  let st : Realize.State := { parser, solver, sm, arena := r.arena }
  let ((problem, choices, proof), _) ← (do
      let p ← Realize.problem r.problemCmds r.asserts
      -- choice constants are declared before the proof's terms are realized
      let mut choices := #[]
      for (sym, sort, lam) in r.choices do
        Realize.command s!"(declare-const {sym} {sort.serialize})"
        let c ← Realize.parseText sym
        let l ← Realize.node lam
        choices := choices.push (c, l)
      let cmds ← r.proof.cmds.mapM Realize.cmd
      return (p, choices, ({ cmds } : Proof Term))).run st
  return { problem, proof, renamed := r.renamed, choices }

end Smt.Alethe
