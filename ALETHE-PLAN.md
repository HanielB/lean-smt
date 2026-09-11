# Alethe proof checking in lean-smt

## Context

lean-smt checks cvc5 proofs only through cvc5's in-process API `Proof` object (the `smt`
tactic; lean-cpc-checker reuses that path for CPC by running cvc5 in-process and walking
`Proof` nodes). There is no path from a *textual* proof to a Lean theorem.

Goal: check **Alethe** proofs produced by cvc5 and elaborated by Carcara
(`~/carcara/wt-diff`, branch `bv-fixes`) with the canonicalizing pipeline
`--pipeline polyeq local`, by defining Alethe proof rules inside lean-smt and reusing its
term reconstruction, clause machinery, lemma libraries and arithmetic tactics. Order:
QF_UF → QF_LIA / QF_LRA / QF_UFLIA → quantifiers (UF, UFLIA). Rules that are
disproportionately hard in Lean are delegated, per rule, to Carcara's `core` reductions.
Work happens on a small local sample first; every experiment is memory- and time-gated
(30 GB box with 12 GB in use, 8 cores).

Decisions taken with the user:
- Terms are parsed by **cvc5's parser through lean-cvc5** (`InputParser.nextCommand` /
  `nextTerm`), so `Smt.Reconstruct.reconstructTerm` / `reconstructSort` are reused unchanged.
  TCB = Lean kernel + cvc5 parser for the statement (same as lean-cpc-checker).
- Local development builds use the **`no_mathlib` lakefile** (only `lakefile.lean` and
  `lake-manifest.json` differ from `main`; the `Smt/` tree is byte-identical).
- SMT `Real` is carried by **`Rat`** (`Smt.Rat`); import exactly one of `Smt.Rat`/`Smt.Real`.

## Verified facts that shape the design

lean-smt (`~/lean/lean-smt`, `main` @ 76b4eea, Lean v4.33.0, never built on this machine):
- `ReconstructM := ReaderT Reconstruct.Context (StateT Reconstruct.State MetaM)`;
  `Context.userNames : HashMap String Expr`, `State.termCache : HashMap cvc5.Term Expr`,
  `currAssums`, `skippedGoals` (`Smt/Reconstruct.lean:31-48`).
- Handler lookup `getReconstructors` uses `evalConst` (`Smt/Reconstruct.lean:61-72`) → an
  executable needs `supportInterpreter := true` no matter what.
- `addThm type val` does not check `val` against `type`; only the final kernel check does
  (`Smt/Reconstruct.lean:186-191`). `addTrust` → `skipStep` abstracts over `currAssums`.
- cvc5 parser driving pattern: `runQuery` (`Smt/Reconstruct.lean:276-301`); cvc5 `Term`s
  outlive the `cvc5.run` block (`solve`/`solveAndReconstructProof`, lines 417-427).
- `CONSTANT` ↦ `userNames[sym]?` → local context by user name → global const
  (`Smt/Reconstruct/Builtin.lean:44-64`); uninterpreted sorts likewise (`UF.lean:23-33`).
- SCOPE pattern (`Builtin.lean:164-176`) + `Builtin.scopes : impliesN ps q → andN ps → q`
  (`Builtin/Lemmas.lean:99`); binder pattern with `withLocalDeclsD` + `withNewTermCache` +
  `withNewProofCache` + `withAssums` (`Smt/Reconstruct/Quant.lean:297-334`).
- `(or a b c)` reconstructs to a right-assoc `Or` chain; `orN [a,b,c]` whnf-reduces to it,
  `orN [p]` to `p`, `orN []` to `False` (`Prop.lean:43-51`, `Prop/Core.lean:56-59`).
- Resolution: `nary`, `clausify`, `getResolutionResult`, `reconstructResolution (c₁ c₂ :
  Array cvc5.Term) (pol l : cvc5.Term) (hps hqs : Expr)`, `reconstructChainResolution`
  (`Prop.lean:240-300`) over `Prop.orN_resolution` (`Prop/Lemmas.lean:695`);
  FACTORING/REORDERING = `Meta.AC.rewriteUnnormalizedTop` on a `p = q` goal + `Prop.eqResolve`
  (`Prop.lean:324-337`, `Builtin/AC.lean:17-41`); `Or` has Assoc/Comm/Idempotent/Identity
  instances (`Prop/Core.lean:103-111`).
- CNF lemmas (`Prop/Lemmas.lean`): `cnfAndPos l i`, `cnfAndNeg`, `cnfOrPos`, `cnfOrNeg l i`,
  `cnfImpliesPos/Neg1/Neg2`, `cnfEquivPos1/2`, `cnfEquivNeg1/2`, `and_elim`, `not_or_elim`,
  `notAnd`, `impliesElim`, `notImplies1/2`, `equivElim1/2`, `notEquivElim1/2`, `eqResolve`,
  `notNotElim`; ite lemmas `iteElim1/2`, `notIteElim1/2`, `cnfItePos1-3`, `cnfIteNeg1-3`
  (`Builtin/Lemmas.lean:16-97`, need `Decidable`, synthesized by
  `Lean.Meta.synthDecidableInstance`, `Smt/Reconstruct.lean:21`).
- Equality: REFL/SYMM(`Ne.symm`)/TRANS/CONG via `smtCongr` (`UF.lean:107-144`,
  `UF/Congruence.lean:100-116`; needs one equation per argument).
- Rewrites: per-theory `reconstructRewrite (pf : cvc5.Proof)` matching `pf.getRewriteRule!`,
  instantiation from `pf.getArguments[1..]`, list args via `.getChildren` of an SEXPR term,
  applied with `Smt.Reconstruct.Tactic.smtRw` (`Smt/Reconstruct/Rewrite.lean:33`).
- Arithmetic (Mathlib-free): `Int.polyNorm`/`nativePolyNorm` (`Int/Polynorm.lean:348,368`),
  `reconstructArithPolyNormRel` (`Int.lean:387-415`), `mul_pos_*`/`mul_neg_*`
  (`Int.lean:489-522`), `sum_ub₁…₉`, `trichotomy₁…₆`, `int_tight_ub/lb`; Rat analogues in
  `Rat.lean`, `Rat/Lemmas.lean`. No Farkas tactic exists.
- Attribute: `registerSmtAttr attr typeName descr` (`Smt/Attribute.lean:50-66`); `validate`
  requires the handler's type to be literally the named abbrev.
- Tests: `lake script run test` runs `lean --plugin=<libcvc5> Test/**/*.lean` from the repo
  root and diffs stdout with `.expected` (`lakefile.lean:47-97`).
- Text: `Smt/Data/Sexp.lean` (`Sexp.Parser.manySexps!`; `|sym|`, strings, comments).
- lean-cvc5 @7e33659 (pinned in the manifest) exposes `InputParser.new/getSymbolManager/
  setIncrementalStringInput/appendIncrementalStringInput/nextCommand?/nextTerm?`,
  `Command.invoke`, `SymbolManager.getDeclaredSorts/getDeclaredTerms/getNamedTerms`,
  `TermManager.mkTerm/mkConst`, `Solver.proofToString pf .ALETHE`.

Carcara (`~/carcara/wt-diff`, binary `target/release/carcara` built Aug 29):
- `polyeq` removes polyequality/implicit context (`assume`, `refl`, `forall_inst`,
  `subproof`, `ite_intro`, `bfun_elim`); `local` canonicalizes `trans`/`cong`/
  `eq_congruent*`/`eq_mp`/`bounded_farkas` and writes **resolution pivots as `:args`**
  (pivot, polarity pairs; `local`'s clausification rules get index args). Output still has
  `reordering` steps and set-wise resolution conclusions; `uncrowd`/`reordering` passes are
  optional knobs.
- `core` reductions dispatch through one `match` (`src/elaborator/core/mod.rs:586`
  `get_elaboration_function`) called from `elaborate_core` (`src/elaborator/mod.rs:448`)
  and `elaborate_core_expensive` (`mod.rs:547`); no per-rule restriction exists
  (`--allowed-rules` only affects checking). CLI options struct: `src/bin/cli/app.rs:222`.
- Printer emits SMT-LIB numerals (`(- 1.0)`, `(/ 1.0 2.0)`), `(! t :named @p_n)` sharing
  by default (the Lean parser supports it from M0, see Parsing), anchors as
  `(anchor :step id :args ((x S) (:= x t)))`, `define-fun` first when skolems are defined.
  Verified command:
  ```
  carcara elaborate --allow-int-real-subtyping \
    --rare-file ~/benchmarks/alethecore-eval/rewrites.eo \
    --pipeline polyeq local -- P.smt2.alethe P.smt2 | tail -n +2   # line 1 = verdict
  ```
  (`--expand-let-bindings` optional; the Lean parser handles `let` too.)
- Elaborated cvc5 output shapes (verified on a QF_UF sample):
  `(step t2 (cl (not (and a b)) a) :rule and_pos :args (0))`,
  `(step t5 (cl …) :rule resolution :premises (t4 a22 a23) :args (piv1 false piv2 false))`,
  `(step t12 (cl (= (= a b) (= b a))) :rule rare_rewrite :args ("eq-symm" a b))`,
  `(step t2 (cl (= (or (or (or p q) r) (not p)) (or (not p) r p q))) :rule aci_simp)`.
- cvc5 (`/usr/local/bin/cvc5`, 1.3.4-dev) flags for the Lean sample (verified end to end):
  `--dump-proofs --proof-format-mode=alethe --proof-granularity=dsl-rewrite
   --proof-elim-subtypes --proof-alethe-define-skolems --no-symmetry-breaker --dag-thresh=0`.
- Existing corpus `~/benchmarks/alethecore-eval/proofs/<LOGIC>/cvc5/` (98/48/66/95/93/94
  proofs for QF_UF/QF_LIA/QF_LRA/QF_UFLIA/UF/UFLIA) was made without
  `--proof-elim-subtypes`; the Lean sample is regenerated from the same problem lists.
- Rule residue after the earlier study's `polyeq local` runs, cvc5: `cong, trans,
  rare_rewrite, refl, resolution, poly_simp, bind, poly_simp_rel, reordering, equiv_pos2,
  implies_neg1/2, aci_simp, or, symm, or_neg, and_pos, contraction, forall_inst, and,
  implies_pos, subproof, implies, or_pos, evaluate, and_neg, not_implies1/2, sko_forall,
  connective_def, not_not, equiv_simplify, equiv1/2, qnt_join, equiv_pos1, onepoint,
  not_and, miniscope_split, qnt_rm_unused, implies_simplify, distinct_elim, not_equiv1/2,
  false, and_intro, la_generic, la_disequality, mult_pos/neg, mult_distrib, hole`.

## Design

### Module layout (new)

```
Smt/Alethe.lean               umbrella (public (meta) imports; imports Smt.Prop/UF/Int/Rat/Quant)
Smt/Alethe/Syntax.lean        AST, parametric in the term type (Sexp before / cvc5.Term after realization)
Smt/Alethe/Parser.lean        Sexp normalisation passes + Sexp → Proof Sexp (pure, #eval-testable)
Smt/Alethe/Realize.lean       cvc5.Env: load problem, realize Proof Sexp → Proof cvc5.Term
Smt/Alethe/Basic.lean         Premise/AnchorCtx/Step records, RuleReconstructor, checker State, mkClause, trust helpers
Smt/Alethe/Lemmas.lean        new lemmas (orN_of_impliesN, not_not_cl, la_generic glue, la_disequality, …)
Smt/Alethe/Clause.lean        resolution chain, contraction/reordering fix-up, `or`
Smt/Alethe/Prop.lean          @[alethe_rule_reconstruct] handler: CNF axioms, elim rules, true/false/not_not, and_intro, aci_simp, *_simplify
Smt/Alethe/UF.lean            handler: refl/symm/not_symm/trans/cong/distinct_elim/rare_rewrite/evaluate
Smt/Alethe/Arith.lean         (M2) poly_simp, poly_simp_rel, la_generic, la_disequality, mult_pos/neg, mult_distrib, comp_simplify
Smt/Alethe/Quant.lean         (M3) bind, forall_inst, sko_forall/sko_ex, onepoint, qnt_*, choice
Smt/Alethe/Reconstruct.lean   driver: assume matching, anchors, dispatch, degradation, result assembly
Smt/Alethe/Frontend.lean      checkAlethe (parse → realize → close over symbols → kernel addDecl → report), shared by command and exe
Smt/Alethe/Command.lean       `#check_alethe "prob.smt2" "proof.alethe"`
AletheMain.lean               `lake exe alethe`
```
All new files follow the module system (`module`, `public import` / `public meta import`,
`public meta section`; lemma files under `@[expose] public section`).

Existing files touched:
- `Smt/Attribute.lean`: `initialize registerSmtAttr `alethe_rule_reconstruct
  `Smt.Alethe.RuleReconstructor "…"`.
- `Smt/Options.lean`: trace classes `smt.alethe`, `smt.alethe.parse`, `smt.alethe.step`.
- `Smt/Reconstruct/Prop.lean`: `getResolutionResult`/`reconstructResolution` take
  `pol : Bool` (old signatures kept as one-line wrappers); lift the local `rightAssocOp`
  out of its `where` block.
- `Smt/Reconstruct.lean`: `addTrustWith (type : Expr) (info : MessageData)`; existing
  `addTrust` becomes its cvc5 wrapper.
- `Smt/Reconstruct/{Builtin,Prop,UF,Int,Rat,Quant,…}.lean`: `RewriteStep` refactor (below).
- `Smt.lean`: import `Smt.Alethe`. `lakefile.lean`: `lean_exe alethe where root :=
  `AletheMain; supportInterpreter := true`.

### Data structures (`Syntax.lean`, `Basic.lean`)

```lean
inductive Arg (τ) | term (t : τ) | list (ts : Array τ) | str (s : String)
  | num (n : Int) (d : Nat) | assign (x : String) (t : τ) | binder (x : String) (v : τ)
inductive Command (τ)
  | assume (id : String) (t : τ)
  | step (id : String) (cl : Array τ) (rule : String) (premises : Array String)
         (args : Array (Arg τ)) (discharge : Array String)
  | anchor (id : String) (args : Array (Arg τ)) (body : Array (Command τ))  -- closed by `step id`
  | defineFun (name : String) (text : Sexp)
structure Proof (τ) where cmds : Array (Command τ)
structure Problem where sorts : Array cvc5.Sort; funs : Array cvc5.Term; asserts : Array cvc5.Term

structure Premise where id : String; lits : Array cvc5.Term; concl : Expr; proof : Expr
structure AnchorCtx where vars : Array (String × cvc5.Term × Expr); assums : Array Premise
                          subst : Array (String × cvc5.Term); last : Premise
structure Step where id rule : String; lits : Array cvc5.Term; concl : Expr
  premises : Array Premise; args : Array (Arg cvc5.Term); discharge : Array Premise
  anchor : Option AnchorCtx
abbrev RuleReconstructor := Step → ReconstructM (Option Expr)
structure State where steps : HashMap String Premise; trusted : HashMap String Nat
  failures : Array (String × String × String); holes : Nat
abbrev AletheM := StateRefT State ReconstructM
```
Handlers stay in plain `ReconstructM`; only the driver sees `State`.

### Parsing (`Parser.lean`), Sexp level

1. `Sexp.Parser.manySexps!` on the file; unwrap a single outer `( … )` wrapper if present.
2. Numeral safety net: `n/d` → `(/ n d)`, `-k` → `(- k)` (Carcara already prints SMT-LIB
   forms; cvc5-native proofs do not). `la_generic` coefficients are also kept as `Arg.num`.
3. **Bindings: `let` and `:named`, handled uniformly by the parser from M0.** The parser
   carries a binding environment `HashMap String Sexp` and eliminates both constructs:
   - `(let ((x t) …) body)`: SMT-LIB parallel-let semantics, scoped, shadowing respected;
     occurrences of `x` in `body` are replaced by `t` (capture-free: bound terms are closed
     except for anchor variables, which are already renamed to unique symbols in pass 6).
   - `(! t :named n)`: the annotation is stripped, `n ↦ t` is added to the environment from
     that point to the end of the proof (Alethe/Carcara sharing semantics, names like
     `@p_12`), and later occurrences of `n` are replaced by `t`. Names are also legal in
     `:args` positions and inside `assume` terms.
   Substitution shares `Sexp` values in memory, so no blowup on the Lean side. To keep the
   text sent to cvc5 small, `Realize` serializes with a memo: a maximal subterm equal to a
   bound term is emitted as a fresh legal symbol `p!n`, bound in cvc5 by
   `(! t :named p!n)` on first use (fallback `(define-fun p!n () S t)` with `S` from the
   realized term's sort). Result: each shared term crosses the parser once, and cvc5's
   hash-consing plus lean-smt's `termCache` keep the `Expr` DAG shared.
   Carcara is therefore run with its default sharing on (no `--no-print-with-sharing`), and
   `--expand-let-bindings` becomes optional. M0 tests include a proof with `:named` sharing
   and one with `let`.
4. `(rare-list …)` / bare `rare-list` → `Arg.list`.
5. Commands: `assume`, `step` (`:rule/:premises/:args/:discharge`), `anchor :step id
   [:args …]`, `define-fun` verbatim. Fold the flat stream into an anchor tree.
6. Alpha-rename anchor variables to globally fresh legal symbols (`x!k`) throughout the
   block (keeps the bound name in `(:= (x S) t)` LHS, renames inside `t`). This avoids
   push/pop and handles nested re-binding of the same name.
7. (M3) `(choice ((x S)) φ)` → fresh constant `k!i` plus a recorded `(exists ((x S)) φ)`,
   later seeded into `userNames` as `Classical.epsilon`.

### Term realization (`Realize.lean`, in `cvc5.Env`, one `cvc5.run` per check)

- `loadProblem`: incremental string input; skip `check-sat*`, `get-*`, `exit`, `set-info`,
  `echo`; for `(assert φ)` append `φ` and `nextTerm` (never assert to the solver); all other
  commands `nextCommand` + `invoke`; then `getDeclaredSorts`/`getDeclaredTerms`. Set
  `produce-proofs false`, never `checkSat`.
- `realizeProof`: per step append all literal/arg texts, then k × `nextTerm`; `Arg.list` →
  `TermManager.mkTerm .SEXPR ts` (verify empty SEXPR; else a sentinel); `Arg.binder x S` →
  `(declare-const x!k S)` invoked, then `nextTerm` on `x!k`; proof-top `define-fun` →
  `nextCommand` + `invoke` (cvc5 macro-expands at parse time; verify on the first sample
  with skolem definitions, fallback = `dfns` scheme of `Smt/Reconstruct.lean:238-246`).
- Return `(Problem, Proof cvc5.Term)`; reconstruct afterwards in `MetaM`.

### Driver (`Reconstruct.lean`)

`Smt.Alethe.reconstructProof (pf : Proof cvc5.Term) (prob : Problem) (ctx :
Reconstruct.Context) : MetaM (Expr × Expr × List MVarId × Stats)` returning type
`¬ andN [a₁,…,aₙ]` (lean-smt's `SolveReconstructResult.unsat` shape) and its value:
1. `as ← prob.asserts.mapM reconstructTerm`; `withLocalDeclsD` hypotheses `hs`; `withAssums hs`.
2. Fetch handlers once per proof via `getReconstructors ``RuleReconstructor`.
3. Top-level `assume id t`: index `i` with `prob.asserts[i] == t` (cvc5 structural `BEq`),
   fallback `findAssumWithType?`; otherwise error (a `lax` flag may add it as a hypothesis
   and report).
4. `step`: build `Step` (`concl ← mkClause lits`), try handlers in order, on `none` or
   exception → `addTrustWith` + `trusted[rule] += 1` + `failures.push`. `hole` → trust,
   counted separately. Optional `checkSteps := true` runs `Meta.check` per returned proof
   (because `addThm` never checks; a kernel error at the end is unattributable).
5. `anchor`: `withNewTermCache`; for each binder `withLocalDeclD x!k (← reconstructSort …)`
   and `withReader` extending `userNames[x!k] := fvar`; block `assume`s as local decls added
   with `withAssums`; recurse; the closing `step id` is dispatched with `anchor := some …`;
   reject (→ trust) a returned proof that still mentions the anchor's fvars.
   - `subproof`: `h ← mkLambdaFVars (assums.map (·.proof)) last.proof` (`impliesN ps q` by
     defeq, as `Int.lean:343-352`), conclusion via new `orN_of_impliesN : impliesN ps q →
     orN (notN ps ++ [q])`, AC fix-up if literal order differs.
   - `bind` (M3): fold `forall_congr`/`exists_congr_eq` as `Quant.lean:305-333`.
6. Final: `h ← mkLambdaFVars hs hFalse`; value `Builtin.scopes h`; type `¬ andN as`;
   return trusted mvars (`skippedGoals`) and `Stats` (checked, trusted by rule, holes,
   failures with id/rule/message).

### Rule dispatch

New attribute `@[alethe_rule_reconstruct]` over `abbrev Smt.Alethe.RuleReconstructor :=
Step → ReconstructM (Option Expr)`, one handler per theory file matching on
`step.rule` strings and returning `none` for foreign rules (mirrors
`@[smt_proof_reconstruct]`; adds no new constraint since `reconstructTerm` already needs
`evalConst`).

### Clauses (`Clause.lean`)

- `mkClause lits`: `False` / single literal / right-assoc `Or` fold. Clause `Expr`s are
  always `Or` chains, never syntactic `orN […]` (AC normalization needs a binary `Or` at the
  top; kernel accepts `orN`-typed lemmas by whnf).
- `or`: identity (same `Expr`); literal arrays still tracked for clause boundaries.
- `resolution`/`th_resolution`: fold `Prop.reconstructResolution` (with `pol : Bool`) over
  premises using `:args` pivot pairs (confirm polarity convention on the M0 sample); unit
  `or` premises via `Prop.clausify`/`reclausify`; re-resolve while the pivot remains (set
  semantics); pivot search fallback when `:args` is absent. If the computed literal array
  differs from the stated clause: fix-up = fresh `p = q` goal closed by
  `Meta.AC.rewriteUnnormalizedTop` + `Prop.eqResolve` (exactly FACTORING; `Or`'s
  idempotence removes duplicates). Prefer this over the older
  `Prop/{Factor,PermutateOr}.lean` builders; revisit only if profiles say so.
- `contraction`, `reordering`: the same fix-up from the premise.

### QF_UF rule → reuse table

| Alethe rule | Lean |
|---|---|
| `and k` / `not_or k` / `not_and` / `and_intro` | `Prop.and_elim` (+`mkDecideProof`), `Prop.not_or_elim`, `Prop.notAnd`, `And.intro` fold |
| `implies`, `not_implies1/2`, `equiv1/2`, `not_equiv1/2` | `impliesElim`, `notImplies1/2`, `equivElim1/2`, `notEquivElim1/2` |
| `and_pos k`, `and_neg`, `or_pos`, `or_neg k` | `cnfAndPos ps k`, `cnfAndNeg`, `cnfOrPos`, `cnfOrNeg ps k` |
| `implies_pos`, `implies_neg1/2` | `cnfImpliesPos`, `cnfImpliesNeg1/2` |
| `equiv_pos1/2`, `equiv_neg1/2` | `cnfEquivPos2/1`, `cnfEquivNeg2/1` (indices swap on purpose) |
| `ite1/2`, `not_ite1/2`, `ite_pos1/2`, `ite_neg1/2` | `iteElim2/1`, `notIteElim2/1`, `cnfItePos2/1`, `cnfIteNeg2/1` |
| `true`, `false`, `not_not` | `trivial`, `not_false`, new `not_not_cl : ¬¬¬p ∨ p` |
| `refl`, `symm`/`not_symm`, `trans` | `Eq.refl`, `Eq.symm`/`Ne.symm`, `Eq.trans` fold with orientation by cvc5-term comparison |
| `cong` | align premises to argument positions (`Eq.refl` for equal children, `Eq.symm` when flipped), then `UF.smtCongr` via `addTac`; `distinct` positions → trust |
| `distinct_elim` | `Eq.refl` (as `Builtin.lean:96-100`) |
| `subproof` | driver + `orN_of_impliesN` |
| `rare_rewrite ("name" args…)` | `RewriteStep` refactor + table `aletheRareRules : HashMap String ProofRewriteRule` (`"eq-symm" ↦ .EQ_SYMM`, …; about 36 names in the corpus, extend on demand) |
| `aci_simp` | `addTac concl Meta.AC.rewriteUnnormalizedTop` (Builtin ACI_NORM) |
| `evaluate` | Builtin EVALUATE body factored to `(lhs rhs : cvc5.Term)`; `decide`, else trust |
| `equiv_simplify`, `implies_simplify`, `and/or_simplify` | shape table over cvc5 kinds → existing RARE theorems (`bool_eq_false`, `bool_eq_true`, `eq_refl`, `bool_impl_*`, `bool_and_conf`, …); fallback `simp only` with a curated set from `*/Rewrites.lean`; else trust |
| `hole` | trust, counted separately |

`RewriteStep` refactor: `structure RewriteStep where rule : ProofRewriteRule; args : Array
cvc5.Term; result : cvc5.Term; premises : Array (ReconstructM Expr)` with
`RewriteStep.ofProof`; each theory's `reconstructRewrite` body is mechanically rewritten to
take a `RewriteStep`, cvc5 dispatchers call `reconstructRewrite (.ofProof pf)`. Interim M1
shortcut: apply the five most frequent RARE theorems directly, delete once refactor lands.

### Arithmetic (M2, `Arith.lean`)

- `poly_simp` → `Int.polyNorm` / `Rat.polyNorm` via `addTac`; `poly_simp_rel` → factor
  `reconstructArithPolyNormRel` to `(premiseResult premiseProof result)`.
- `mult_pos/neg` (and `la_mult_pos/neg` if kept) → `mul_pos_*` / `mul_neg_*` lemmas;
  `mult_distrib` → `polyNorm`.
- `la_generic` (Farkas; dominates residue: 40k–68k steps per arithmetic logic): introduce
  negations of clause literals as hypotheses (`withLocalDeclsD` + `mkLambdaFVars`, as
  `reconstructMulSign`), integer strengthening of strict bounds with `int_tight_ub/lb`, scale
  by the `Arg.num` coefficients (lcm-cleared for Int) with `mul_pos_*`, fold with
  `sum_ub₁…₉`, normalize with `polyNorm`, close by `decide`/`lt_irrefl`, convert with
  `orN_of_impliesN`. Cover the two strengthening pitfalls documented in
  `~/carcara/wt-diff/investigations/2026-08-25-la-generic-strengthening.md` with tests.
- `la_disequality` → new lemma from `trichotomy`; `la_totality`/`la_tautology`/`la_rw_eq`
  → delegation candidates; `comp_simplify` → RARE `ARITH_*` theorems via `RewriteStep`;
  `lia_generic` (veriT only) → `omega` attempt, else trust.
- Check `TO_REAL` handling in `Smt/Reconstruct/Rat.lean` (mixed terms should not appear with
  `--proof-elim-subtypes`, but coefficients like `1.0` in Int proofs are read as values only).

### Quantifiers (M3, `Quant.lean`)

`forall_inst` (instantiate as `INSTANTIATE`, both `(:= x t)` and bare-term args),
`bind` (anchor + `forall_congr`), `sko_forall`/`sko_ex` (`Classical.epsilon`,
`epsilon_spec_aux'` as `Quant.lean:77-93,335-347`), `qnt_rm_unused`/`qnt_join`/
`miniscope_*` via existing `QUANT_*` rewrite theorems through `RewriteStep`, `onepoint`/
`connective_def`/`qnt_duality`/`qnt_simplify` with new lemmas or delegation; `choice` as
in the parser pass.

### Per-rule delegation to Carcara

Add `--core-rules <rule>...` to Carcara (in `wt-diff` or a fresh worktree): early
`if !core_rules.contains(&s.rule) { return None }` in the `mutate` closures of
`elaborate_core` (`src/elaborator/mod.rs:448`) and `elaborate_core_expensive`
(`mod.rs:547`), field in `ElaborationOptions` (`src/bin/cli/app.rs:222`) threaded through
the elaborator config. Lean-checker pipeline becomes
`polyeq local core --core-rules <delegated>` (a second `core` if second-generation
reducible steps appear). Initial candidates (all have recipes in `core/mod.rs:586`):
`not_symm`, `eq_congruent_pred`, `la_totality`, `la_tautology`, `la_rw_eq`,
`la_mult_pos/neg`, `connective_def`, `qnt_simplify`, `qnt_rm_unused`, `qnt_join`,
`miniscope_*`, `onepoint`, `ac_simp`, plus `*_simplify` rules lacking a lean-smt theorem.
A rule is delegated only after its trusted count and Lean cost are measured on the sample.

### Entry points

- `#check_alethe "P.smt2" "P.alethe"` (`Command.lean`) → `Frontend.checkAlethe`: parse,
  realize, close over sorts (`(S : Type)` + `[Nonempty S]`), functions
  (`reconstructSort f.getSort!`), `userNames` from symbols; `mkForallFVars`/`mkLambdaFVars`;
  trusted mvars abstracted as extra hypotheses (or `sorryAx` with a warning, as
  lean-cpc-checker); `addDecl (.thmDecl …)`; deterministic `logInfo` line
  `checked N steps, trusted K (rule: n, …), holes H` so `.expected` files are stable;
  timings under `trace.smt.alethe`.
- `lake exe alethe P.smt2 P.alethe [--native] [--check-steps]` (`AletheMain.lean`):
  `initSearchPath`, `enableInitializersExecution`, `importModules #[`Smt] (loadExts :=
  true)`, run `checkAlethe`, print `[time] parse/realize/reconstruct/kernel` and the trusted
  report; exit 0 valid, 1 holey, 2 error.
- Later: `alethe` tactic closing goals like `Smt/Tactic/Smt.lean:141-147`.

## Local sample and gating

`~/benchmarks/alethe-lean/` (outside the repo):
- `problems/<LOGIC>/`: smallest 10 problems per logic from
  `~/benchmarks/alethecore-eval/sample-<LOGIC>.txt` whose cvc5 proof succeeds (QF_UF,
  QF_LIA, QF_LRA, QF_UFLIA now; UF, UFLIA at M3).
- `scripts/gen.sh`: cvc5 flags above, `timeout 30`, `ulimit -v 8000000`, `xargs -P 2` max.
- `scripts/elab.sh`: Carcara command above, `ulimit -s unlimited`, `timeout 300`,
  `ulimit -v 8000000`; stores `<P>.elab.alethe` and the verdict line.
- `scripts/check.sh`: `lake exe alethe` per proof, `timeout 600`, `ulimit -v 10000000`,
  one at a time, smallest first, `/usr/bin/time -v`; writes `results/<LOGIC>.csv`
  (`file,steps,verdict,trusted,trusted_rules,t_parse,t_reconstruct,t_kernel,rss_kb`).
- `scripts/rules.sh`: rule histogram (`grep -oE ':rule [^ )]+'`) = the worklist.
- Build: branch `alethe` off `main`; locally swap in the `no_mathlib` lakefile/manifest
  (not committed); first `lake build Smt` fetches lean-auto, lean-cvc5 (downloads a prebuilt
  cvc5) — run it alone. Never run test builds and sample checks concurrently; use
  `lean -M 8000` where possible.

## Milestones

**M0 — skeleton.** Create `Smt/Alethe.lean`, `Syntax`, `Parser`, `Realize`, `Basic`,
`Lemmas`, `Clause`, `Prop` (only `or`, `resolution`, `true`, `false`, `not_not`),
`Reconstruct`, `Frontend`, `Command`; modify `Smt/Attribute.lean`, `Smt/Options.lean`,
`Smt/Reconstruct/Prop.lean` (`pol : Bool`), `Smt/Reconstruct.lean` (`addTrustWith`),
`Smt.lean`. Tests `Test/Alethe/M0/`: hand-written `simple.smt2`
(`p`, `(or (not p) q)`, `(not q)`) with a 3-step proof (`or`, two `resolution`s with
pivots), a pivot-less copy, a variant with `(declare-sort U 0)(declare-fun f (U) U)`, a
variant whose proof uses `(! t :named @p_1)` sharing (including a name used in `:args` and
in an `assume`), and one using `let`; each first validated by
`carcara check --check-granularity elaborated`. Parser unit tests (`#eval`) cover
`let` shadowing and `:named` scope. Verify `.expected`
= `checked … trusted 0`, `addDecl` passes, `checkSteps` passes, a mutated proof is rejected.

**M1 — QF_UF.** `Smt/Alethe/UF.lean`, full `Prop.lean` table, anchors/`subproof`,
`RewriteStep` refactor (separate commit), `AletheMain.lean` + lakefile `lean_exe`. Tests:
`2018-Goel-hwbench__QF_UF_blocks.2.prop1_ab_reg_max` and a `subproof`/`trans` file copied
to `Test/Alethe/QF_UF/` after elaboration with the target pipeline. Verify zero trusted
steps on both; run `scripts/check.sh QF_UF` on the 10-file sample and iterate on the
trusted-by-rule histogram (expected hot spots: `equiv_simplify` shape table, `evaluate`,
`cong` alignment); `lake script run test` still green.

**M2 — linear arithmetic.** `Smt/Alethe/Arith.lean` as above; Carcara `--core-rules`
flag; first delegation list. Verify QF_LIA/QF_LRA/QF_UFLIA samples with zero trusted steps
or documented residue; regression tests for `la_generic` over Int (strengthening) and Rat,
`la_disequality`, `poly_simp_rel`.

**M3 — quantifiers.** `Smt/Alethe/Quant.lean`; add UF, UFLIA samples; `choice` and
`define-fun` skolems verified. Regression tests per binder rule.

**M4 — consolidation.** `alethe` tactic; in-process differential test (`Solver.proofToString
… .ALETHE` → Carcara → checker); README section; grow the sample to 30–50 per logic;
only then consider cluster runs (via the `stanford-cluster` skill, with approval).

## Risks to watch

- `termCache` keyed by `cvc5.Term` across scopes (fresh `x!k` names + `withNewTermCache`).
- `Decidable` for `ite` falls back to `Classical.propDecidable`, which breaks `decide` in
  `evaluate` (use `simp` before trusting).
- `addThm` never checks → use `checkSteps` in tests.
- cvc5 parser vs Alethe syntax: `cl`, `(:= …)`, `(x S)`, `rare-list`, `choice`; whether
  cvc5 accepts `@`-prefixed symbols (hence the `p!n` renaming for shared terms); empty
  SEXPR construction; `define-fun` macro expansion — each verified on first contact.
- `cong` premise alignment, `trans` orientation, resolution polarity convention, set vs
  multiset semantics: handled defensively and validated by the kernel; measure after M1.
- Scale: QF_UF proofs reach hundreds of thousands of resolutions; batch `nextTerm` calls,
  rely on hash-consing + `termCache`; profile with `lake script run profile`; a
  theorem-per-top-level-step kernel submission is the fallback for memory.

## Verification summary

- Unit: `lake script run test` picks up `Test/Alethe/**` automatically.
- Sample: `scripts/check.sh <LOGIC>` → `results/<LOGIC>.csv`; success = every proof
  `valid` with 0 trusted steps; the trusted histogram is the worklist.
- Soundness spot checks: mutate a literal in an elaborated proof and confirm kernel
  rejection; compare verdicts with `carcara check --check-granularity elaborated`.
- Every script wraps `ulimit -v`, `timeout`, runs sequentially, logs peak RSS.
