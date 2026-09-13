/-
Copyright (c) 2021-2026 by the authors listed in the file AUTHORS and their
institutional affiliations. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Haniel Barbosa
-/

module

public import Smt.Data.Sexp
public import Std.Data.HashMap

@[expose] public section

/-!
# Alethe proof syntax

The abstract syntax of Alethe proofs, parametric in the representation `τ` of terms. The parser
produces proofs over arena node ids (`Nat`, see `Smt.Alethe.Arena`), and realization turns them
into proofs over `cvc5.Term`.
-/

namespace Smt.Alethe

/-- An argument of a step or an anchor. -/
inductive Arg (τ : Type) where
  /-- An ordinary term (also numerals, booleans, and indices). -/
  | term (t : τ)
  /-- A `(rare-list t₁ … tₙ)` argument (the bare atom `rare-list` is the empty list). -/
  | list (ts : Array τ)
  /-- A string literal such as `"eq-symm"` (without the quotes). -/
  | str (s : String)
  /-- An assignment `(:= x t)` or `(:= (x S) t)` in anchors and `forall_inst`. `var` is the
      variable `x` as a term (the parser renames anchor variables to fresh symbols). -/
  | assign (x : String) (var : τ) (t : τ)
  /-- A variable declaration `(x S)` in an anchor. `var` is `x` as a term. -/
  | binder (x : String) (sort : Sexp) (var : τ)
deriving Inhabited

/-- The data of a `step` command. -/
structure StepData (τ : Type) where
  id : String
  /-- The literals of the clause `(cl l₁ … lₙ)`. -/
  cl : Array τ
  rule : String
  premises : Array String := #[]
  args : Array (Arg τ) := #[]
  discharge : Array String := #[]
deriving Inhabited

/-- A proof command. Subproofs are folded into a tree: an `anchor` holds its body and the step
    that closes it. -/
inductive Command (τ : Type) where
  | assume (id : String) (t : τ)
  | step (s : StepData τ)
  | anchor (id : String) (args : Array (Arg τ)) (body : Array (Command τ)) (close : StepData τ)
  /-- A command forwarded verbatim to the SMT-LIB parser (`define-fun`, `declare-fun`, …). -/
  | raw (cmd : Sexp)
deriving Inhabited

structure Proof (τ : Type) where
  cmds : Array (Command τ)
deriving Inhabited

namespace Arg

def map (f : α → β) : Arg α → Arg β
  | .term t => .term (f t)
  | .list ts => .list (ts.map f)
  | .str s => .str s
  | .assign x v t => .assign x (f v) (f t)
  | .binder x s v => .binder x s (f v)

def mapM [Monad m] (f : α → m β) : Arg α → m (Arg β)
  | .term t => return .term (← f t)
  | .list ts => return .list (← ts.mapM f)
  | .str s => return .str s
  | .assign x v t => return .assign x (← f v) (← f t)
  | .binder x s v => return .binder x s (← f v)

end Arg

namespace StepData

def mapM [Monad m] (f : α → m β) (s : StepData α) : m (StepData β) :=
  return { s with cl := ← s.cl.mapM f, args := ← s.args.mapM (·.mapM f) }

end StepData

namespace Command

partial def mapM [Monad m] (f : α → m β) : Command α → m (Command β)
  | .assume id t => return .assume id (← f t)
  | .step s => return .step (← s.mapM f)
  | .anchor id args body close =>
    return .anchor id (← args.mapM (·.mapM f)) (← body.mapM (mapM f)) (← close.mapM f)
  | .raw c => return .raw c

/-- The number of `step` commands, including those of nested subproofs. -/
partial def numSteps : Command α → Nat
  | .step _ => 1
  | .anchor _ _ body _ => body.foldl (· + numSteps ·) 1
  | _ => 0

end Command

/-! ## Hash-consed term arena

Terms are stored as a DAG so that `let`-bound and `:named` terms can be substituted without
copying: the environment maps names to node ids. -/

/-- A node of the arena. -/
inductive Node where
  /-- An atom. `bound` marks a variable bound by an enclosing `forall`/`exists`/`choice`/`lambda`
      (a term where such an atom occurs *free* is open, and open terms are never named on the
      cvc5 side). -/
  | atom (s : String) (bound : Bool)
  /-- An S-expression list `(n₀ n₁ … nₖ)`. `isOpen` records whether a bound atom occurs free
      below (`Arena.free` has which); `size` is the tree size (for diagnostics). -/
  | list (children : Array Nat) (isOpen : Bool) (size : Nat)
deriving Inhabited, BEq

structure Arena where
  nodes : Array Node := #[]
  atoms : Std.HashMap (String × Bool) Nat := {}
  lists : Std.HashMap (Array Nat) Nat := {}
  /-- Number of parents of each node (how many list nodes have it as a child). -/
  refs : Array Nat := #[]
  /-- The bound atoms occurring free in each node: a binder form closes its own variables, so a
      quantified formula with no variable of an enclosing binder is closed, and can be shared by
      name on the cvc5 side like any other closed term. -/
  free : Array (Array Nat) := #[]
deriving Inhabited

namespace Arena

def get (a : Arena) (i : Nat) : Node := a.nodes[i]!

def isOpen (a : Arena) (i : Nat) : Bool :=
  match a.get i with
  | .atom _ b => b
  | .list _ o _ => o

def size (a : Arena) (i : Nat) : Nat :=
  match a.get i with
  | .atom _ _ => 1
  | .list _ _ s => s

def mkAtom (a : Arena) (s : String) (bound : Bool := false) : Arena × Nat :=
  match a.atoms[(s, bound)]? with
  | some i => (a, i)
  | none =>
    let i := a.nodes.size
    ({ a with nodes := a.nodes.push (.atom s bound), atoms := a.atoms.insert (s, bound) i,
              refs := a.refs.push 0, free := a.free.push (if bound then #[i] else #[]) }, i)

/-- The variables `(q ((x S) …) body)` binds, if the list is such a binder form. -/
def binderVars (a : Arena) (cs : Array Nat) : Option (Array Nat) := do
  guard (cs.size == 3)
  let .atom q false := a.get cs[0]! | none
  guard (q == "forall" || q == "exists" || q == "choice" || q == "lambda")
  let .list vs _ _ := a.get cs[1]! | none
  vs.mapM fun v => do
    let .list xs _ _ := a.get v | none
    guard (xs.size == 2)
    let .atom _ true := a.get xs[0]! | none
    return xs[0]!

def mkList (a : Arena) (cs : Array Nat) : Arena × Nat :=
  match a.lists[cs]? with
  | some i => (a, i)
  | none =>
    let i := a.nodes.size
    let free := cs.foldl (fun (acc : Array Nat) c => acc ++ a.free[c]!.filter (!acc.contains ·)) #[]
    let free := match a.binderVars cs with
      | some vs => free.filter (!vs.contains ·)
      | none => free
    let isOpen := !free.isEmpty
    let size := cs.foldl (fun n c => n + a.size c) 1
    let refs := cs.foldl (fun rs c => rs.modify c (· + 1)) a.refs
    ({ a with nodes := a.nodes.push (.list cs isOpen size), lists := a.lists.insert cs i,
              refs := refs.push 0, free := a.free.push free }, i)

/-- Serialize a node as a tree (exponential on heavily shared DAGs; use only for small terms and
    diagnostics). -/
partial def serialize (a : Arena) (i : Nat) : String :=
  match a.get i with
  | .atom s _ => s
  | .list cs _ _ => "(" ++ " ".intercalate (cs.toList.map a.serialize) ++ ")"

/-- The atom text of a node, if it is an atom. -/
def atom? (a : Arena) (i : Nat) : Option String :=
  match a.get i with
  | .atom s _ => some s
  | _ => none

/-- The children of a node, if it is a list. -/
def children? (a : Arena) (i : Nat) : Option (Array Nat) :=
  match a.get i with
  | .list cs _ _ => some cs
  | _ => none

end Arena

end Smt.Alethe
