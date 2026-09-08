/-
Copyright (c) 2021-2026 by the authors listed in the file AUTHORS and their
institutional affiliations. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Haniel Barbosa
-/

module

public import Smt.Tactic.Smt
public meta import Smt.Tactic.Smt
public import Smt.Alethe.Frontend
public meta import Smt.Alethe.Frontend
public import Smt.Alethe.Rare.Rules
public meta import Smt.Alethe.Rare.Rules

/-!
# The `alethe` tactic

Like `smt`, but the proof travels through the Alethe format: cvc5 prints its proof in Alethe,
Carcara elaborates it (external process, `smt.alethe.carcara`), and the elaborated proof is
checked by the Alethe checker against the same query, with the goal's variables as the problem's
symbols. Steps the checker cannot reconstruct are returned as goals.
-/

public meta section

namespace Smt.Alethe

open Lean Elab Tactic Qq
open Smt Translate Query Reconstruct Util

register_option smt.alethe.carcara : String := {
  defValue := ""
  descr := "the Carcara executable used by the `alethe` tactic (default: `$CARCARA`, else `carcara` in the PATH)"
}

register_option smt.alethe.rareFile : String := {
  defValue := ""
  descr := "the RARE rule file handed to Carcara by the `alethe` tactic (default: the file the checker's rule table was generated from)"
}

register_option smt.alethe.pipeline : String := {
  defValue := "polyeq local core-simp-rare"
  descr := "the Carcara elaboration pipeline of the `alethe` tactic"
}

register_option smt.alethe.coreRules : String := {
  defValue := "ite_simplify eq_simplify not_simplify implies_simplify equiv_simplify bool_simplify comp_simplify and_simplify or_simplify prod_simplify sum_simplify minus_simplify unary_minus_simplify div_simplify"
  descr := "the rules Carcara's core pass reduces in the `alethe` tactic (`--core-rules`)"
}

register_option smt.alethe.cvc5 : String := {
  defValue := ""
  descr := "a cvc5 executable to run instead of the in-process solver (its Alethe printer is used as is; the in-process cvc5 is the 1.3.2 build of lean-cvc5)"
}

register_option smt.alethe.keepFiles : Bool := {
  defValue := false
  descr := "keep the temporary problem and proof files of the `alethe` tactic (paths in the `smt.alethe` trace)"
}

/-- cvc5 options for Alethe proofs, on top of `defaultSolverOptions`. -/
def aletheSolverOptions : List (String × String) := [
  ("produce-proofs", "true"),
  ("proof-format-mode", "alethe"),
  ("proof-alethe-define-skolems", "true"),
  ("symmetry-breaker", "false"),
]

inductive SolveResult where
  | unsat (proof : String)
  | sat
  | unknown (reason : String)

/-- Run cvc5 on the query and return its Alethe proof. -/
def solveAlethe (query : String) (timeout : Option Nat) (options : List (String × String)) :
    MetaM (Except cvc5.Error SolveResult) :=
  withTraceNode `smt.alethe (fun _ => pure m!"cvc5") do cvc5.run do
    let tm ← cvc5.TermManager.new
    let slv ← cvc5.Solver.new tm
    if let some t := timeout then
      slv.setOption "tlimit-per" (toString (1000 * t))
    for (opt, val) in options do
      slv.setOption opt val
    let _ ← runQuery slv query
    let res ← slv.checkSat
    if res.isUnsat then
      let ps ← slv.getProof
      if h : 0 < ps.size then
        return .unsat (← slv.proofToString ps[0] .ALETHE)
      return .unknown "cvc5 produced no proof"
    else if res.isSat then
      return .sat
    else
      return .unknown res.getUnknownExplanation.toString

/-- Run an external cvc5 on the query with the same options as the in-process solver (as command
    line flags) and `--dump-proofs`. -/
def solveAletheExternal (exe : String) (query : String) (timeout : Option Nat)
    (options : List (String × String)) : MetaM SolveResult := do
  let (h, path) ← IO.FS.createTempFile
  h.putStr (query ++ "\n(check-sat)\n"); h.flush
  let flag : String × String → String
    | (o, "true") => s!"--{o}"
    | (o, "false") => s!"--no-{o}"
    | (o, v) => s!"--{o}={v}"
  let args := #["--dump-proofs"] ++ options.toArray.map flag
    ++ (match timeout with | some t => #[s!"--tlimit={1000 * t}"] | none => #[]) ++ #[path.toString]
  trace[smt.alethe] "{exe} {args}"
  let out ← try IO.Process.output { cmd := exe, args } catch e =>
    throwError "could not run cvc5 (`{exe}`): {e.toMessageData}"
  unless smt.alethe.keepFiles.get (← getOptions) do IO.FS.removeFile path
  let lines := out.stdout.splitOn "\n"
  match lines[0]? with
  | some "unsat" => return .unsat ("\n".intercalate (lines.drop 1))
  | some "sat" => return .sat
  | some "unknown" => return .unknown out.stderr
  | _ =>
    -- a resource limit aborts cvc5 (exit code 134) with a message on stderr
    if (out.stderr.splitOn "interrupted by timeout").length > 1 then return .unknown "TIMEOUT"
    throwError "cvc5 failed (exit code {out.exitCode}):\n{out.stdout}\n{out.stderr}"

/-- The Alethe printer of the cvc5 build lean-cvc5 ships (1.3.2) predates part of the current
    Alethe vocabulary: it prints some rules as `rare_rewrite`s of rules that do not exist
    (`arith-poly-norm`, `evaluate`, `distinct_bin_bool_elim`) and others as holes named by the
    internal rule (`ARITH_POLY_NORM_REL`, `ACI_NORM`). Rename them to what current cvc5 prints,
    so that Carcara and the checker see rules they know. -/
def compatProof (proof : String) : String :=
  -- `rare_rewrite` steps whose "rule" is another Alethe rule (no arguments)
  let rules : List (String × String) :=
    [("arith-poly-norm", "poly_simp"), ("evaluate", "evaluate")]
  -- RARE rules under an older name
  let rares : List (String × String) := [("distinct_bin_bool_elim", "distinct-binary-elim")]
  -- holes standing for an Alethe rule (the hole's arguments are dropped)
  let holes : List (String × String) := [("ARITH_POLY_NORM_REL", "poly_simp_rel"), ("ACI_NORM", "aci_simp")]
  let fixLine (line : String) : String := Id.run do
    let mut line := line
    for (old, new) in rules do
      line := line.replace s!":rule rare_rewrite :args (\"{old}\")" s!":rule {new}"
    for (old, new) in rares do
      line := line.replace s!":rule rare_rewrite :args (\"{old}\"" s!":rule rare_rewrite :args (\"{new}\""
    for (name, rule) in holes do
      if let [pre, _] := line.splitOn s!" :args (\"{name}\"" then
        line := pre.replace ":rule hole" s!":rule {rule}" ++ ")"
    -- an anonymous hole `(cl (ite c (= (ite c a b) a) (= (ite c a b) b)))` is the `ite-eq` lemma,
    -- which current cvc5 prints as the RARE rule `ite-eq` (concluding `(= … true)`)
    if line.endsWith ":rule hole)" then
      if let .ok [.expr [.atom "step", .atom id, .expr [.atom "cl", lit], .atom ":rule", .atom "hole"]] :=
          Sexp.Parser.manySexps!.run line then
        if let .expr [.atom "ite", c, .expr [.atom "=", .expr [.atom "ite", c₁, a, b], a'],
                      .expr [.atom "=", .expr [.atom "ite", c₂, a₂, b₂], b']] := lit then
          if c == c₁ && c == c₂ && a == a' && a == a₂ && b == b' && b == b₂ then
            return "\n".intercalate [
              s!"(step {id}.ite (cl (= {lit} true)) :rule rare_rewrite :args (\"ite-eq\" {c} {a} {b}))",
              s!"(step {id}.pos (cl (not (= {lit} true)) {lit} (not true)) :rule equiv_pos1)",
              s!"(step {id}.true (cl true) :rule true)",
              s!"(step {id} (cl {lit}) :rule resolution :premises ({id}.pos {id}.ite {id}.true))"]
    return line
  "\n".intercalate ((proof.splitOn "\n").map fixLine)

/-- Elaborate cvc5's proof with Carcara; returns the elaborated proof text. -/
def runCarcara (problem proof : String) : MetaM String := do
  let opts ← getOptions
  let exe ← match smt.alethe.carcara.get opts with
    | "" => do pure ((← IO.getEnv "CARCARA").getD "carcara")
    | p => pure p
  let (hp, problemPath) ← IO.FS.createTempFile
  hp.putStr problem; hp.flush
  let (hf, proofPath) ← IO.FS.createTempFile
  hf.putStr proof; hf.flush
  let mut rare := smt.alethe.rareFile.get opts
  let mut rarePath : Option System.FilePath := none
  if rare == "" then
    let (hr, p) ← IO.FS.createTempFile
    hr.putStr Rare.ruleFileText; hr.flush
    rare := p.toString
    rarePath := some p
  trace[smt.alethe] "problem: {problemPath}\nproof: {proofPath}"
  let words (s : String) := (s.splitOn " ").filter (· ≠ "") |>.toArray
  let coreRules := words (smt.alethe.coreRules.get opts)
  let args := #["elaborate", "--expand-let-bindings", "--allow-int-real-subtyping", "--rare-file", rare,
                "--pipeline"] ++ words (smt.alethe.pipeline.get opts)
    ++ (if coreRules.isEmpty then #[] else #["--core-rules"] ++ coreRules)
    ++ #["--", proofPath.toString, problemPath.toString]
  let out ← try IO.Process.output { cmd := exe, args } catch e =>
    throwError "could not run Carcara (`{exe}`): {e.toMessageData}\nSet `smt.alethe.carcara` or `$CARCARA`."
  unless smt.alethe.keepFiles.get opts do
    IO.FS.removeFile problemPath
    IO.FS.removeFile proofPath
    if let some p := rarePath then IO.FS.removeFile p
  if out.exitCode != 0 then
    throwError "Carcara failed (exit code {out.exitCode}):\n{out.stderr}"
  let verdict := (out.stdout.splitOn "\n")[0]!
  -- `holey`: cvc5 left holes Carcara could not fill; the checker returns them as goals
  if verdict != "valid" && verdict != "holey" then
    throwError "Carcara does not accept cvc5's proof: {verdict}\n{out.stderr}"
  return "\n".intercalate ((out.stdout.splitOn "\n").drop 1)

/-- The `alethe` tactic: preprocess and translate the goal as `smt` does, prove it with cvc5,
    elaborate the Alethe proof with Carcara and check it. -/
def alethe (cfg : Config) (mv : MVarId) (hs : Array Expr) : MetaM Result := mv.withContext do
  let goalType : Q(Prop) ← mv.getType
  let mv₀ := (← Meta.mkFreshExprMVar (← mv.getType)).mvarId!
  let mv₀ ← mv₀.cleanup (← hs.foldlM (fun s h => return (← (Expr.collectFVars h).run s).snd) {}).fvarIds
  mv₀.withContext do
  let steps := if cfg.mono then #[Preprocess.mono] else #[Preprocess.pushHintsToCtx] ++
              (if cfg.intros then #[Preprocess.intros] else #[]) ++ #[Preprocess.negateGoal]
  let steps := if cfg.normalize then steps.push Preprocess.normalize else steps
  let steps := if cfg.embeddings then steps.push Preprocess.embedding else steps
  let ⟨_, hs₁, mv₁⟩ ← Preprocess.applySteps mv₀ hs steps
  mv₁.withContext do
  let (fvNames₁, fvNames₂) ← genUniqueFVarNames
  let cmds ← prepareSmtQuery hs₁.toList fvNames₁
  let cmds := .setLogic "ALL" :: cmds
  let query := Command.cmdsAsQuery cmds
  if cfg.showQuery then
    mv.withContext do logInfo m!"goal: {goalType}\n\nquery:\n{query}"
    return .unsat [mv] hs₁
  trace[smt.alethe] "goal: {goalType}\nquery:\n{query}"
  let options := defaultSolverOptions ++ aletheSolverOptions ++ cfg.extraSolverOptions
  let external := smt.alethe.cvc5.get (← getOptions)
  let res ← if external == "" then
      match ← solveAlethe query cfg.timeout options with
      | .error e => throwError e.toString
      | .ok r => pure r
    else
      solveAletheExternal external query cfg.timeout options
  match res with
  | .sat => return .sat none
  | .unknown r => return .unknown r
  | .unsat proofText =>
    trace[smt.alethe] "cvc5 proof:\n{proofText}"
    -- cvc5 prints `(error "…")` when its proof cannot be expressed in Alethe
    if let [_, second] := ((proofText.splitOn "\n").filter (· ≠ "")).take 2 then
      if second.startsWith "(error " then
        throwError "cvc5 cannot print this proof in Alethe: {second}"
    -- the shim is for the in-process 1.3.2 printer only
    let proofText := if external == "" then compatProof proofText else proofText
    let elaborated ← runCarcara query proofText
    trace[smt.alethe] "elaborated proof:\n{elaborated}"
    let ctx : Reconstruct.Context := { userNames := fvNames₂, native := cfg.native }
    let (r, mvs) ← reconstructAletheText query elaborated ctx
    trace[smt.alethe] "{r.stats.summary}"
    for (id, rule, m) in r.stats.failures do
      trace[smt.alethe] "trusted {id} ({rule}): {m}"
    let some hp := r.proof | throwError "the Alethe proof does not derive the empty clause"
    let mv₂ ← mv₁.assert (← mkFreshId) r.type hp
    let ⟨_, mv₃⟩ ← mv₂.intro1
    let gs ← mv₃.apply (← Meta.mkAppOptM ``Prop.implies_false_of_not_and #[listExpr r.asserts q(Prop)])
    mv₃.withContext (gs.forM (·.assumption))
    mv.assign (.mvar mv₀)
    return .unsat mvs hs₁

namespace Tactic

open Smt.Tactic

/-- `alethe` proves the goal like `smt`, but through the Alethe format: cvc5's Alethe proof is
    elaborated by Carcara and checked by the Alethe checker. Takes the same configuration and
    hints as `smt`. Carcara is found through `smt.alethe.carcara`, `$CARCARA`, or the PATH. -/
syntax (name := alethe) "alethe " optConfig smtHints : tactic

@[tactic alethe] def evalAlethe : Lean.Elab.Tactic.Tactic := fun stx => match stx with
  | `(tactic| alethe $cfg:optConfig $hs:smtHints) => withMainContext do
    let cfg ← elabConfig cfg
    let mv ← getMainGoal
    let (_, hs) ← elabHints hs
    match ← Smt.Alethe.alethe cfg mv hs with
    | .unsat mvs _ => replaceMainGoal mvs
    | .sat _ => throwError "unable to prove goal, either it is false or you need to provide more facts."
    | .unknown r => throwError "unable to prove goal. Try providing more hints. Reason: {r}"
  | _ => throwUnsupportedSyntax

end Tactic

end Smt.Alethe
