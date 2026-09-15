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
