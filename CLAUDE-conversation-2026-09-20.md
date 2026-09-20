
## Round nine results

Both halves finished (cvc5 19 Sep 15:57, veriT 23:55). Compared against round
eight on all 23,328 benchmarks each, `~/exp/alethe-lean/round9-compare.py`.

### Coverage: nothing moved the wrong way

|                  | cvc5 r8 -> r9        | veriT r8 -> r9        |
|------------------|----------------------|-----------------------|
| valid            | 17,540 -> 17,546 (+6)| 16,921 -> 16,928 (+7) |
| timeout          | 1,635 -> 1,627       | 1,926 -> 1,916        |
| holey            | 0 -> 0               | 10 -> 10              |
| trusted steps    | 0 -> 0               | 10 -> 10, all `lia_generic` |
| `valid -> holey` | 0                    | 0                     |

The remaining verdict churn is solver-side jitter against the 150 s kill
(`timeout -> valid` 12 and 11, `valid -> timeout` 5 and 5, and so on). So
`distinct_elim` accepting the canonical form alone, and the three dropped
reconstructors, cost nothing anywhere in the corpus -- which is the only way
this round could have gone wrong.

### `distinct_elim`: 5.17 h -> 0.04 h, 132x

veriT, same 11,751 steps: 1,582 ms a step -> 12 ms. And on the **native** arm
too, 5.13 h -> 0.04 h -- so that cost was never the kernel's. It was the
checker's own alignment scan and congruence chain, which `native` does not
avoid; Carcara canonicalizing and the checker comparing in order removes it on
both arms.

The bridge Carcara adds is visible and is the price: veriT `cong` 8.78 -> 9.99 h
(0.88x) on 3% more steps, `eq_symmetric` 1.48 -> 1.55, `trans` 1.97 -> 2.03.
About 1.35 of the 5.13 hours saved goes back into the bridge.

### `la_generic`: 1.12x, and the control behaves

|            | kernel arm        | native arm        |
|------------|-------------------|-------------------|
| cvc5       | 4.83 -> 4.31 (1.12x) | 2.49 -> 2.46 (1.01x) |
| veriT      | 13.79 -> 12.28 (1.12x) | 10.57 -> 10.53 (1.00x) |

The native arm is flat to 1%, which is exactly the control the pairing was for:
the re-keying changes what the kernel evaluates and nothing the compiled
evaluator does, so the kernel-arm movement is attributable to it.

But 1.12x is well under the 1.34x I measured locally and the 1.55x I estimated.
The local measurement was one QF_LRA proof whose `la_generic` steps average ~22
literals and ~176 monomials; across the corpus the steps are much smaller (veriT
13.79 h over 940k steps is 53 ms a step), and on small polynomials `normalize`
is a smaller share of the work, so re-keying it buys less. `poly_simp` likewise
gained 1.06x on cvc5 against the ~1.7x I projected.

### Totals

    cvc5   rule time 154.16 -> 153.29 h (1.01x); lean wall 634.3 -> 634.5 h
    veriT  rule time 183.26 -> 178.19 h (1.03x); lean wall 714.7 -> 704.8 h

Wall barely moves because rule time is a fraction of it -- parsing, realizing,
the solver and elaboration dominate the rest.

## Turn: 2026-09-20 12:06:12 (session 18d95de2)

Both halves finished (cvc5 19 Sep 15:57, veriT 23:55). Compared against round eight on all 23,328 benchmarks each.

## Coverage — nothing moved the wrong way

| | cvc5 r8 → r9 | veriT r8 → r9 |
|---|---|---|
| valid | 17,540 → **17,546** (+6) | 16,921 → **16,928** (+7) |
| timeout | 1,635 → 1,627 | 1,926 → 1,916 |
| holey | 0 → 0 | 10 → 10 |
| trusted steps | 0 → 0 | 10 → 10, all `lia_generic` |
| **`valid → holey`** | **0** | **0** |

The remaining churn is solver-side jitter against the 150 s kill (`timeout→valid` 12 and 11, `valid→timeout` 5 and 5). So `distinct_elim` accepting only the canonical form, and the three dropped reconstructors, cost nothing anywhere in the corpus — the one way this round could have gone wrong.

## `distinct_elim`: 5.17 h → 0.04 h — **132×**

Same 11,751 veriT steps: 1,582 ms a step → 12 ms.

The surprise is that it fell just as far on the **native** arm (5.13 → 0.04 h). So that cost was never the kernel's — it was the checker's own alignment scan and congruence chain, which `native` doesn't avoid. Carcara canonicalizing plus the checker comparing in order removes it on both arms. My earlier framing of this as a kernel problem was wrong.

The bridge Carcara adds is the price, and it's visible: veriT `cong` 8.78 → 9.99 h on 3% more steps, plus small rises in `eq_symmetric` and `trans`. About 1.35 of the 5.13 hours saved goes back into the bridge.

## `la_generic`: 1.12×, and the control behaved

| | kernel arm | native arm |
|---|---|---|
| cvc5 | 4.83 → 4.31 h (**1.12×**) | 2.49 → 2.46 (1.01×) |
| veriT | 13.79 → 12.28 h (**1.12×**) | 10.57 → 10.53 (1.00×) |

The native arm is flat to 1% — exactly what the two-arm pairing was for. The re-keying changes what the kernel evaluates and nothing the compiled evaluator does, so the kernel-arm movement is attributable to it.

But 1.12× is well under the 1.34× I measured locally and the 1.55× I estimated, and I should own that. My local number came from one QF_LRA proof whose `la_generic` steps average ~22 literals and ~176 monomials. Across the corpus the steps are far smaller — veriT's 13.79 h spread over 940k steps is 53 ms each — and on small polynomials `normalize` is a smaller share of the work, so re-keying it buys less. `poly_simp` likewise gained 1.06× against the ~1.7× I projected.

## Totals

```
cvc5    rule time 154.16 → 153.29 h (1.01×)    lean wall 634.3 → 634.5 h
veriT   rule time 183.26 → 178.19 h (1.03×)    lean wall 714.7 → 704.8 h
```

Wall barely moves because rule time is a fraction of it — parsing, realizing, the solver and elaboration dominate the rest.

**The honest summary:** the `distinct_elim` work was worth it and then some — a 132× on the rule, net ~3.8 h after the bridge, and it validates pushing canonicalization into Carcara. The `Polynorm` re-keying is real and measurable but small at corpus scale, and `resolution` (99.3 + 102.3 = 201.6 h) plus `semilattice_simp` (36.0 h on veriT) now dominate everything else by an order of magnitude. Stage two of `RESOLUTION-PLAN.md` is where the next hour comes from.

Want me to update the report and summary to round nine?

## Turn: 2026-09-20 14:19:39 (session 18d95de2)

Stopping here. Where things stand on the report update:

**Done — round-nine data and figures are regenerated:**
- `~/exp/alethe-lean/plots9/` — `cactus-smtlib.pdf`, `carcara-vs-lean-smtlib-{cvc5,veriT}.pdf`
- `~/exp/alethe-lean/plots9/native/` — `step-vs-native-*`, `kernel-step-vs-native-*`
- `~/exp/alethe-lean/plots9/stacked/` — `rule-boxplots.pdf`, `rule-totals.pdf`, `rule-samples.csv`
- The `tab:smtlib` LaTeX body and all the prose figures it feeds (medians 169× / 425×, carcara vs checker CPU hours, the veriT carcara-gap buckets 261/150/37/28, per-rule medians and shares)
- `~/exp/alethe-lean/round9-compare.py`, the round-eight/nine diff script

**Not done — no `.tex` file was touched yet.** Both documents are still at round eight, unmodified. I was mapping the edit sites when you exited; nothing is half-edited, so there's no inconsistent state to clean up.

Two things I found worth knowing before that edit happens:

1. **The Sledgehammer section is not round-nine data.** `cvc5-seventeen` / `verit-seventeen` were last run 2026-09-09. Round nine submitted only the twelve SMT-LIB logics, so that section and its two figures describe an older round — as they already did in the round-eight report, without saying so.
2. **The box-plot step-count labels mix populations.** `steps_by_rule` sums the `carcara-elab` counts (every step in the elaborated proof) with the `lean` counts (only steps the checker reached), which is why the figure says 190 M `resolution` while the checker actually ran 25.9 M. The report quotes those labels as "steps in the round". Worth fixing or rewording rather than carrying forward.

Everything from this session is logged in `CLAUDE-conversation-2026-09-20.md`. Say the word when you want the `.tex` edits done.

## Turn: 2026-09-20 16:39:37 (session 8d69a5cd)

Both stale workers are gone and all three sessions now have no live process. Transcripts are intact (flushed on stop).

**What they were:** background/fleet sessions managed by the `claude daemon` — not tmux, not plain `claude` processes. `alethe-proof-checking (2)` had a worker alive for 25 hours that the daemon had already marked `done` and "retired" at 02:25Z but which never actually exited; that orphan is why the session looked stale and wouldn't come back cleanly.

**What I ran:**

```
claude stop 6cc35fc7      # alethe-proof-checking (2)
claude stop 18d95de2      # alethe-proof-checking (3)
```

`stop` kills the worker and keeps the conversation. The commands you were missing:

- `claude agents` (or `--json` when not on a TTY) — lists background sessions with their short ids
- `claude stop <id>` — kill the worker, keep the transcript
- `claude rm <id>` — delete the session entirely; works on already-exited ones
- `claude daemon stop` — nuclear option, terminates every background session

**To resume:**

```
claude attach 18d95de2                                          # (3) — round-nine plots/report work
claude attach 6cc35fc7                                          # (2) — the big 23MB one
claude attach bddaeda3                                          # (1) — idle since Sep 13
```

Or in the foreground on the same transcript, e.g. `claude --resume 18d95de2-d7a7-4f82-9b04-018a12006ffb`.

For context on where to pick up: `(3)` stopped itself at 17:19Z today after regenerating `~/exp/alethe-lean/plots9/` (cactus, carcara-vs-lean, native and stacked rule figures) — that's the most recent state. `(1)` is stale by a week; `claude rm bddaeda3` clears it from the list if you don't want it, though I left it alone since `rm` deletes the session rather than just stopping it.

One leftover process, pid 2713348, is the daemon's prewarmed spare pool rather than a session — harmless, and the daemon reaps it on its own.

## Turn: 2026-09-20 16:43:12 (session 18d95de2)

Here it is precisely.

## What the caption claims

> "the label above each group is the rule's **total step count in the round**"

## What the code computes

`rule-boxplots.py:203–207` sums the `count` column across **both drawn series**:

```python
for _, sv, se, rule, n, _, tot in rows:
    if (sv, se) in keys:
        total_by_rule[rule] += tot
        steps_by_rule[rule] += n      # <- both series, added together
```

Those two `n`s come from different places and mean different things:

| series | where `n` comes from | what it counts |
|---|---|---|
| `lean` | the checker's own `steps.csv` | steps the checker **executed** |
| `carcara-elab` | `counts(out, 'elab')` — `grep -oE ':rule [^ )]+'` over the proof text | **every** step in the elaborated proof |

So the printed label is *(every step in every elaborated proof)* **+** *(every step the checker ran)*. It isn't a count of anything: not of steps in the round, not of steps either tool checked.

## The magnitude

| rule | carcara-elab | lean | label printed | label ÷ lean |
|---|---:|---:|---:|---:|
| `resolution` | 163,918,182 | 25,871,718 | **189,789,900** | 7.3× |
| `cong` | 65,329,048 | 24,470,375 | 89,799,423 | 3.7× |
| `la_generic` | 18,317,280 | 1,088,043 | 19,405,323 | **17.8×** |
| `and` | 5,497,127 | 3,601,654 | 9,098,781 | 2.5× |

The inflation isn't even a constant factor — it runs from 2.5× to 17.8×, because the two series cover different populations. `carcara-elab` appears for **20,037** benchmarks (every proof Carcara accepted after elaboration); `lean` for **18,153** (essentially the proofs the checker validated — the runner only writes `steps.csv` when the checker finishes). The ~1,900 benchmarks in the gap are exactly the ones the checker timed out on, i.e. the largest proofs, which is why `resolution` and `la_generic` inflate hardest.

This is how the report ended up saying "84 M `cong` and 178 M `resolution` steps in the round" — those were round-seven-era label values, and the real checker-side counts were ~24 M and ~26 M.

## What it does *not* break

The boxes themselves. They plot `mean_ns` — per-benchmark mean step time — which comes from Carcara's own `--stats` "by rule" line on one side and the checker's per-step timings on the other. Both are genuine means. I checked whether the population mismatch distorts Carcara's distribution by restricting it to the checker's benchmarks:

```
resolution        1.40us -> 1.34us  (0.96x)      cong    0.44 -> 0.45  (1.02x)
semilattice_simp  5.22us -> 5.03us  (0.96x)      and     0.29 -> 0.29  (1.00x)
la_generic       11.00us -> 10.42us (0.95x)      trans   0.26 -> 0.27  (1.02x)
```

Nothing moves more than 5%, because Carcara's per-step cost is nearly size-independent. So the three-to-four-decade gap the figure shows is sound; only the annotation is wrong.

There's a third, cosmetic consequence: the same inflated `n` sets `mean_ns * n` as the Carcara side's "total", which is what `top = sorted(total_by_rule, ...)` ranks by. The checker's totals are three decades larger, so the ranking comes out right anyway — but it isn't right by construction.

## What I'll do

Label each group with the **checker's** step count only, and say so in the caption. That's a count of a real thing, and it's the population the surrounding prose already discusses ("`resolution` is 61% of the checker's time"). It makes `resolution` read 25.9 M instead of 189.8 M — a big visible change in the figure, and the honest one.

I'll fold that into the round-nine regeneration unless you'd rather label it with the elaborated-proof count instead. Continuing with the report edits now.

## Report and summary brought to round nine

Both PDFs rebuilt: `alethe-lean-smt.pdf` 26 pages, `summary-of-changes.pdf` 11.

Figures regenerated from `cvc5-9`/`verit-9` into `~/exp/alethe-lean/plots9/`:
the SMT-LIB scatter and cactus, the two `native` pairs, and the rule box plots.
`step-vs-shot-*` and the two Sledgehammer figures are untouched -- those corpora
have not been re-run.

### The box plot, fixed

`rule-boxplots.py` drew its two series over different populations. The
`carcara-elab` rows came from every benchmark \carcara accepts after elaboration
(20,037), the `lean` rows only from proofs the checker ran to the end (18,153),
since the runner writes `steps.csv` only then. The ~1,900 in the gap are the
largest proofs. Worse, `steps_by_rule` *added* the two series' counts and the
caption called the sum "the rule's total step count in the round": for
`resolution` that printed 189.8 M, being 163.9 M + 25.9 M, a count of nothing.
The inflation ran from 2.5x (`and`) to 17.8x (`la_generic`).

Haniel's suggestion was the fix: restrict to the proofs both check. `parse_dir`
now takes the drawn series and keeps a benchmark only when all of them have
data, and the label is read from one series. On that population the two counts
agree *exactly* -- 665,759 (benchmark, rule) pairs, zero disagreements -- since
both are counting the steps of the same proof. `resolution` now reads 26 M.

The boxes themselves were never wrong: restricting \carcara to the checker's
benchmarks moves its medians by at most 5%, because its per-step cost is nearly
size-independent. Only the annotation was.

### What changed in the prose

Report: the SMT-LIB and `native` tables; the outcome, \carcara-gap, comparison,
cactus and residue paragraphs; the rule inventory 96 -> 93 with the three
retired reconstructors; the `distinct_elim` case added to the \carcara section;
two new passages in Section 5.2, one on `distinct_elim` (5.17 -> 0.04 CPU hours,
132x, and the `native` arm showing the cost was never the kernel's) and one on
the `poly_norm` re-keying (1.12x, with `native` flat as the control); and an
explicit note that the Sledgehammer corpus is the one measurement not from the
current toolchain.

Summary: a new \Perf entry for the monomial re-keying; the `distinct_elim` row
and a paragraph on why its handler shrank; `Proj.ProjChain` dropped from it and
from the "no counterpart" list; sizes refreshed (130 commits, 11 modified
pre-existing files at +1,493/-814, `UF.lean` 516, tests 49 over 96 files).

## Turn: 2026-09-20 16:55:49 (session 18d95de2)

Both documents are at round nine and rebuilt: **report 26 pages, summary 11**.

## The box plot — fixed the way you suggested

`parse_dir` now keeps a benchmark only when *every* drawn series has data for it, and the label is read from one series instead of summing them. On that population the two counts agree **exactly** — 665,759 (benchmark, rule) pairs, zero disagreements — because both are counting the steps of the same proofs. `resolution` now reads **26 M** instead of 189.8 M.

Worth recording that the boxes themselves were never wrong: restricting Carcara to the checker's benchmarks moves its medians by at most 5%, since its per-step cost is nearly size-independent. Only the annotation was.

## Report

- **Both tables** replaced (SMT-LIB and `native`), and every prose number with them: valid 17,546 / 16,928, timeouts 1,627 / 1,916, medians 169× / 425×, the Carcara gap 476 = 261 + 150 + 37 + 28, the cactus figures.
- **Rule inventory 96 → 93**, naming the three retired reconstructors and the fact that none occurs anywhere in the corpus.
- **Two new passages in §5.2.** `distinct_elim`: 5.17 → 0.04 CPU hours, 132×, and — the part worth reading — the `native` arm paid the same 5.13 hours, so the cost was never the kernel's but the reconstructor's alignment, and only a canonical form on Carcara's side removed it. Then the `poly_norm` re-keying: 1.12×, with `native` flat at 1% as the control, and an explicit account of why the corpus figure is below the 1.34× I measured locally.
- The `distinct_elim` case added to the Carcara-changes section, and the older "pairwise conversion" note in §6 corrected to say what actually replaced it.
- **The Sledgehammer caveat made explicit**: that corpus was last run several rounds ago and is the one measurement in the report not from the current toolchain.

## Summary

New `P` entry for the monomial re-keying (with the A/B and the corpus numbers), a paragraph on why `distinct_elim`'s handler *shrank*, `Proj.ProjChain` dropped from its row and from the "no counterpart" list, and the sizes refreshed — 130 commits, 11 modified pre-existing files at +1,493/−814, `UF.lean` 516 lines, 49 tests over 96 files.

Both builds pass with `-synctex=1`; no undefined references. Nothing is committed — the working tree has the two `.tex` files, both PDFs and eight figures modified. Say the word and I'll commit.
