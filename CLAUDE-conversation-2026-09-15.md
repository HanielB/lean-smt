## Turn: 2026-09-15 (session 6cc35fc7)

Round seven is complete. Both jobs finished, 23,328 benchmarks per solver.

**Headline, against round six**

| | cvc5 r6 → r7 | veriT r6 → r7 |
|---|---|---|
| Lean valid | 16,813 → **16,912** (+99) | 15,870 → **16,098** (+228) |
| timeout | 2,327 → 2,259 | 2,827 → 2,729 |
| error | 50 → **15** | 116 → **14** |
| holey | 0 → 2 | 48 → **17** |
| carcara valid | 19,190 → 19,188 | 18,688 → 18,683 |

`valid → holey` is **0** on both, the check that matters. Median slowdown against
carcara is 178× (cvc5) and 436× (veriT); on proofs both validate the wall-clock
ratio r7/r6 is 0.963 median, and 0.941 / 0.917 restricted to proofs over 10 s.

**Per rule**, the `and` work holds at full scale:

| rule | cvc5 | veriT |
|---|---|---|
| `and` | 3.808 → **0.829** ms/step (0.22×) | 18.889 → **1.682** (0.09×) |
| `or_neg` | 1.966 → 0.948 | — |
| `subproof` | 7.514 → 4.920 | — |
| `bind` | 9.145 → 7.262 | 11.277 → 9.004 |
| `resolution` | 5.278 → 5.075 | 5.026 → 5.022 |

**Losses.** veriT loses 24 proofs, every one of them between 851 s and 898 s in
round six against a 900 s limit — boundary noise, no exceptions. cvc5 loses 4,
and two of those are real and worth chasing:

```
QF_LIA/…/ConcurrencySafety-Main/30_Function…   769.3 s valid  ->  900 s timeout
QF_LIA/…/ConcurrencySafety-Main/32_pthread5…   526.2 s valid  ->  900 s timeout
```

Same elaborated proof both rounds (617 and 291 steps), and both are stuck in
**parse**: round six spent 283.7 s and 237.4 s there, already the dominant phase,
and round seven does not finish parsing inside 900 s. Few steps but enormous
terms — 47.7 MB and 29.8 MB of raw cvc5 proof. Neither was in the tenth-sample,
so neither smoke pass could have caught them. That leaves a residual parse cost
in the `e9c32bf` + `ee8502b` path on this shape, which the QF_IDL chains the fix
targeted do not exhibit. The other two cvc5 losses are one boundary timeout
(899.4 s) and one where cvc5 itself crashed this round (`solver_rc=134`, no
proof).

**New holes.** cvc5 gains 2 `error → holey`; both used to fail outright and now
complete with trusted steps. veriT's holey count falls 48 → 17.

**Residue, for the report.** cvc5: carcara rejects 2 `equiv_simplify`; the 15
Lean errors are all `failed to parse`. veriT: carcara rejects 102 `and_simplify`
and 4 `minus_simplify`; all 14 Lean errors are `memory_exception`. CPU: carcara
9.6 h against the checker's 177.3 h (cvc5), 8.8 h against 167.4 h (veriT).

## Turn: 2026-09-15 08:08:03 (session 6cc35fc7)

Round seven is complete — both jobs, 23,328 benchmarks per solver.

## Against round six

| | cvc5 | veriT |
|---|---|---|
| Lean **valid** | 16,813 → **16,912** (+99) | 15,870 → **16,098** (+228) |
| timeout | 2,327 → 2,259 | 2,827 → 2,729 |
| error | 50 → **15** | 116 → **14** |
| holey | 0 → 2 | 48 → **17** |
| carcara valid | 19,190 → 19,188 | 18,688 → 18,683 |

**`valid → holey` is 0 on both** — the check that matters. Median slowdown against carcara is 178× (cvc5) and 436× (veriT). On proofs both rounds validate, r7/r6 wall is 0.963 median, and 0.941 / 0.917 restricted to proofs over 10 s.

## Per rule — the `and` work holds at full scale

| rule | cvc5 | veriT |
|---|---|---|
| `and` | 3.808 → **0.829** ms/step (0.22×) | 18.889 → **1.682** (0.09×) |
| `or_neg` | 1.966 → 0.948 | — |
| `subproof` | 7.514 → 4.920 | — |
| `bind` | 9.145 → 7.262 | 11.277 → 9.004 |

## Losses, and one that needs chasing

veriT loses 24, and **every one** sat between 851 s and 898 s in round six against a 900 s limit — boundary noise without exception. cvc5 loses 4, of which two are real:

```
QF_LIA/…/30_Function…    769.3 s valid → 900 s timeout
QF_LIA/…/32_pthread5…    526.2 s valid → 900 s timeout
```

Same elaborated proof both rounds (617 and 291 steps), both stuck in **parse** — round six spent 283.7 s and 237.4 s there, already the dominant phase, and round seven doesn't finish parsing within 900 s. Few steps, enormous terms (47.7 MB and 29.8 MB of raw cvc5 proof). Neither was in the tenth-sample, so neither smoke pass could have caught them. So there's a residual parse cost in the new path on this shape — different from the QF_IDL chains the fix targeted. The other two cvc5 losses are one boundary timeout (899.4 s) and one where cvc5 itself crashed (`solver_rc=134`, no proof).

Also: cvc5 gains 2 `error → holey` — proofs that used to fail outright now complete, but with trusted steps.

## Residue for the report

cvc5: carcara rejects 2 `equiv_simplify`; all 15 Lean errors are `failed to parse`. veriT: carcara rejects 102 `and_simplify` and 4 `minus_simplify`; all 14 Lean errors are `memory_exception`. CPU: carcara 9.6 h against the checker's 177.3 h (cvc5), 8.8 h against 167.4 h (veriT).

Logged as `62a7731`. Two obvious next steps — updating the report to round seven, and diagnosing those two parse regressions. I'd suggest the parse regression first, since it may change a number in the report. Which would you like?

## Turn: 2026-09-15 08:50 (session 6cc35fc7)

**Request:** update the report to round seven, and explain the two cvc5 holes.

**The cvc5 holes, root-caused.** Both are QF_UF `2018-Goel-hwbench` proofs
(`QF_UF_h_Vlunc_ab_cti_max`, 1,465 steps, 9.0 s, 2 trusted;
`QF_UF_h_BufAl_ab_fp_max`, 11,939 steps, 66.9 s, 6 trusted). All 8 trusted
steps are `resolution`, all fail in `ac_rfl_top`, and all have the same shape.
Reproduced locally on Vlunc with the cluster's cvc5 and Carcara flags
(different cvc5 build, 1,847 elaborated steps, same 2 trusted steps):

- cvc5's clauses carry doubly negated literals, e.g. `(cl ... (not (not y$251)) ...)`
  (original step t15), and its SAT solver treats `(not (not p))` as `p`, so one
  `(not p)` eliminates both `p` and `(not (not p))` in a single chain.
- Carcara's checker accepts the step: `resolution.rs` matches a literal against
  its negation with one negation added *or removed*.
- Carcara's elaborator (`local/resolution.rs`) cannot order the chain — greedy
  inference fails with "pivot was not eliminated: (not (not y$251))", the RUP
  fallback finds no chain either — and keeps the step *without* `:args`
  (4 such warnings on Vlunc, 8 on BufAl, one per trusted step).
- lean-smt's `resolveChain` (Clause.lean) then finds one syntactic pivot per
  premise, eliminates `y$251` against `(not y$251)`, and leaves
  `(not (not y$251))` in the working clause. The computed clause has one
  literal more than the stated one, so `concludeClause`'s AC fallback fails:
  `[ac_rfl_top] expected (= y$n1s32 ...) ∨ ¬¬y$251 and (= y$n1s32 ...) to have
  the same AC operator`.

Both proofs were memory exhaustions in round six, so the hole is new only in
that the proofs now get that far. Not fixed; the remedy is to resolve modulo
double negation in `resolveChain` — after the pivot loop, re-resolve against
the same premise on the stacked-negation form of the pivot (`¬¬p` vs `¬p`),
which is sound (the premise is a proven clause) and cannot loop the way the
tautology case did. Not started; waiting on Haniel.

**Report updated** (`docs-alethe/alethe-lean-smt.tex`, 33 scripted
replacements, each asserted to match once; PDF rebuilt, 24 pages,
2,326,814 bytes). Regenerated with the round-six scripts on `cvc5-7`/`verit-7`:
`report-table.py` (tab:smtlib), `plots-round6.py` (scatter + cactus),
`plots-native6.py` (tab:native + 4 figures), `rule-boxplots.py --label-by
pooled --stack -n 16` (Fig. 4). The native LaTeX body was generated from the
plot script's text table by the edit script. Changes of substance:

- Outcomes: 16,912 / 16,098 valid; mem 0 / 14; holey 2 / 17; 15 cvc5 errors.
  Per-logic: UF all but one, UFLIA 99.9%, QF_LIA 93%, QF_UF 59%/58%, QF_IDL
  67%/40%.
- Carcara gap: cvc5 19,188 of 19,189; veriT 478 = 261 holey + 151 timeout
  (median 57 MB, a quarter above 240 MB — round six's "130 to 230 MB" was
  replaced by the measured quartiles) + 38 memory + 28 rejected (27
  `and_simplify`, 1 `minus_simplify`; the "102 + 4" in the collect-results
  entry counted steps, not proofs).
- Against Carcara: 12,806 / 9,760 both valid; median 178× / 436× (gmean 163 /
  417, p90 402 / 915; check alone 177 / 434); QF_UF 135× vs UF 346×; QF_UF
  medians 0.78 s vs 52 s and 0.14 s vs 45 s; CPU 9.6 / 8.8 h vs 177 / 167;
  size buckets: <10k steps 0.1% / 0.5% timeouts, 20–50k 72% / 94%.
- Cactus: Carcara 26.6 / 18.1 h; checker 184 / 171 h; first 13,147 / 11,982
  within Carcara's budget.
- Per rule: 178× / 436×; or_neg 4,500×, and 4,600× (was 9,300× / 30,000×);
  resolution 59% (+ semilattice_simp 12%); the `and` paragraph now in the past
  tense with the round-seven median 1.3 ms, share 3%, and per-solver 0.8 / 1.7
  ms against 3.8 / 18.9; semilattice_simp 4.4 ms 850×, poly_simp 11 ms 790×.
  Figure labels unchanged (178 M resolution, 84 M cong — they sum both series).
- What is left: the cvc5 double-negation holes as above; veriT 17 = 10
  lia_generic + 6 th_resolution + 1 resolution (QF_IDL/parity/06.200, kernel
  memory cap); the 32 distinct_elim gone, fixes confirmed.
- Revealed: apostrophe — all 49 check; deep recursion — 4 of 5 check, 1
  timeout; resolution loop — all 8 cvc5 memory failures now complete (6 valid,
  2 holey), so "6 one step too large" was wrong and is retracted; veriT 49 →
  34 valid, 14 remain (asp, parity, Dartagnan); the Decidable lookup — root
  cause and fix stated, and the 40 proofs are now timeouts (median 61,600
  steps), not successes; ho_cong the one open group (13 incrementalScheduling
  + 2 QF_UFLIA Certora).
- Native: 19 / 19 more valid; 16,908 / 16,097 both; 23 / 20 native-only, 4 / 1
  step-only — verified every one is a timeout on the other arm; 92.5% / 92.3%
  faster; 172.8→164.2 h and 165.2→161.4 h; kernel 606→409 ms and 573→491,
  106.7→95.2 h and 109.4→105.3, share 58% / 65% vs 62% / 66%; 33,005 pairs.

Committed as one change with the regenerated figures. Overfull boxes in the
build are the two pre-existing ones (§1.2 and §3).

## Turn: 2026-09-15 08:48:39 (session 6cc35fc7)

I'll start with the cvc5 holes, then update the report. First, the two holey cvc5 tasks in round seven.

## Turn: 2026-09-15 08:48:39 (session 6cc35fc7)

The report is on round seven (commit `1c3f32e`, PDF rebuilt at 24 pages), and the two cvc5 holes are one defect, reproduced locally.

## The cvc5 holes

Both proofs are QF_UF hardware benchmarks from `2018-Goel-hwbench`: `Vlunc_ab_cti_max` (2 trusted steps) and `BufAl_ab_fp_max` (6). All 8 trusted steps are `resolution`, and all fail the same way. I regenerated the Vlunc proof with the cluster's cvc5 and Carcara flags and got the same two trusted steps.

**What cvc5 does.** Its clauses carry doubly negated literals, and its SAT solver treats `¬¬p` as `p`. So one `(not p)` eliminates both `p` and `(not (not p))` in a single resolution chain. Alethe literals are syntactic, so that is not a chain any checker can replay one pivot per premise.

**What Carcara does.** Its checker accepts the step, because it matches a literal against its negation with one negation added *or removed*. Its elaborator cannot order the chain, and says so:

```
warn: resolution 't1090': could not infer pivots (pivot was not eliminated: '(not (not y$221))'), keeping step
```

It keeps the step without `:args`. One such warning per trusted step, 4 on Vlunc and 8 on BufAl.

**What the checker does.** With no pivot hints, `resolveChain` finds one syntactic pivot per premise. It eliminates `y$251` against `¬y$251` and leaves `¬¬y$251` in the working clause, so the computed clause has a literal the stated one lacks and the AC fallback fails:

```
[ac_rfl_top] expected (= y$n1s32 ...) ∨ ¬¬y$251 and (= y$n1s32 ...) to have the same AC operator
```

Both were memory exhaustions in round six, so the hole is new only because the proofs now get that far. The fix is local: after the pivot loop, re-resolve against the same premise on the stacked-negation form of the pivot. That is sound, since the premise is a proven clause, and it cannot loop the way the tautology case did. Not started.

## What changed in the report

- **Tables and figures.** Both tables and the seven SMT-LIB and native figures regenerated with the round-six scripts. Sledgehammer figures are unchanged.
- **Headline prose.** 16,912 and 16,098 validated, 178× and 436× median slowdown, size buckets, cactus budgets, and the per-rule section now reads the `and` fix as confirmed at full scale.
- **Residue.** The cvc5 holes as above. veriT's 17 are 10 `lia_generic`, 6 `th_resolution`, and one resolution step that hit the kernel memory cap. The 32 `distinct_elim` holes are gone.
- **Two corrections to earlier claims.** Round six's "6 memory failures are one step too large" was wrong: all 8 now complete. And the 40 veriT `Decidable` proofs are fixed but now time out, at a median of 61,600 steps. The report says both.
- **One number I had reported wrongly.** The "102 `and_simplify` + 4 `minus_simplify`" in the collect-results summary counted steps. Per proof it is 27 and 1, unchanged from round six.

Open items, in the order I'd take them: the double-negation resolution fix, then the two cvc5 parse regressions on `ConcurrencySafety-Main`.

## Turn: 2026-09-15 08:57:00 (session 6cc35fc7)

All six are the same three-line pattern, verified on the smallest (`uf.560771`, regenerated locally with the cluster's veriT and Carcara flags, same trusted step). In veriT's proof, inside a Skolemization subproof:

```
(step t22.t23 (cl X)          :rule th_resolution :premises (t22.t22 t22.t21))
(step t22.t24 (cl (= (not (not X)) X)) :rule not_simplify)
(step t22.t25 (cl X)          :rule th_resolution :premises (t22.t23 t22.t24))
```

**The step is vacuous.** Its conclusion is its first premise verbatim, and the second premise, the equality `¬¬X = X`, is never resolved against anything. veriT had already derived `¬¬X`, turned it into `X` with a `not_not` clause at t22.t22 and a real resolution at t22.t23, then "used" the `not_simplify` equality in one more resolution that changes nothing. To veriT the literals `¬¬X` and `X` are the same SAT literal, so from its side this looked like the step that eliminated the double negation.

**Carcara accepts it, its elaborator does not annotate it.** The checker's greedy chain inference fails (there is no pivot between `X` and an equality), so it falls back to RUP, and `X` is trivially implied by a premise that *is* `X`. The elaborator has no such fallback for producing pivots. It logs the same warning as the cvc5 case and keeps the step without `:args`:

```
warn: resolution 't22.t25': could not infer pivots (pivot was not eliminated: '(= (not (not X)) X)'), keeping step
```

**The checker then refuses it.** With no hints, `resolveChain` searches for a pivot between the working clause `[X]` and the premise `[(= ¬¬X X)]`, finds none, and throws "no pivot found between …", which the per-step guard turns into a trusted step. The clause it needed was already in hand.

So the residue is not a `th_resolution` weakness. It is one degenerate veriT shape, in the same family as the cvc5 holes: a solver whose SAT-level literals identify `¬¬p` with `p` writes a resolution step Alethe's syntactic literals cannot replay. All six are Sledgehammer benchmarks, three from `Fundamental_Theorem_Algebra` and three from `Hoare`, and the pattern always sits under the same anchor with a `choice` witness.

The fix is smaller than the cvc5 one: when no pivot exists between the working clause and a premise, skip the premise rather than fail. That is sound, since the premise contributed nothing to the derivation, and the final comparison against the stated clause still catches any real mismatch. Both fixes touch the same loop in `Smt/Alethe/Clause.lean`. If you want, I can do them together and add the two proofs as regression tests.

## Turn: 2026-09-15 09:19:15 (session d1c95d65)

I'll explore the current checker and the performance data before designing anything.

## Turn: 2026-09-15 09:19:15 (session d1c95d65)

The SMTCoq study landed and it changes the design for the better. Let me rewrite the plan.

## Turn: 2026-09-15 09:19:15 (session d1c95d65)

Both sources paid off — and one of them changes a design decision.

**Lean's LRAT checker (in core, backs `bv_decide`) is not kernel-evaluated.** It compiles `verifyBVExpr expr cert` natively, runs it, and mints a *fresh axiom* asserting the result (`Lean/Meta/Native.lean:18-87`; `ofReduceBool` was deprecated for this in Feb 2026). Same trust profile as `native_decide`. The reason is structural: its clause DB is `Array (Option Clause)` and its assignment is an `Array Assignment` mutated in place with a trail for undo — and Lean's `Array` is a structure wrapping a `List`, so in the kernel every `get`/`modify` is a list traversal. The number worth carrying away is the proof cost: **~3,400 of its ~5,500 lines verify the mutate-and-undo discipline of that array, against 84 lines for the actual proof induction.** A functional bitset has no such state and pays none of it. What does port: put the untrusted parser *inside* the checked function (trust-free), treat a bad hint as rejection not panic, and the `_result`/`_sound` split for Stage 2's store. Alethe needs no RAT analogue at all — resolution steps carry explicit premises, so the hint property is free.

**Carcara contributes two things and one correction.** It interns (literal = `(negation count, &Rc<Term>)`, `Rc::eq` is `ptr_eq`, no term ever traversed) — that's what we do with `Nat` indices. And it *doesn't binarize*: `greedy_resolution` checks an n-premise chain in one pass over Σ|premise| literals, which is why it's three to four decades faster per step, and why it grew a `budget` pass whose module doc names lean-smt as the consumer needing chains split. The bitset fold reaches the same asymptotics without importing greedy's invariant (which needs a per-premise elimination cap *and* a same-premise pivot buffer, each with an unsoundness counterexample inline).

The correction: Carcara **counts** negations rather than collapsing parity — `p`, `¬¬p`, `¬¬¬p` are three distinct literals, with a regression test for a real cvc5 pattern. A single parity bit provably cannot express that, since `¬¬g` and `g` are different Lean `Prop`s and the denotation must produce the literal syntactically. So Stage 1 handles literals with at most one leading negation and falls back otherwise — which is exactly the restriction Carcara's own `rup_chain` fallback carries.

I also measured the two kernel assumptions rather than assuming them:

- The kernel **does** reduce `Nat.div`/`mod`/`land`/`lor`/`xor`/`shiftLeft` on literals. A 230-iteration bitset fold over a 459-bit `Nat`, closed by `rfl`, is free (0.22 s for the whole file including startup).
- Converting a clause denotation to a real `Or` chain costs the kernel **~50 µs/literal** (2000 literals → `type checking took 105ms`). That's the new floor, and it's irreducible.

**Expected gain.** The cost model becomes ≈50 µs × (literals in the step), flat in the number of links, against ~10 ms per *link* today with a width-cubed term on wide chains. The 230-premise step in the sample proof — one 230-literal clause against 229 units, i.e. literally unit propagation — goes from 1.18 s to ~25 ms. Corpus-wide it's Amdahl on the 51 %: **~1.5–2× median, one to two orders on the tail**. The tail is the deliverable — the 2,287 + 2,494 timeouts and the memouts, and it removes the need for `budget`.

**What it takes:** ~300 lines of verified core (constructive, no `Classical.em`, no `propext`) plus ~200 of reification, 2–3 days; Stage 2 another 2–3 behind a flag. `AciNorm.lean` is 462 lines of the identical shape and its `denoteOr_iff`/`testBit` lemmas are near copy-paste.

## Turn: 2026-09-15 09:19:15 (session d1c95d65)

No response requested.

## Turn: 2026-09-15 09:19:15 (session d1c95d65)

`/home/hbarbosa/lean/lean-smt/RESOLUTION-PLAN.md` — 342 lines, committed alone as `2ddfa08` on `alethe-dev`. The rest of the dirty tree is untouched.

## Turn: 2026-09-15 09:31:13 (session 6cc35fc7)

Waiting on the lean-smt test suite (both new regression tests plus the existing 142) before committing the pin bump and the tests; I'll report when it finishes.

## Turn: 2026-09-15 09:55 (session 6cc35fc7)

**Request:** the checker stays clean; the two resolution shapes are Carcara's
to handle.

**Carcara** (`~/carcara/wt-diff`, branch `bv-fixes`, pushed to `origin`):

- `d1823169` *elaborator: write a chain for the resolutions a solver's SAT
  literals justify.* `rup_chain` now reports the chain of one premise it
  finds (a conflict clause falsified by the negated conclusion alone), and
  `build_rup_chain_step` drops the step when that premise is the conclusion
  verbatim — returning the premise node, as `remove_reorderings` does — or
  writes the weakening/reordering directly over it. That is the veriT shape.
  For cvc5's, when neither greedy inference nor the RUP chain succeeds,
  `reduce_stacked_negations` rewrites every premise literal under ≥2
  negations that the conclusion does not keep, by a `not_not` step and a
  binary resolution on that literal, and the chain is inferred over the
  reduced premises by the same two routes. The weakening/reordering tail is
  factored into `restore_clause`, which no longer writes a no-op weakening.
  Three new cases in `tests/elaboration/resolution.rs`, expected output
  written by hand from the algorithm and matched on the first run.
- `69c92a64` *budget and uncrowd skip the step ids an earlier pass already
  used.* Found by BufAl: the reduced premises survive as `t11076.t3`/`.t4`,
  and the budget pass then named its pieces `t11076.t1..t4` from a fresh
  `IdHelper` — lean-smt refused the proof with `duplicate step id`.
  `IdHelper::avoiding(root, taken)` skips ids already in the proof; both
  passes collect the set once. Unit test for the helper.
- Suite: 414 tests, all passing (412 before + the elaboration test + the
  unit test). Static binary rebuilt from the committed state,
  `carcara 1.1.0 [git 69c92a64 bv-fixes]`, md5 `796c3e13…`.

Minimal cvc5 shape, elaborated with `--pipeline local`:

```
(step t1 (cl @p_1 q) :rule or :premises (h1))            ; @p_1 = (not (not p))
(step t4.t1 (cl (not @p_1) p) :rule not_not)
(step t4.t2 (cl p q) :rule resolution :premises (t1 t4.t1) :args (@p_1 true))
(step t4.t3 (cl r q) :rule resolution :premises (t2 t4.t2) :args (p false))
(step t4.t4 (cl r q s) :rule weakening :premises (t4.t3))
(step t4 (cl q r s) :rule reordering :premises (t4.t4))
```

**Verified on the eight round-seven proofs** (regenerated locally with the
cluster's solver and Carcara flags; `scratchpad/holes8/check.sh`): all
elaborate with zero warnings and check `valid … trusted 0, holes 0` —
Vlunc 1,862 steps 6.6 s, BufAl 12,670 steps 45 s, the six veriT ones
98–472 steps, 2.7–3.7 s each.

**lean-smt** `a0d0dbd`: pin bumped to `69c92a64` in `scripts/setup-alethe.sh`;
regression tests `Test/Alethe/QF_UF/hwbench_double_negation` (Vlunc, cvc5)
and `Test/Alethe/UF/th_resolution_unused_premise` (uf.560771, veriT), with
the elaborated proofs from the new binary. `lake test`: 144 passing. No
change under `Smt/`.

**One mistake on the way.** `rustfmt` on `src/elaborator/mod.rs` follows the
`mod` declarations and reformatted 19 files; the repository is not
rustfmt-clean, so I reverted every file I had not meant to touch and
re-applied my hunks minimally. The committed diff is 6 files.

**Not done.** The report's residue paragraph still describes round seven as
measured (the holes existed on that toolchain); a round eight would retire
it. The cluster's `runs/alethe-lean7/bin/carcara` is still `29a8e966`.
