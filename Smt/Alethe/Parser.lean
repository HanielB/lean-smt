/-
Copyright (c) 2021-2026 by the authors listed in the file AUTHORS and their
institutional affiliations. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Haniel Barbosa
-/

module

public import Smt.Alethe.Syntax

@[expose] public section

/-!
# Alethe parser

Turns the S-expressions of an Alethe proof into a `Proof Nat` over a hash-consed `Arena`.

Binding constructs are eliminated here, all through one environment:
* `(let ((x t) …) body)` — parallel `let`, scoped, shadowing respected;
* `(! t :named n)` — the annotation is stripped and `n ↦ t` is recorded from that point on;
* anchor variables `(x S)` and `(:= x t)` — renamed to globally fresh symbols inside the block.

Contexts follow the semantics of "Scalable Fine-Grained Proofs for Formula Processing" (and of
Carcara): the substitution of the context applies to the left-hand side of a step's equality
only. Each context therefore carries two environments, the *substituted* one (`vars`, with the
`(:= x t)` renamings, cumulative and shadowing) and the *fixed* one (`fixed`, the enclosing
environment plus the context's `(x S)` variables). A unit clause `(= l r)` parses `l` under the
first and `r` under the second; they coincide wherever no substitution is in scope. A term named
with `:named` is resolved anew under each environment it is used in, since the same shared term
can mean different variables on the two sides.

Since terms are arena nodes, substitution never copies a term. Numerals that are not SMT-LIB
syntax (`-1`, `1/2`) are normalized to applications.
-/

namespace Smt.Alethe.Parser

/-- Binding environment: `some n` substitutes the node `n`; `none` marks a name shadowed by a
    quantifier binder (so that named terms and `let`s of the same name do not apply). -/
structure Env where
  vars : Std.HashMap String (Option Nat) := {}
  /-- The environment of right-hand sides: the context's variables without its substitutions. -/
  fixed : Std.HashMap String (Option Nat) := {}
  /-- Identities of the two environments, keys of the `:named` resolution cache. -/
  id : Nat := 0
  fixedId : Nat := 0

/-- The environment for the right-hand side of a judgment. -/
def Env.rhs (env : Env) : Env :=
  { vars := env.fixed, fixed := env.fixed, id := env.fixedId, fixedId := env.fixedId }

structure State where
  arena : Arena := {}
  /-- Global table of `:named` terms (name ↦ its S-expression). -/
  named : Std.HashMap String Sexp := {}
  /-- Resolutions of named terms per environment (name, environment id ↦ node). -/
  namedCache : Std.HashMap (String × Nat) Nat := {}
  /-- Environment identities handed out so far (`0` is the top level). -/
  envs : Nat := 0
  /-- Anchor variables renamed so far (fresh symbol ↦ original name). -/
  renamed : Array (String × String) := #[]
  fresh : Nat := 0
  /-- `define-fun`s of the problem: parameter names and body (parameters are bound atoms). -/
  defs : Std.HashMap String (Array String × Nat) := {}
  /-- The epsilon symbols introduced for `choice` terms, per sort: symbol and sort. -/
  choices : Array (String × Sexp) := #[]
  choiceOfSort : Std.HashMap String String := {}
  /-- The logic has reals but no integers: integer numerals denote reals, as cvc5's and Carcara's
      parsers read them (the realization parses under `HO_ALL`, where they would be integers). -/
  realNumerals : Bool := false

abbrev M := StateT State (Except String)

def throw' (msg : String) : M α := throw msg

def mkAtom (s : String) (bound := false) : M Nat :=
  modifyGet fun st =>
    let (a, i) := st.arena.mkAtom s bound
    (i, { st with arena := a })

def mkList (cs : Array Nat) : M Nat :=
  modifyGet fun st =>
    let (a, i) := st.arena.mkList cs
    (i, { st with arena := a })

def isDigits (s : String) : Bool :=
  !s.isEmpty && s.all Char.isDigit

def isDecimal (s : String) : Bool :=
  match s.splitOn "." with
  | [a, b] => isDigits a && isDigits b
  | _ => false

/-- A fresh legal SMT-LIB symbol derived from `x` (quoted symbols stay quoted). -/
def freshSymbol (x : String) : M String := do
  let k ← modifyGet fun st => (st.fresh, { st with fresh := st.fresh + 1 })
  let sym := if x.startsWith "|" && x.endsWith "|" && x.length ≥ 2 then
      (x.dropEnd 1).toString ++ s!"!{k}|"
    else
      s!"{x}!{k}"
  modify fun st => { st with renamed := st.renamed.push (sym, x) }
  return sym

/-- Normalize a numeral atom that is not SMT-LIB syntax: `-5` ↦ `(- 5)`, `1/2` ↦ `(/ 1 2)`,
    `-1/2` ↦ `(/ (- 1) 2)`. Returns `none` for other atoms. -/
def numeral? (s : String) : M (Option Nat) := do
  let neg := s.startsWith "-"
  let body := if neg then (s.drop 1).toString else s
  let mkNum (t : String) : M Nat := do
    let n ← mkAtom (if (← get).realNumerals && isDigits t then t ++ ".0" else t)
    if neg then mkList #[← mkAtom "-", n] else return n
  match body.splitOn "/" with
  | [a, b] =>
    if isDigits a && isDigits b then
      return some (← mkList #[← mkAtom "/", ← mkNum a, ← mkAtom b])
    return none
  | [a] =>
    if neg && (isDigits a || isDecimal a) then return some (← mkNum a)
    return none
  | _ => return none

def freshEnvId : M Nat :=
  modifyGet fun st => (st.envs + 1, { st with envs := st.envs + 1 })

def binderKeywords : List String := ["forall", "exists", "choice", "lambda"]

/-- Replace the bound atoms named in `m` inside node `i` (memoized over the DAG). -/
partial def substBound (m : Std.HashMap String Nat) (i : Nat) : StateT (Std.HashMap Nat Nat) M Nat := do
  if let some j := (← get)[i]? then return j
  let a := (← getThe State).arena
  let j ← match a.get i with
    | .atom x true => pure (m.getD x i)
    | .atom _ false => pure i
    | .list _ false _ => pure i
    | .list cs true _ => do
      let cs' ← cs.mapM (substBound m)
      if cs' == cs then pure i else liftM (mkList cs')
  modify (·.insert i j)
  return j

/-- Instantiate the body of a function definition. -/
def instantiate (params : Array String) (args : Array Nat) (body : Nat) : M Nat := do
  if params.size != args.size then throw' s!"wrong number of arguments for a defined function"
  let m := (params.zip args).foldl (fun m (x, a) => m.insert x a) {}
  (substBound m body).run' {}

/-- Turn a term into an arena node under the binding environment. -/
partial def term (env : Env) : Sexp → M Nat
  | .atom s => do
    match env.vars[s]? with
    | some (some n) => return n
    | some none => mkAtom s (bound := true)
    | none =>
      if let some n := (← get).namedCache[(s, env.id)]? then return n
      if let some t := (← get).named[s]? then
        let n ← term env t
        modify fun st => { st with namedCache := st.namedCache.insert (s, env.id) n }
        return n
      if let some (ps, body) := (← get).defs[s]? then
        if ps.isEmpty then return body
      if let some n ← numeral? s then return n
      if (← get).realNumerals && isDigits s then return ← mkAtom (s ++ ".0")
      mkAtom s
  | .expr [] => mkList #[]
  | .expr (.atom "!" :: t :: attrs) => do
    let n ← term env t
    let rec go : List Sexp → M Unit
      | .atom ":named" :: .atom name :: rest => do
        modify fun st => { st with named := st.named.insert name t,
                                   namedCache := st.namedCache.insert (name, env.id) n }
        go rest
      | _ :: rest => go rest
      | [] => return ()
    go attrs
    return n
  | .expr [.atom "let", .expr bindings, body] => do
    let mut env' := env
    for b in bindings do
      match b with
      | .expr [.atom x, t] => env' := { env' with vars := env'.vars.insert x (some (← term env t)) }
      | _ => throw' s!"ill-formed let binding {b}"
    term env' body
  | .expr [.atom "choice", .expr [.expr [.atom x, sort]], body] => do
    -- `(choice ((x S)) φ)` becomes `(ε_S (lambda ((x S)) φ))` for a higher-order symbol `ε_S`
    -- whose meaning (`Classical.epsilon`) is attached at reconstruction; this works for open
    -- choices too, the bound variables being those of the lambda
    let key := sort.serialize
    let sym ← match (← get).choiceOfSort[key]? with
      | some sym => pure sym
      | none =>
        let sym ← freshSymbol "choice"
        modify fun st => { st with choices := st.choices.push (sym, sort),
                                   choiceOfSort := st.choiceOfSort.insert key sym }
        pure sym
    let lam ← term env (.expr [.atom "lambda", .expr [.expr [.atom x, sort]], body])
    mkList #[← mkAtom sym, lam]
  | .expr [.atom b, .expr vars, body] => do
    if binderKeywords.contains b then
      let mut env' := env
      let mut varNodes := #[]
      for v in vars do
        match v with
        | .expr [.atom x, sort] =>
          env' := { env' with vars := env'.vars.insert x none }
          varNodes := varNodes.push (← mkList #[← mkAtom x (bound := true), ← term {} sort])
        | _ => throw' s!"ill-formed bound variable {v}"
      mkList #[← mkAtom b, ← mkList varNodes, ← term env' body]
    else
      mkList #[← mkAtom b, ← term env (.expr vars), ← term env body]
  | .expr (.atom f :: args) => do
    if !env.vars.contains f then
      if let some (ps, body) := (← get).defs[f]? then
        if !ps.isEmpty then
          return ← instantiate ps (← args.toArray.mapM (term env)) body
    mkList (← (Sexp.atom f :: args).toArray.mapM (term env))
  | .expr items => do
    mkList (← items.toArray.mapM (term env))

def isStrLit (s : String) : Bool :=
  s.length ≥ 2 && s.startsWith "\"" && s.endsWith "\""

/-- Parse an argument of a `step`. RARE lists (`rare-list`, `(rare-list t₁ … tₙ)`) stay ordinary
    arena nodes here (they can be `:named`); realization turns them into `Arg.list`. -/
def stepArg (env : Env) : Sexp → M (Arg Nat)
  | .atom s => do
    if isStrLit s then return .str ((s.drop 1).dropEnd 1).toString
    -- a bare numeral argument is an index or a coefficient, never a real of the problem
    if isDigits s then return .term (← mkAtom s)
    return .term (← term env (.atom s))
  | .expr [.atom ":=", .atom x, t] => do
    return .assign x (← term env (.atom x)) (← term env t)
  | .expr [.atom ":=", .expr [.atom x, _], t] => do
    return .assign x (← term env (.atom x)) (← term env t)
  | s => do return .term (← term env s)

/-- Parse the arguments of an `anchor`, renaming the variables it introduces. Returns the
    environment for the subproof body. -/
def anchorArgs (env : Env) (args : List Sexp) : M (Env × Array (Arg Nat)) := do
  let mut env := { env with id := ← freshEnvId, fixedId := ← freshEnvId }
  let mut out := #[]
  for a in args do
    match a with
    | .expr [.atom x, sort] =>
      -- a variable of the context: the same on both sides
      let sym ← freshSymbol x
      let v ← mkAtom sym
      env := { env with vars := env.vars.insert x (some v), fixed := env.fixed.insert x (some v) }
      out := out.push (.binder x sort v)
    | .expr [.atom ":=", .atom x, t] | .expr [.atom ":=", .expr [.atom x, _], t] =>
      -- a substitution: `t` under the enclosing substitution, `x` replaced on left-hand sides
      -- only (on right-hand sides it keeps its enclosing meaning)
      let t ← term env t
      if env.fixed[x]? == some (some t) then
        -- `(:= x x)` for the context's own variable `x`: the identity, no renaming needed (veriT
        -- writes every `bind` this way)
        env := { env with vars := env.vars.insert x (some t) }
        continue
      let sym ← freshSymbol x
      let v ← mkAtom sym
      -- a right-hand side that mentions `x` although nothing encloses it can only mean the
      -- replaced variable; resolve it to the substitution rather than to an unknown symbol
      let fixed := if env.fixed.contains x then env.fixed else env.fixed.insert x (some v)
      env := { env with vars := env.vars.insert x (some v), fixed }
      out := out.push (.assign x v t)
    | _ => throw' s!"ill-formed anchor argument {a}"
  return (env, out)

def asList : Sexp → List Sexp
  | .expr xs => xs
  | s => [s]

def ids : Sexp → M (Array String)
  | .expr xs => xs.toArray.mapM fun
    | .atom id => pure id
    | s => throw' s!"expected an identifier, got {s}"
  | s => throw' s!"expected a list of identifiers, got {s}"

/-- Parse `(step id (cl …) :rule r [:premises (…)] [:args (…)] [:discharge (…)])`. -/
def step (env : Env) : List Sexp → M (StepData Nat)
  | .atom id :: .expr (.atom "cl" :: lits) :: rest => do
    let cl ← match lits with
      -- a judgment `Γ ▷ l ≃ r`: the context's substitution applies to `l` only
      | [.expr [.atom "=", l, r]] => do
        pure #[← mkList #[← mkAtom "=", ← term env l, ← term env.rhs r]]
      | _ => lits.toArray.mapM (term env)
    let mut s : StepData Nat := { id, cl, rule := "" }
    -- keyword arguments in any order
    let mut rest := rest
    while !rest.isEmpty do
      match rest with
      | .atom ":rule" :: .atom r :: rest' =>
        s := { s with rule := r }; rest := rest'
      | .atom ":premises" :: ps :: rest' =>
        s := { s with premises := ← ids ps }; rest := rest'
      | .atom ":discharge" :: ps :: rest' =>
        s := { s with discharge := ← ids ps }; rest := rest'
      | .atom ":args" :: .expr as :: rest' =>
        s := { s with args := ← as.toArray.mapM (stepArg env) }; rest := rest'
      | x :: _ => throw' s!"unexpected token {x} in step {id}"
      | [] => pure ()
    if s.rule.isEmpty then throw' s!"step {id} has no rule"
    return s
  | xs => throw' s!"ill-formed step {Sexp.expr xs}"

/-- Record a `define-fun`: it is expanded wherever it is used afterwards. -/
def defineFun (f : String) (params : List Sexp) (body : Sexp) : M Unit := do
  let mut ps := #[]
  let mut env : Env := {}
  for p in params do
    match p with
    | .expr [.atom x, _] =>
      ps := ps.push x
      env := { env with vars := env.vars.insert x none }
    | _ => throw' s!"ill-formed parameter {p} in the definition of {f}"
  let b ← term env body
  modify fun st => { st with defs := st.defs.insert f (ps, b) }

/-- Parse a sequence of commands until the list is exhausted or the step closing the current
    anchor (`close?`) is reached; that step is left in the returned remainder. -/
partial def commands (env : Env) (close? : Option String) (cmds : List Sexp) :
    M (Array (Command Nat) × List Sexp) := do
  let mut out := #[]
  let mut rest := cmds
  while true do
    match rest with
    | [] => break
    | c :: rest' =>
      match c with
      | .expr (.atom "step" :: .atom id :: _) =>
        if close? == some id then break
        out := out.push (.step (← step env (asList c |>.drop 1)))
        rest := rest'
      | .expr [.atom "assume", .atom id, t] =>
        out := out.push (.assume id (← term env t))
        rest := rest'
      | .expr (.atom "anchor" :: .atom ":step" :: .atom id :: more) =>
        let args ← match more with
          | [] => pure []
          | [.atom ":args", .expr as] => pure as
          | _ => throw' s!"ill-formed anchor {c}"
        let (env', args) ← anchorArgs env args
        let (body, rest'') ← commands env' (some id) rest'
        match rest'' with
        | closing :: rest''' =>
          let close ← step env (asList closing |>.drop 1)
          out := out.push (.anchor id args body close)
          rest := rest'''
        | [] => throw' s!"anchor {id} is never closed"
      | .expr [.atom "define-fun", .atom f, .expr params, _, body] =>
        -- skolem definitions (`--proof-alethe-define-skolems`): expanded like the problem's
        defineFun f params body
        rest := rest'
      | .expr (.atom _ :: _) =>
        out := out.push (.raw c)
        rest := rest'
      | _ => throw' s!"unexpected command {c}"
  return (out, rest)

/-- Parse the problem: `define-fun`s are recorded (and expanded wherever they are used, in the
    problem and in the proof), `assert`ions become arena nodes, and the remaining commands are
    returned for the SMT-LIB parser. -/
def problem (cmds : List Sexp) : M (List Sexp × Array Nat) := do
  let mut forwarded := #[]
  let mut asserts := #[]
  for c in cmds do
    match c with
    | .expr [.atom "define-fun", .atom f, .expr params, _, body] => defineFun f params body
    | .expr [.atom "assert", t] =>
      asserts := asserts.push (← term {} t)
    | .expr [.atom "set-logic", .atom l] =>
      -- real arithmetic without integers: `20` is the real `20.0`
      let real := (l.splitOn "RA").length > 1 || (l.splitOn "RDL").length > 1
      let int := (l.splitOn "IA").length > 1 || (l.splitOn "IDL").length > 1 || (l.splitOn "IRA").length > 1
      modify fun st => { st with realNumerals := real && !int }
      forwarded := forwarded.push c
    | _ => forwarded := forwarded.push c
  return (forwarded.toList, asserts)

structure Result where
  arena : Arena
  /-- The problem's commands other than `assert` and `define-fun`. -/
  problemCmds : List Sexp
  /-- The problem's assertions. -/
  asserts : Array Nat
  proof : Proof Nat
  /-- Fresh anchor-variable symbols and their original names. -/
  renamed : Array (String × String)
  /-- The epsilon symbols introduced for `choice` terms: symbol and sort. -/
  choices : Array (String × Sexp)

/-- Parse a problem and a proof. A single outer pair of parentheses around the proof is
    tolerated. -/
def parse (problemSexps proofSexps : List Sexp) : Except String Result := do
  let proofSexps := match proofSexps with
    | [.expr (c@(.expr (.atom _ :: _)) :: cs)] => c :: cs
    | _ => proofSexps
  let (((problemCmds, asserts), (cmds, rest)), st) ← (do
      let p ← problem problemSexps
      let c ← commands {} none proofSexps
      return (p, c)).run {}
  if !rest.isEmpty then throw s!"unexpected trailing command {rest.head!}"
  return { arena := st.arena, problemCmds, asserts, proof := { cmds }, renamed := st.renamed,
           choices := st.choices }

end Smt.Alethe.Parser
