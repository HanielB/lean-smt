
## Turn: 2026-09-14 01:25:57 (session 6cc35fc7)

The second smoke pass is clean.

## Against the first pass — one commit apart, same sample

| | cvc5 | veriT |
|---|---|---|
| `timeout → valid` | 38 | 38 |
| `valid →` anything else | **0** | **0** |
| `valid → holey` | 0 | 0 |
| wall new/old, proofs over 10 s | median 0.969 | median 0.914 |

Every lost proof came back — all 37 cvc5 and all 38 veriT, plus one extra on the cvc5 side — and they come back *faster than round six*, because the `and` optimization applies to them too: `LD_ST_neg.2step` 28.7 s → 24.4 s, `FISCHER10-1` 34.8 s → 31.7 s.

## Against round six

cvc5: **13 gained, 0 lost** (6 `timeout → valid`, 6 `error → valid`, 1 `none → valid`). veriT: **24 gained** (11 + 8 + 5 `holey → valid`) against one loss — `convert-jpg2gif-query-1237`, 880.5 s in round six against a 900 s limit, so twenty seconds from the edge. `valid → holey` is 0 in every pairing.

Per rule, all gains hold and nothing regressed: `and` 3.740 → 0.818 ms/step on cvc5 and **19.025 → 1.704** on veriT, `subproof` 7.491 → 4.882.

## One finding worth recording

Four veriT benchmarks moved between non-valid states and I checked all four rather than wave them through. Three are veriT hitting its own 150 s solver kill in one pass but not the other (136.8, 143.4, 132.9 s against the limit) — solver timing, not the checker. The fourth is real: `QF_LIA/…/cggmp2005-O0.smt2` was a 900 s timeout and is now an **error at 301 s**, Lean's `-M 10000` heap cap with RSS at 10,241,864 kB. Before the fix it burned its whole budget in the quadratic parse and never allocated that far; now it gets further and exhausts the heap on a 29,667-step proof. Never valid either way and no soundness question, but a genuine memory-bound case for the report.

## Waiting on you

```
cluster-approve
```

for the full round's dry run. It uploads the driver (header updated to name the `ee8502b` oleans and the two smoke passes — the submit call itself is unchanged) and dry-runs it, submitting nothing: octa, `-j 8`, wall 3000 s, 12000 MB, 1 cpu, the twelve `unsat_*` sets, 25,200 benchmarks per solver, into `cvc5-7` and `verit-7`. The submit will need its own approval after that.

## Turn: 2026-09-14 10:23:33 (session 6cc35fc7)

**Dry run passed**, exit 0:

| | cvc5 | veriT |
|---|---|---|
| working dir | `cvc5-7` | `verit-7` |
| partition | octa | octa |
| wall / memory / cpus | 3000 s / 12000 MB / 1 | 3000 s / 12000 MB / 1 |
| jobs per node | 8 | 8 |
| sets | 12 `unsat_*` | 12 `unsat_*` |

No errors, no `Submitted` line. The uploaded driver matches the local one (md5 `a3dce29b…`), so the `mux_client_request_session` warning was only ssh's control socket, not a failed transfer.

**Waiting on you:**

```
cluster-approve
```

for the full round. It starts both jobs inside a detached tmux named `alean7`, waits 45 seconds, then reports the submitted array count, the aggregator lines and the queue — 25,200 benchmarks per solver.

Toolchain going in: carcara `29a8e966`, lean-smt oleans `ee8502b`. cvc5, veriT, the benchmark sets, `rewrites.eo` and `run-arms.sh` are byte-identical to round six, so the two rounds stay directly comparable. This is the configuration the second smoke pass validated on a tenth of the corpus.

## Turn: 2026-09-14 10:25:00 (session 6cc35fc7)

Full round seven is running.

| | |
|---|---|
| tmux | `alean7` |
| arrays | 24, twelve per solver |
| aggregators | 3196142, 3196174 — both up |
| tasks | 23,327 cvc5 (200 already running), 23,328 veriT |
| working dirs | `cvc5-7`, `verit-7` |
| limits | octa, 8 per node, wall 3000 s, 12000 MB, 1 cpu |

One correction to my own proposal note: I described the round as 25,200 benchmarks per solver. That is the catalog's count across all fourteen logics; these twelve give **23,328** — exactly what round six ran, which is what makes the pairing work.

Toolchain: carcara `29a8e966`, lean-smt oleans `ee8502b`, everything else byte-identical to round six.

I have a waiter on the queue. Round six took most of a day, so expect similar. When it lands I'll pair the full round against round six the same way, and then update the report — `tab:smtlib`, `tab:native`, the five figures, and §2.2, where the `and` row will change substantially (19.03 → 1.70 ms/step on veriT).

## Turn: 2026-09-14 11:23:08 (session 6cc35fc7)

**650 proofs** — the larger of the two Carcara defects that closed veriT's checking gap between rounds five and six.

The breakdown by family, which is the tell that it really was int/real mixing:

| family | proofs |
|---|---|
| QF_UFLRA `mathsat` | 409 |
| QF_LRA `meti-tarski` | 95 |
| QF_LRA `LassoRanker` | 85 |
| QF_RDL `sal` | 47 |

All real-arithmetic families, which is exactly what you'd expect.

To be precise about what the defect was, since the phrasing matters: it was a **Carcara parser** defect, not veriT emitting bad proofs. veriT writes an integer literal on one side of an equality whose other side is real-sorted — which `--allow-int-real-subtyping` is supposed to permit. Carcara consulted that flag for operators with fixed numeric argument sorts (`+`, `*`, `/`, the order comparisons) but *not* for the positions where the sorts merely have to agree with each other: the arguments of `=` and `distinct`, the branches of an `ite`, and the arguments of an uninterpreted function. So those proofs were rejected with *sort error: expected `Real', got `Int'* before checking even began.

Two further details worth having:

- The same defect had shown up in an earlier three-logic round on **194 QF_LRA proofs**, where it was misattributed to `lia_generic` residue. So it cost two diagnoses before being caught.
- The fix is confined to those three polymorphic positions, so `(div 1.0 2.0)` is still correctly rejected, and the affected families now check *valid* rather than merely parsing.

For context on scale: it was 650 of the 868 proofs veriT's gap lost between the rounds (the other 190 were `ac_simp` ignoring `:premises`, 28 other). veriT's gap went 1,344 → 476.

## Turn: 2026-09-14 13:43:12 (session 6cc35fc7)

Written to `verit-int-real-failures.txt` (704 lines, 653 benchmark paths).

**How the list was derived**, so you can check it: every round-four veriT task whose output contains `sort error: expected 'Real', got 'Int'` — 653 of 23,328, all with Carcara verdict `error`. Cross-referencing against round six resolves the report's 650 exactly: 650 now check `valid`, and 3 do not, for unrelated reasons (one `no-proof`, one `error`, one where veriT produced nothing).

The distribution confirms it was real-arithmetic only:

| logic | proofs | | family | proofs |
|---|---|---|---|---|
| QF_UFLRA | 412 | | QF_UFLRA/`mathsat` | 409 |
| QF_LRA | 189 | | QF_LRA/`meti-tarski` | 95 |
| QF_RDL | 49 | | QF_LRA/`LassoRanker` | 84 |
| | | | QF_RDL/`sal` | 47 |

Two small corrections to the figures I quoted from the report earlier, now that I have counted from the data: `LassoRanker` is **84**, not 85, and `sal` is **47** across a QF_RDL total of 49. The report's per-family numbers (409/95/85/47) are otherwise right; the 85 looks like a transcription slip, and the tail families it omits are QF_LRA/`miplib` (9), QF_UFLRA/`FFT` (3), and three singletons. I can fix that line in the report when I next touch it — say the word if you'd rather I did it now.

The file also carries the explanation of the defect and notes the earlier three-logic round where the same thing was misattributed to `lia_generic` residue. It is untracked; tell me if you want it committed.

Round seven is still running in the background.

## Turn: 2026-09-14 13:45:04 (session 6cc35fc7)

Committed as `0915e5f` (the non-zero exit was just `grep` finding no modified files — the tree is clean).

The line now reads:

> …the affected benchmarks are exactly the real-arithmetic families: 412 in QF_UFLRA (409 `mathsat`, 3 `FFT`), 189 in QF_LRA (95 `meti-tarski`, 84 `LassoRanker`, 9 `miplib`) and 49 in QF_RDL (47 `sal`).

Two things this fixes beyond the `85` → `84` slip: the old figures omitted the tail families entirely, so they summed to 636 against the 650 the same paragraph claims. They now add up exactly.

Report rebuilt clean at 23 pages, and `verit-int-real-failures.txt` is committed alongside it so the numbers have a checkable source.

Round seven is still running; I'll report when the queue empties.

## Turn: 2026-09-14 14:37:48 (session 6cc35fc7)

I'm regenerating proofs for a 36-benchmark stratified sample (all nine families) so I can report the operators and rules from evidence rather than from the fix alone.

What the Carcara fix commit `92d8a42f` settles definitively — it changed exactly three call sites:

| position | check that was unconditional |
|---|---|
| arguments of `=` / `distinct` | `check_sort_all_eq` |
| the two branches of `ite` | `check_sort_eq` on `sorts[1]`/`sorts[2]` |
| arguments of an uninterpreted function | `check_sort_eq` per argument |

And it confirms which sites deliberately stay strict: `div`, `mod`, `to_int`, `is_int` and the trigonometric operators, so `(div 1.0 2.0)` is still rejected. The already-correct ones were `+`, `-`, `*`, `/`, `abs` and the order comparisons.

The sample will tell me which of those three actually fire in practice and in which steps' terms. I'll add both the code-level list and the measured distribution to the file.

## Turn: 2026-09-14 14:40:56 (session 6cc35fc7)

The file now answers this systematically. The result is sharper than I expected: **one rule, one operator, one shape.**

## What veriT emits

```
(! (- 1.0) :named @p_1)                                   in an assumption
...
(step t28 (cl (= @p_1 (- 1))) :rule unary_minus_simplify)
```

`@p_1` names `(- 1.0)`, which is Real. veriT prints the simplified right-hand side as `(- 1)` — unary minus on an *integer* literal, so Int. The `=` therefore has Real on one side and Int on the other. Note `(- 1)` is fine on its own: `-` has fixed numeric argument sorts and already honoured the flag. It is the `=` above it that was rejected.

## The measurement

I resolved the `file:line:column` each round-four task recorded against proofs regenerated with the runner's own veriT invocation, on a stratified sample of 36 (six per family, all nine families):

- The reported position is the `=` of a `unary_minus_simplify` step in **36 of 36**. No other operator, no other rule.
- The parser stops at its first error, so that alone would only characterise the *first* offending term. Scanning every step of those proofs for the same shape finds **221 occurrences, again all `unary_minus_simplify`**.

## Against what the fix actually changed

Carcara `92d8a42f` relaxed three polymorphic positions; this population reaches the defect through the first alone:

| | |
|---|---|
| relaxed | arguments of `=` / `distinct` ← **the one these proofs hit**, branches of `ite`, arguments of an uninterpreted function |
| already correct | `+ - * / abs`, order comparisons |
| deliberately still strict | `div mod to_int is_int`, trigonometric operators |

So `(div 1.0 2.0)` is still rejected, and nothing changes with the flag off.

The file also now carries the reported line:column per benchmark, so any entry can be re-checked. Committed as `379d7e6`.

One caveat I want to be explicit about: the 36-proof sample is stratified across all nine families and is unanimous, but it is a sample — I have not regenerated all 653 proofs, which would mean re-running veriT on every one. If you want certainty across the whole set rather than strong evidence, say so and I'll run it.

## Turn: 2026-09-14 14:53:28 (session 6cc35fc7)

Short answer so far: **no, and my previous claim was wrong.** The scan is running; here is what is already clear.

`unary_minus_simplify` is where the *first* rejection always lands — that is what the 36-of-36 result really showed, and it is the position Carcara reported for every one of the 653. But the mis-printed literal is not confined to that rule. Once veriT writes `(- 1)` where the term is `(- 1.0)`, that same integer-sorted term reappears in other steps that mention it. The FFT proof shows it plainly:

```
=  unary_minus_simplify   (= @p_3 (- 1))
=  cong                   (= @p_5 (- 1))
=  la_generic             (= 1.0 (- 1))
```

That last one is the clearest statement of the defect: a Real literal equated with an Int term.

Two corrections I owe you on how I got here:

- My "221 occurrences, all `unary_minus_simplify`" was worthless as corroboration. It searched for `(= @p_N (- <int>))` — the exact shape I had already found — so it could only ever confirm itself. It would miss the int on the left, an int without the unary minus, or mixing at an `ite` or function argument.
- My first shape-agnostic scan then reported `div_simplify`, `trans` and `cong` hits that were **false positives**: I had it treating `/` as Int-valued when both arguments are Int, but SMT-LIB `/` is real division and always returns Real (`div` is the integer one). Those disappeared once fixed.

So the operator is still `=` in everything seen so far, but the rules are more than one. I'll give you the full distribution across the sample when the scan finishes, and correct the file — which currently states the wrong claim.

## Turn: 2026-09-14 14:54:13 (session 6cc35fc7)

Rescanning with the recursion fix and a higher size cap (35 of 36 proofs now, only the 224 MB one excluded). From the 26 that scanned cleanly the first time:

| operator | rule | occurrences | proofs |
|---|---|---|---|
| `=` | `cong` | 138 | 7 of 26 |
| `=` | `unary_minus_simplify` | 87 | **26 of 26** |
| `=` | `la_generic` | 3 | 3 of 26 |

So the shape of the answer: the operator really is `=` and nothing else — no `distinct`, no `ite`, no uninterpreted-function argument. But the rule is not only `unary_minus_simplify`. That rule is the one present in *every* proof and the one the parser always hits first, which is consistent with it being the origin: veriT drops the decimal point when it prints the simplified negated literal, and the resulting Int-sorted term then turns up again in `cong` and `la_generic` steps that mention it.

I'll confirm those counts on the fuller scan before I correct the file.

## Turn: 2026-09-14 14:55:39 (session 6cc35fc7)

**No — and my earlier claim was wrong.** Rescanning shape-agnostically (inferring a sort for every subterm, flagging every polymorphic position whose arguments disagree) over 35 of the 36 sampled proofs:

| occurrences | proofs | operator | rule |
|---|---|---|---|
| 707 | 11/35 | `=` | `cong` |
| 220 | **35/35** | `=` | `unary_minus_simplify` |
| 3 | 3/35 | `=` | `la_generic` |

So two things are true at once:

**The operator really is `=` alone.** Not one `distinct`, not one `ite` branch, not one uninterpreted-function argument — even though the Carcara fix relaxed all three positions. On this population only the first was ever needed.

**The rule is not only `unary_minus_simplify`** — but that rule is the origin. It appears in every proof, it is where the parser stops in all 36, and it is where the bad literal is created: veriT prints the simplified negated literal without its decimal point, so a Real term gets equated with an Int one. `cong` then inherits it directly from that step:

```
(step t4384 (cl (= @p_2 (- 100))) :rule unary_minus_simplify)
(step t4385 (cl (= @p_10477 (! (= tmp64 (- 100)) :named @p_10478)))
            :rule cong :premises (t4384))
```

with `tmp64` declared `Real`. And `la_generic` shows it at its barest: `(= 1.0 (- 1))`.

`cong` has the larger raw count but occurs in under a third of the proofs and always downstream of a `unary_minus_simplify` premise. So: one operator, one origin, two rules that inherit it — fixing how veriT prints that literal would remove all three.

Two methodological corrections behind this, both mine:

- The "221 occurrences, all `unary_minus_simplify`" I gave you was not evidence. It grepped for `(= @p_N (- <int>))` — the shape I had already found — so it could only confirm itself.
- An intermediate version of the new scan reported `div_simplify`, `trans` and `cong` hits that were **false positives**: it treated `/` as Int-valued on Int arguments, where SMT-LIB `/` is real division and always returns Real.

File corrected and committed as `145218a`. Coverage caveat stands: this is 35 proofs of 653, stratified across all nine families; one 224 MB proof was too large to scan.

## Turn: 2026-09-14 17:11:14 (session 6cc35fc7)

Waiter restarted (10-minute poll), and I freed the 507 MB of regenerated proofs that caused the memory pressure.

Round seven is healthy and roughly half done overall: cvc5 has 3,373 queued and 200 running of 23,327 — so about 19,750 finished — and veriT's 23,328 queue behind it. Nothing was lost when the waiter died; only my polling stopped.

I'll report when the queue empties, then pair the full round against round six and update the report.

## Turn: 2026-09-14 17:11:50 (session 6cc35fc7)

Restarted the waiter with a 15-minute poll.

The memory pressure isn't mine: a **concurrent Claude session** is running `carcara reconstruct` jobs out of `~/carcara/wt-tiago` (processes seconds old, different session id). That's what keeps tripping the harness's low-memory guard and killing my waiter. I've left those processes alone. I also freed the 507 MB of proofs I'd regenerated, so my own footprint is now minimal.

Round seven itself is unaffected — the cluster jobs don't care what happens locally. If the waiter gets killed again I'll simply check the queue on your next message rather than keep respawning it.
