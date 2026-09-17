## Turn: 2026-09-16 06:55 (session 6cc35fc7)

**Round-eight smoke results, paired against round seven's second smoke pass**
(same 2,340 benchmarks per solver).

| | cvc5 | veriT |
|---|---|---|
| lean valid | 1,696 → **1,778** (+82) | 1,624 → **1,694** (+70) |
| timeout | 235 → 153 | 272 → 205 |
| error | 1 → 1 | 3 → **0** |
| holey | 0 → 0 | 2 → **1** |
| carcara valid | 1,932 → 1,932 | 1,883 → 1,882 |

**`valid → holey` 0 on both, and "was valid, now not" 0 on both.** The gate
passes.

Every non-timeout move accounted for:
- veriT `error → valid` on `QF_IDL/parity/17.200.graph` — a memory exception
  of the family I could not test locally (not in the mirror). The `cong`
  index fix reaches it.
- veriT `error → timeout` ×2, `asp/BlockedNQueens` (96,467 steps) and
  `cggmp2005-O0` (29,667): exactly what I predicted after the local runs —
  they stop exhausting memory and become ordinary timeouts. cggmp2005 takes
  688 s here and the cluster node is slower.
- veriT `holey → valid` on `UFLIA/sledgehammer/…/smtlib.1460296` — one of the
  six `th_resolution` holes, so carcara `d1823169` works on the cluster.
- veriT `timeout → none` on `QF_LRA/…/_array1.i_3_2_2.bp`: `solver_rc=124`,
  veriT itself failed to print in its 150 s this time. Solver-side
  nondeterminism, and the same benchmark's `carcara valid → no-proof`.
- The one remaining hole is `lia_generic` on `QF_LIA/prime-cone/…_7`, the
  oracle rule neither checker can close.

**The reflective checker measured.** Per-step medians understate it, because
the median step is small and the total is set by the big ones. Over the
proofs *both* rounds validate:

| | cvc5 | veriT |
|---|---|---|
| all lean rule time | 45,258 s → 23,892 s (**0.53×**) | 51,949 s → 32,959 s (**0.63×**) |
| `resolution` | 29,322 s → 7,669 s (**0.26×**) | 27,195 s → 9,106 s (**0.33×**) |
| `contraction` | 0.80× | 0.49× |
| `reordering` | 0.74× | 0.76× |
| `or` | 198 s → 628 s (**3.17×**) | 34 s → 132 s (**3.85×**) |
| `weakening` | — | 74 s → 132 s (**1.78×**) |

Whole-proof wall, new/old, on proofs both validate: median 0.987 (cvc5) and
0.992 (veriT); over 10 s, 0.969 and 0.935. The fixed ~5 s library load
dominates the median proof, which is why the whole-proof median barely moves
while the rule time halves.

**The `or`/`weakening` regression is mine and is understood.** Their old
paths are already optimal and do essentially no work: for `or` the premise's
proposition *is* the stated clause, so `fixClause` returns the premise proof
untouched, and `weakening` is one `orN_append_left` application. The
reflective path instead builds an atom context, two `Nat` lists and the
masks — pure overhead on a rule that needed none. This is the size-threshold
risk the plan named; my local A/B missed it because that proof's `or`
population is small. Cost: +429 s (cvc5) and +98 s (veriT) against
resolution's −21,653 s and −18,089 s, so about 2% of the gain. The fix is to
leave `or` and `weakening` on their direct paths and route only
`resolution`, `contraction` and `reordering` reflectively. Deferred to round
nine rather than re-deploying and re-smoking for 2%.

Staged: the full-round dry run.

## Turn: 2026-09-16 06:58:18 (session 6cc35fc7)

The smoke pass is clean and the gate holds.

| | cvc5 | veriT |
|---|---|---|
| valid | 1,696 → **1,778** (+82) | 1,624 → **1,694** (+70) |
| timeout | 235 → 153 | 272 → 205 |
| error | 1 → 1 | 3 → **0** |
| holey | 0 → 0 | 2 → **1** |

`valid → holey` is zero on both, and nothing that validated before stopped validating.

**Every non-timeout move is accounted for.** A veriT memory exception in `QF_IDL/parity` became valid, which matters because that family is not in my local mirror, so the `cong` fix is confirmed on benchmarks I could not test. Two memory exceptions became plain timeouts, `BlockedNQueens` at 96k steps and `cggmp2005`, exactly as I predicted from the local runs. One of the six `th_resolution` holes became valid, confirming the Carcara fix on the cluster. One veriT proof went to `none` because veriT itself failed to print within its 150 s that time, which also explains the single carcara drop. The one hole left is `lia_generic`, the oracle rule neither checker can close.

**The reflective checker, measured over the proofs both rounds validate:**

| | cvc5 | veriT |
|---|---|---|
| all rule time | 45,258 s → 23,892 s (**0.53×**) | 51,949 s → 32,959 s (**0.63×**) |
| `resolution` | 29,322 s → 7,669 s (**0.26×**) | 27,195 s → 9,106 s (**0.33×**) |
| `contraction` | 0.80× | 0.49× |
| `reordering` | 0.74× | 0.76× |

Whole-proof wall barely moves at the median, 0.987 and 0.992, because the fixed library load dominates a small proof. That is not a contradiction: the totals are set by the large proofs, which is also where the 152 newly valid proofs come from.

**One regression, and it is mine.** `or` costs 3.2× more on cvc5 and 3.9× on veriT, `weakening` 1.8×. Their old paths already did essentially nothing: for `or` the premise's proposition *is* the stated clause, so the old code returned the premise proof untouched, and `weakening` was a single lemma application. The reflective path builds an atom context, two lists and the masks for them, which is pure overhead. This is precisely the size-threshold risk the plan flagged, and my local A/B missed it because that proof has few `or` steps. It costs 429 s and 98 s against resolution's savings of 21,653 s and 18,089 s, so about 2% of the gain. The fix is to route only `resolution`, `contraction` and `reordering` reflectively. I'd do that for round nine rather than redeploy and re-smoke now for 2%, but say the word if you'd rather have it in this round.

**Staged**: the full-round dry run, which submits nothing and prints the same audit I ran on the smoke plan.

## Turn: 2026-09-16 09:19:06 (session 6cc35fc7)

**Nothing of mine is running.** My round-eight smoke finished, and the full round is only staged as a dry run awaiting your approval, so I have nothing queued on the cluster and nothing computing locally.

**On the cluster** the queue holds 1,979 `holes-full` jobs, 48 running and 1,931 pending. Those are not mine. They belong to your other Claude session working in `~/carcara/wt-tiago`, and I've left them alone.

**Locally** there were two stray pollers. One, `sleep 1500`, belongs to that same other session and is watching its `holes` jobs. The other was mine: the waiter I started to tell me when the smoke drained. It should have exited when the queue emptied, but the ssh control socket broke during one poll, my fallback treated that as "still running", and it kept looping every five minutes over jobs that had already finished. I've killed it. The three Lean processes are your editor's language server, running for fourteen hours.

One housekeeping point: the date rolled over while we worked. I have been appending to `CLAUDE-conversation-2026-09-15.md`, but you have `CLAUDE-conversation-2026-09-16.md` open, and it already exists with content that isn't mine. The last three entries I wrote — the deploy and verification, the smoke submission, and the smoke results — are all dated today but sit in yesterday's file. Do you want me to move those three into today's file, or leave them where they are and start using the 16th from here on?

## Turn: 2026-09-16 09:20:39 (session 6cc35fc7)

Moved, but only one entry needed it, and I owe you a correction on what I said before.

The commit timestamps settle it. The deploy, the verification, and the smoke submission were written at 22:46, 23:02 and 23:08 on the 15th, so they are correctly filed. Only the smoke-results entry, written at 06:58, belonged to the 16th. I told you all three were dated today, which was wrong.

I was also wrong that today's file held content that wasn't mine. It is mine. My final replies to you are appended to the day's file automatically, so the 16th already had the smoke-results reply from 06:58 and the running-tasks reply from 09:19. What I moved is the separate hand-written technical entry, which is more detailed than the reply and is now at the top of the file, ahead of those two.

The 15th's file ends where it should, with the smoke submission. Today's file now runs to 104 lines across three entries.

Nothing else changed, and the full-round dry run is still staged for your approval.

## Turn: 2026-09-16 09:37:45 (session 6cc35fc7)

Fixed now, in `f1d6a7f`. And chasing it turned up a second case I had not seen.

`or` and `weakening` go back to their direct paths, which were already optimal. But the synthetic sweep showed a `contraction` or `reordering` step whose premise is literally its conclusion is **8× slower** reflectively — the same degenerate shape, since reifying two clauses just to discover they match is wasted. Those now return the premise's proof before any reification, which is what the old code did anyway.

On 400 steps of each rule at width 8, reflect on against off:

| rule | before the fix | now |
|---|---|---|
| `or` | 4.26× | **0.99** |
| `weakening` | 1.82× | **0.98** |
| `contraction` | 8.05× (degenerate) | **0.95** |
| `reordering` | 0.66 | **0.67** |

Resolution is untouched at 0.81 s against 1.98 s on the profiled proof, so the win that motivated the whole thing is intact. `lake test` passes 149, and all 47 Alethe tests give identical output with the option on.

Worth saying plainly: my original local A/B could not have caught either of these. That proof contains no `or`, `weakening`, `contraction` or `reordering` steps at all, so I measured a rule set that excluded every rule that regressed. The smoke pass found the first case and a purpose-built synthetic found the second.

This changes what is deployed. `runs/alethe-lean8` carries the oleans without this fix, and the staged full-round dry run would run that. Three options: redeploy and re-smoke, which is the cautious path and costs a few hours; redeploy and go straight to the full round, since the change only removes rules from the new path and restores behavior that seven rounds have exercised; or run the full round as deployed and keep this for round nine. I lean toward the middle one, but the choice is yours.

## Turn: 2026-09-16 10:53:17 (session 6cc35fc7)

Both changes are in and verified locally. The redeploy is staged.

**The reordering pass.** Carcara's own default pipeline has always ended with it; ours had simply omitted it. It removes `reordering` steps and recomputes the conclusions of the order-sensitive rules, which is sound for us because the checker treats clauses as sets, so those steps were pure cost. On a QF_UF hardware proof:

| | without | with |
|---|---|---|
| elaborated steps | 1,862 | 1,755 |
| `reordering` steps | 107 | 0 |
| lean-smt rule time | 1.266 s | **1.040 s** |
| `contraction` | 0.050 s | 0.018 s |

Carcara still checks the elaborated proof valid, and lean-smt validates it with no trusted step. `contraction` improves as a side effect, since it no longer sees permuted clauses.

One caveat about the four proofs I had been using to test: they contain no `reordering` steps at all, so I had to generate a resolution-heavy QF_UF proof to see the pass do anything. That is the same blind spot that hid the `or` regression, and it is worth remembering when reading round eight: **elaborated step counts will be lower than round seven's**, so per-proof step counts are not comparable across the two rounds, though per-rule times still are.

**Staged**:

```
bash /home/hbarbosa/exp/alethe-lean/redeploy-alethe-lean8b.sh
```

It uploads the new runner and the `f1d6a7f` oleans over `runs/alethe-lean8`, leaving Carcara, cvc5, veriT, the sets and the rewrites file untouched, then runs both solvers through all five arms on three small benchmarks and finishes by dry-running the full driver. I folded that dry run in because only the smoke driver had been previewed, and it submits nothing.

Once that comes back clean I'll stage the full submission itself: the twelve sets, 23,328 benchmarks per solver, into `cvc5-8` and `verit-8`.

## Turn: 2026-09-16 (session 6cc35fc7) — the or/weakening fix and the reordering pass

**`f1d6a7f` — only the clausal rules that gain go through the reflective
checker.** `or` and `weakening` keep their direct paths, which already did
essentially no work. Chasing it turned up a second case the smoke could not
separate: a `contraction`/`reordering` step whose premise *is* its conclusion
was 8x reflectively, so those now return the premise's proof before any
reification (what `concludeClause` did for them anyway). Synthetic sweep, 400
steps of each rule at width 8, reflect on against off:

| rule | before | after |
|---|---|---|
| `or` | 4.26x | **0.99** |
| `weakening` | 1.82x | **0.98** |
| `contraction` (degenerate) | 8.05x | **0.95** |
| `reordering` | 0.66 | **0.67** |

Resolution on the profiled proof stays 0.81 s against 1.98 s. `lake test`
149; 47/47 Alethe tests unchanged with the option on.

Worth recording: my original local A/B could not have caught either
regression. That proof contains no `or`, `weakening`, `contraction` or
`reordering` steps at all, so I had measured a rule set that excluded every
rule that regressed. The smoke found the first, a purpose-built synthetic the
second.

**The `reordering` elaboration pass, at Haniel's direction.** The pipeline
becomes `polyeq local core-simp-rare budget reordering`. Carcara's own
default pipeline has always ended with this pass; ours had omitted it. It
removes `reordering` steps and recomputes the conclusions of the
order-sensitive rules, which is sound for our consumer because it checks
clauses as sets. Measured on a QF_UF hwbench proof (Vlunc_ab_cti_max, cvc5),
the only local proof I had with any reordering steps:

| | without | with |
|---|---|---|
| elaborated steps | 1,862 | 1,755 |
| `reordering` | 107 | 0 |
| lean-smt rule time | 1.266 s | 1.040 s |
| `contraction` | 0.050 s | 0.018 s |

carcara checks the elaborated proof valid either way, and lean-smt validates
both with no trusted step. Note for reading round eight: **elaborated step
counts are lower than round seven's**, so per-proof step counts do not
compare across the rounds; per-rule times still do.

The same blind spot bit twice here — the four Dartagnan proofs I had been
testing on contain no reordering steps either, so the pass looked like a
no-op until I generated a resolution-heavy QF_UF proof.

**Redeploy** (approved, `redeploy-alethe-lean8b.sh`): run-arms.sh md5
`8b9aec5f…` with the new pipeline, oleans at f1d6a7f, everything else
untouched. Six end-to-end head-node runs all valid with no trusted step, and
the elaborated UF sledgehammer proof is 20 steps where it was 21 — the pass
visibly active. Full driver dry run in the same chain: 24 arrays, 46,656
tasks, octa, wall 3000 s, memlimit 12000MB, into cvc5-8/verit-8, nothing
submitted.

Staged: the full submission.

## Turn: 2026-09-16 11:35:22 (session 6cc35fc7)

Both changes are deployed and verified, and the full round is staged.

```
cluster-run barrett2 'tmux new-session -d -s alean8 "bash …/submit-alethe-lean8.sh …"; sleep 90; …'
```

It submits the twelve sets for both solvers from a detached tmux, so the aggregator outlives the ssh session, then reports the submitted count, any aggregator or error lines, and the queue. Twenty-four "Submitted batch job" and two "started aggregator" is what it should say.

One thing to carry into reading the results: the reordering pass makes elaborated proofs shorter, so **per-proof step counts will not be comparable with round seven**. Per-rule times still are, for the rules that remain, and `reordering` will simply vanish from the series.

A note on how both of these were found, since it bears on how much the smoke is worth. My original local A/B ran on a proof with no `or`, `weakening`, `contraction` or `reordering` steps in it, so it measured a rule set that excluded every rule that later regressed — and the same gap made the reordering pass look like a no-op on my four test proofs until I generated a resolution-heavy one. The smoke pass caught the first regression, and a purpose-built synthetic caught the second. Neither would have surfaced from the benchmark I had been using.

**Round eight submitted** (full), 2026-09-16: 24 "Submitted batch job", two
"started aggregator" (3355334, 3355367), queue `alean8-cvc5` 23,280 PD + 48 R
and `alean8-verit` 23,328 PD. 46,656 tasks, 23,328 per solver, into
`cvc5-8` / `verit-8`.

Toolchain of record for round eight: carcara `69c92a64`, lean-smt oleans
`f1d6a7f`, run-arms.sh md5 `8b9aec5f…` (pipeline `polyeq local core-simp-rare
budget reordering`, `LEAN_REFLECT=1`). cvc5, veriT, the twelve sets and
rewrites.eo byte-identical to round seven.

## Turn: 2026-09-16 11:40:03 (session 6cc35fc7)

Round eight is running.

```
submitted: 24
started aggregator 3355334
started aggregator 3355367
alean8-cvc5   PD 23280   R 48
alean8-verit  PD 23328
```

All 24 arrays went in, 46,656 tasks, 23,328 per solver, into `cvc5-8` and `verit-8`.

**Toolchain of record**: Carcara `69c92a64`, lean-smt oleans `f1d6a7f`, runner md5 `8b9aec5f…` with the pipeline ending in `reordering` and the reflective checker on. cvc5, veriT, the twelve sets and the rewrites file are byte-identical to round seven, so the rounds compare.

I've started a waiter that polls every fifteen minutes. This one tolerates transient ssh failures instead of treating them as "still running", which is what left the last waiter spinning after the smoke had already finished.

When it lands I'll pair against round seven, check the gate, and read the per-rule series — where `reordering` should now be absent, `resolution` should show the reflective gain at full scale, and `or`, `weakening` and `contraction` should sit back at parity. I'll also look for the four benchmarks I fixed locally, the two `ConcurrencySafety-Main` parse regressions in particular, since neither was in the smoke sample.

## Turn: 2026-09-16 13:09:39 (session 6cc35fc7)

**One shell of mine is running**: the round-eight waiter, `bj9mw0m6p`, alive for an hour and a half, polling the queue every fifteen minutes.

The other four sleeping loops are not mine. One belongs to your other session, still watching its `holes` jobs. Two have been running for nearly eighteen hours with no cluster tag at all, so they predate this work and belong to some other session.

My earlier task list was misleading and I should flag why. Six task files looked "running" because none contained an exit line, but only one has a live process. Two of them I killed earlier, and their files just say `[killed]`. Two more are empty leftovers from yesterday whose shells died without recording an exit. And one vanished between two commands, because it was the listing command's own transient entry. The reliable signal is a live process, not the task file.

Round eight is making progress, though unevenly:

| | pending | running |
|---|---|---|
| `alean8-cvc5` | 14,703 | 160 |
| `alean8-verit` | 23,328 | 0 |

cvc5 is about a third through its 23,328 and veriT has not started, which is normal: the scheduler is draining the cvc5 arrays first, and the other session's `holes-full` is down to its last 14 jobs. At roughly 8,600 cvc5 tasks in ninety minutes the full round should take most of a day.

## Turn: 2026-09-16 13:13:29 (session 6cc35fc7)

Both killed. Only two polling loops remain: my round-eight waiter, and your other session's `holes` watcher, which I left alone.

They were both mine, from yesterday's debugging, and each was stuck in a loop that could never end:

- One waited for a file to gain content, but the process meant to write that file had already died, so the file stayed empty forever.
- The other waited for a Lean process to disappear using `pgrep -f 'cggmp/check.lean'`. That pattern matched the waiter's *own* command line, so it was waiting for itself to exit.

The second is a mistake worth not repeating: a `pgrep -f` poll for a string that appears in the polling command always finds itself. Matching on the process name plus reading `/proc/<pid>/cmdline`, which is what I did when auditing just now, avoids it.

They cost nothing but a wakeup every five or ten seconds, and neither touched the cluster. Round eight is unaffected and still running.

## Turn: 2026-09-16 13:27:14 (session 5c039b91)

Short answer: for proofs that went through Carcara's `polyeq` pass it is mostly redundant, and it exists for two cases that pass does not cover. Here is what the code says.

**What Carcara's pass removes.** The elaborator rewrites an `assume` only when its term is not an exact member of the problem's premises in Carcara's own term pool. In that case it replaces the `assume` with the problem's term and adds explicit steps, a polyeq equality followed by `equiv1`, that derive the proof's spelling. So a flipped equality, a regrouped n-ary application, or renamed bound variables in an `assume` do get elaborated away, and lean-smt never sees them after elaboration.

**What it cannot remove: differences its own parser erases.** Carcara normalizes numerals at the lexer. A token like `0/1` becomes the rational constant zero, and a decimal `0.0` becomes the same constant, and a division of two integer literals is folded into one rational constant during parsing. So `(assume a0 (<= x 0/1))` against `(assert (<= x 0.0))` is an exact match to Carcara. Nothing is elaborated, and the difference survives into the output, where Carcara's printer chooses its own spelling for reals. lean-smt realizes both sides through cvc5's parser, which is syntactic: the problem's `0.0` and the proof's `0/1` come back as different terms, and the driver's exact match fails. That is the case in the regression test `Test/Alethe/M0/assume_polyeq`, and it is what motivated commit 29f0fbc. Any difference that Carcara's term identity is coarser about than cvc5's parser will reach lean-smt this way, and numerals are the known instance.

**The second case: raw proofs.** `check-alethe.sh` checks the proof it is given as is, and elaborates first only under `--elaborate`. The commit message describes exactly that situation, a raw cvc5 proof of a problem written with decimals. The module mirrors Carcara's whole comparison, orientation, regrouping and alpha-renaming included, so that a raw proof is accepted on the same terms Carcara accepts it.

**Cost on the common path.** The driver tries three things before `polyeq`: an exact match on the cvc5 term, a reflexive equality, and a match on the reconstructed proposition. `polyeq` runs only after all three fail, and the definitional-equality fallback runs after it. On the sample run in the repo the assume phase was 49 ms of a 28 s run and the polyeq search itself 0 ns, meaning every one of its 1,460 assumptions matched exactly.

So the cleaner statement for the report is: `Polyeq.lean` is a fallback for representation differences that Carcara's parser hides and for unelaborated proofs, not a duplicate of Carcara's pass. The current wording, which says it decides equality "as Carcara's polyeq does", is accurate about the comparison but does not say why it is still needed. I can adjust that paragraph in `summary-of-changes.tex` if you want.

## Turn: 2026-09-16 13:39:50 (session 5c039b91)

All 48 Alethe tests and the two normalizer unit tests pass against their expected outputs, and the report rebuilds cleanly.

**Polyeq narrowed.** `Smt/Alethe/Polyeq.lean` now accepts only what Carcara's pass cannot see: two cvc5 terms are compared structurally, with numerals by value. The orientation flip, the associative regrouping and the binder pairing are gone, along with the lemma that proved flipped equalities and the two kind tables they needed. The module shrank from 202 to 145 lines, and its header now explains why the gap exists: Carcara's lexer folds `0/1`, `0.0` and a division of literals into one constant, so such an `assume` is an exact match on its side and nothing is elaborated, while cvc5's parser gives the checker two different terms. The driver comment in `Smt/Alethe/Reconstruct.lean` says the same. Two tests cover it:

- `Test/Alethe/M0/assume_polyeq` keeps the numeral cases, now including `(/ 1 3)` against `(/ 1.0 3.0)` and a numeral under a binder with the same variable name.
- `Test/Alethe/M0/assume_flipped` is new and checks that a flipped equality is rejected as not an assertion of the problem.

**Report cut to the surviving rules.** Section 5 of `docs-alethe/summary-of-changes.tex` now opens with a scope sentence and covers only the core vocabulary of Carcara's classification plus what its passes emit. The basis is the classification document and the core pass dispatch in your Carcara worktree, and the pinned revision at `69c92a64`. Removed: the premise-clausification rules, `and_intro`, `bfun_elim`, `connective_def`, `th_resolution`, `or`, `reordering`, `eq_reflexive`, `eq_symmetric`, `not_symm`, `eq_congruent_pred`, `la_totality`, `la_tautology`, `la_rw_eq`, `bounded_farkas`, `poly_simp_rel`, the quantifier rewrites and `onepoint`, and the non-linear `la_mult_pos`, `la_mult_neg`, `la_mult_sign` and the two `mult-tangent` RARE rules. Figure 3 and every table were redone accordingly, so the propositional table has 25 rules, the RARE tally is 105 rules and 113 theorems with no sorried proof, and the lemma count is 52. One sentence notes that the handlers still accept the eliminated classes for raw solver proofs, without listing them.

Two things to be aware of:

- `reordering` is removed per your instruction, but the pipeline string in the tactic and in `check-alethe.sh` does not include Carcara's `reordering` pass, and the `local` pass itself emits `reordering` and `contraction` steps. The checker keeps its handler either way.
- The premise-clausification reduction is in the classification and in your worktree's core pass but not at the pinned revision, so proofs elaborated with the pinned binary still contain `and`, `implies`, `equiv1` and the like. The report follows the classification, as you asked.

Nothing is committed. The changed files are the two Lean sources, the lemma file, the four test files, and the report with its PDF.

## Turn: 2026-09-16 13:52:27 (session 6cc35fc7)

Waiter restarted as `bj29sg50v`, polling every twenty minutes now instead of fifteen.

Round eight is progressing: cvc5 is down to 10,812 pending with 198 running, having cleared about 3,900 tasks in the last forty minutes. veriT's 23,328 have not started, since the scheduler is draining cvc5's arrays first. At that rate cvc5 finishes in roughly two hours and the whole round takes most of a day.

Nothing was lost. The waiter only watches the queue; the jobs themselves run on the cluster and were never at risk.

I also noticed a new project memory was recorded while we worked: the report should list only the rules that survive the Carcara pipeline, the core vocabulary plus emitted variants, excluding reducible rules, the `*_simplify` family, `reordering`, and non-linear rules. That fits the change we just made, since `reordering` will no longer appear in round eight's per-rule series at all. I'll apply it when I update the report.

## Turn: 2026-09-16 13:53:03 (session 6cc35fc7)

Memory is not actually low. There are 20.9 GB available of 31.6 GB, and only 2.4 GB of 30 GB swap in use. Nothing is near exhaustion, and my waiter was a bash loop with a sleep — a few megabytes.

I won't restart it a third time. Two kills in a row means the harness is reacting to something other than real pressure, perhaps free memory rather than available, and a poller that keeps getting killed is worse than none. I'll check the queue when you ask or when I next have reason to.

Round eight is still running, but the pace has changed in a way worth flagging:

| period | cvc5 tasks cleared | rate |
|---|---|---|
| first 40 min | ~3,900 | ~97/min |
| last 5 min | ~18 | ~4/min |

That drop is expected rather than alarming. The quick benchmarks are done and what remains are the long ones, each allowed up to 3,000 s, with about 200 slots running at a time. But at the current rate the remaining 10,794 cvc5 tasks would take far longer than the "most of a day" I estimated, and veriT's 23,328 have not started at all. I'd rather correct that estimate now than have you plan around it: I don't have a reliable finish time, and the honest answer is that it depends on how heavy the tail is. Round seven's tail is the best guide, and I can look up how long that round actually took if it would help.

## Turn: 2026-09-16 14:48:04 (session 5c039b91)

Yes, and I have restored the report accordingly. I had applied Carcara's full rule classification instead of the pipeline as the evaluation configures it.

**What the evaluation's pipeline actually removes.** At the pinned Carcara revision, the core pass reduces only the rules named by `--core-rules`. With the list in `Smt/Alethe/Tactic.lean` and `scripts/check-alethe.sh` that is:

- the 13 `*_simplify` rules, replayed as `rare_rewrite` and `evaluate` chains;
- the legacy ACI trio `ac_simp`, `aci_simp`, `absorb`, replaced by `semilattice_simp`, `boolean_group_simp` and `assoc_simp`;
- `reordering`, by the reordering pass;
- one more that you did not name: `bounded_farkas`. The `local` pass rewrites it in place into `la_generic`, so it never reaches the checker either.

Everything else in Carcara's reducible tier, such as the premise clausification rules, `and_intro`, `eq_symmetric`, `la_totality`, `poly_simp_rel`, the quantifier rewrites and `onepoint`, is not reduced because it is not in the list. The other legacy rules `bfun_elim`, `ite_intro` and `qnt_cnf` are not in the list either, so they survive too; the checker handles `bfun_elim` and would trust the other two.

**The report now.** Section 5 of `docs-alethe/summary-of-changes.tex` is back to the full inventory minus exactly `reordering`, `bounded_farkas`, and the non-linear `la_mult_pos`, `la_mult_neg`, `la_mult_sign` and `mult-tangent` rules. The scope paragraph states the pipeline as configured and what it removes. Figure 3, the tables and the counts were redone, so the propositional table is back to 46 rules, the quantifier table has all 12, and the RARE tally is 105 rules and 113 theorems. The PDF rebuilds without errors.

**Two details on the pipeline defaults.** The tactic and script defaults still read `polyeq local core-simp-rare budget`, without the reordering pass; today's session notes say it is being added. The `polyeq` narrowing in `Smt/Alethe/Polyeq.lean` and its tests are unchanged from my previous message and still pass.

## Turn: 2026-09-16 17:50:29 (session 6cc35fc7)

`aci_simp` and `absorb` survive, which contradicts the assumption. Checking which corpus they come from, since the sledgehammer runs are older and may have used a different configuration:

## Turn: 2026-09-16 17:50:29 (session 6cc35fc7)

The current lean-smt code handles **96 rules** across five reconstructors.

**`Arith.lean` (14)** — `bounded_farkas`, `div_by_zero_intro`, `div_intro`, `la_disequality`, `la_generic`, `la_mult_neg`, `la_mult_pos`, `la_mult_sign`, `la_rw_eq`, `la_tautology`, `la_totality`, `lia_generic`, `poly_simp`, `poly_simp_rel`

**`Clause.lean` (8)** — `contraction`, `or`, `reordering`, `resolution`, `strict_resolution`, `subproof`, `th_resolution`, `weakening`

**`Prop.lean` (46)** — `and`, `and_intro`, `and_neg`, `and_pos`, `bfun_elim`, `connective_def`, `equiv1`, `equiv2`, `equiv_neg1`, `equiv_neg2`, `equiv_pos1`, `equiv_pos2`, `false`, `implies`, `implies_neg1`, `implies_neg2`, `implies_pos`, `ite1`, `ite2`, `ite_else_intro`, `ite_neg1`, `ite_neg2`, `ite_pos1`, `ite_pos2`, `ite_then_intro`, `not_and`, `not_equiv1`, `not_equiv2`, `not_implies1`, `not_implies2`, `not_ite1`, `not_ite2`, `not_not`, `not_or`, `not_xor1`, `not_xor2`, `or_neg`, `or_pos`, `qnt_duality`, `true`, `xor1`, `xor2`, `xor_neg1`, `xor_neg2`, `xor_pos1`, `xor_pos2`

**`Quant.lean` (12)** — `bind`, `forall_inst`, `let`, `miniscope_distribute`, `miniscope_ite`, `miniscope_split`, `onepoint`, `qnt_join`, `qnt_rm_unused`, `qnt_simplify`, `sko_ex`, `sko_forall`

**`UF.lean` (16)** — `assoc_simp`, `boolean_group_simp`, `cong`, `distinct_elim`, `eq_congruent`, `eq_congruent_pred`, `eq_reflexive`, `eq_symmetric`, `eq_transitive`, `evaluate`, `not_symm`, `rare_rewrite`, `refl`, `semilattice_simp`, `symm`, `trans`

Two things I had found before you stopped me, which bear on removal. No `*_simplify` checker exists any more apart from `qnt_simplify`, and there is no `ac_simp`, `aci_simp`, `absorb`, `qnt_cnf` or `ite_intro` checker either, so most of the legacy set is already gone from the code. But `bounded_farkas` and `bfun_elim` are still handled, and across round seven and the round-eight smoke neither appears in a single elaborated proof. `aci_simp` and `absorb` do still appear, though only in the two sledgehammer result sets, which are from an older round with a different configuration, not in anything the current pipeline produced.

## Turn: 2026-09-16 18:01:31 (session 6cc35fc7)

Done in `0e167f0`. Both checkers are gone, along with `bfunAtoms`, which had no other user. `proveByCases` stays, since `evaluate` uses it to split on opaque Boolean atoms. `lake test` passes 150.

A caution worth stating: **another session is editing this repo right now.** Uncommitted changes sit in `Lemmas.lean`, `Polyeq.lean` and `Reconstruct.lean`, plus new `assume_flipped` tests and `docs-alethe/summary-of-changes.tex`, none of it mine. I checked each file I touched before committing and staged only those three, so nothing of theirs was swept in. That is also where the extra test came from: the count moved 149 → 150 because of their `assume_flipped`, not anything I added.

## Why `strict_resolution` is there

It is a distinct rule in the Alethe specification, not an alias. Plain `resolution` is checked with **set** semantics: duplicate literals collapse, and the conclusion need only match as a set. `strict_resolution` is checked with **multiset and positional** semantics. In Carcara the two differ by one type parameter, `IndexSet` against `Vec`, and the strict version then requires the conclusion to have exactly the same length and to agree literal by literal in order, with no implicit contraction and no reordering.

In lean-smt it shares the arm with `resolution` because the checker's clause machinery is set-based throughout, and `concludeClause` reconciles whatever the chain computes with the clause the step states. Treating a strict step as an ordinary one is sound: we still produce a proof of the *stated* conclusion. It is simply more permissive than the rule demands, which is the right direction for a checker — we are proving the step's conclusion, not auditing whether the producer honoured strictness.

As for whether it earns its place: it appears in **zero** elaborated proofs across every corpus, exactly like `bfun_elim`. Neither cvc5 nor veriT emits it in these twelve logics. The difference is that it costs nothing to keep, being three words in an existing match arm with no code of its own, whereas `bfun_elim` carried a reconstructor and a helper. If you want the handled-rule list to state only what the evaluation can actually produce, say so and I'll drop it too.

## Turn: 2026-09-16 18:05:37 (session 5c039b91)

`assume_flipped` is a new regression test I added under `Test/Alethe/M0/` when I narrowed the polyeq module. It checks the negative side of that change: an `assume` that differs from an assertion only by the orientation of an equality is now rejected.

The problem asserts `(= 0.0 y)` and its negation; the proof assumes `(= y 0.0)` and resolves the two. Before the change, the checker accepted that assumption through its own polyeq matching, which mirrored Carcara's and tried both orientations. Now it fails with the message that the assumption is not an assertion of the problem, and the expected file records that error. The point is to pin the new behavior: such an `assume` is Carcara's job, since its `polyeq` pass rewrites it to the assertion and adds an `equiv1` step before the proof reaches lean-smt.

The companion test `assume_polyeq` covers the positive side, the numeral spellings the checker still accepts. If you would rather not keep a test whose expected output is an error, I can drop it.

## Turn: 2026-09-16 18:08:26 (session 5c039b91)

Three commits are on `alethe-dev` from this session.

- `52235eb` narrows the polyeq matching to numeral spelling, drops the flipped-equality lemma, and adds the two tests.
- `e053b17` adds the report, `docs-alethe/summary-of-changes.tex` with its PDF.
- `b3fddb9` updates the report as you asked mid-turn: `bfun_elim`, `th_resolution` and `strict_resolution` are out, since their reconstructors were dropped, and `bounded_farkas` is back in, listed with `la_generic` and `la_tautology` under the Farkas driver. The scope paragraph now names only the `*_simplify` family, the legacy ACI rules and `reordering` as what the pipeline removes, plus the non-linear rules as left out by decision. Line counts were refreshed for the files the deletions touched.

Left uncommitted on purpose, because they belong to your other session: the `strict_resolution` removal in `Smt/Alethe/Clause.lean`, the conversation log for today, and the table reformat in `RESOLUTION-PLAN.md`. The report's clausal table already reflects the `strict_resolution` removal, so it will match once that change lands.

## Turn: 2026-09-16 18:12:56 (session 6cc35fc7)

The checker now handles **93 rules**, down from 96: `Arith` 14, `Clause` 6, `Prop` 45, `Quant` 12, `UF` 16. `bounded_farkas` is kept as you asked.

On `strict_resolution` specifically, the removal is more than cosmetic. Sharing the arm with `resolution` meant a strict step would have been accepted on the weaker reading, because this checker's clauses are sets and `concludeClause` reconciles the computed clause with the stated one. That was sound — the proof produced is of the stated conclusion either way — but it claimed coverage of a rule the checker does not actually implement. The module header now records that clauses are sets and the strict variant is out of scope.

Two things worth your attention.

The other session committed `b3fddb9`, dropping the same three rules from the report, so code and write-up agree without my touching their file. They still have uncommitted work in `Lemmas.lean`, `Polyeq.lean` and `Reconstruct.lean`; I staged only my own files each time and left theirs alone.

These removals land in round **nine**, not the round running now. Round eight is executing the oleans deployed before any of this, which still contain all three checkers. That is harmless, since the rules never appear, but it means round eight cannot confirm the removals — the first evidence will come from round nine.

## Turn: 2026-09-16 18:17:52 (session 6cc35fc7)

Two corrections, and the second one matters.

**The binaries are not all the same.** cvc5, veriT and the rewrites file are byte-identical between rounds seven and eight. **Carcara is not**: round seven ran `29a8e966`, round eight runs `69c92a64`, which is my fix for the two resolution shapes. That change is the whole reason round eight can validate the formerly trusted steps.

**`th_resolution` did show up in round seven** — six veriT proofs, one step each, all in the sledgehammer families:

```
UF/sledgehammer/Fundamental_Theorem_Algebra/uf.560771
UFLIA/sledgehammer/Fundamental_Theorem_Algebra/smtlib.1419618
UFLIA/sledgehammer/Fundamental_Theorem_Algebra/smtlib.1460296
UFLIA/sledgehammer/Hoare/smtlib.593629, 594414, 594826
```

These are the same six I diagnosed earlier in the session. Each carries exactly one "could not infer pivots" warning, and **all six were already `holey` in round seven** — the checker had a `th_resolution` arm, but the step reached it with no pivots, found none, and became a trusted step. So the arm was never actually discharging those steps; it was failing on them.

`bfun_elim` and `strict_resolution` were genuinely absent from round seven, zero steps in both solvers.

**The consequence for the deletion.** Removing the `th_resolution` checker is safe only because Carcara changed. Under round seven's `29a8e966` those six proofs would still emit a `th_resolution` step, and without the arm they would go from a trusted step to an unhandled rule — the same verdict, `holey`, but for a different reason. The deletion is therefore coupled to the Carcara pin, and `scripts/setup-alethe.sh` already pins `69c92a64`, so a fresh checkout is consistent.

One honest gap in my earlier evidence. I said the round-eight smoke showed zero `th_resolution`, which is true but weaker than it sounded: only one of the six proofs is in the tenth-sample. That one, `smtlib.1460296`, went `holey → valid`, which is direct confirmation. The other five are not sampled, so the full round eight now running is what will confirm them, and I verified all six locally earlier with the new Carcara.

## Turn: 2026-09-16 18:29:10 (session 6cc35fc7)

For `bfun_elim` and `strict_resolution`, yes — with near-certainty. Neither depends on Carcara at all. `strict_resolution` is simply never emitted by either solver, and `bfun_elim` is in the `--core-rules` set that the core pass reduces for veriT while cvc5 does not produce it. Both were zero across round seven's 46,656 proofs with the same solver binaries, and round eight changes nothing that bears on them.

`th_resolution` is different, and I should not overstate it. My fix narrowed the path that produced those six steps but did not remove it. The elaborator still has a final fallback: when greedy pivot inference fails, and the RUP reconstruction fails, and now also the stacked-negation reduction fails, it logs "could not infer pivots" and returns the step untouched — keeping the original rule name.

```rust
log::warn!("resolution '{}': could not infer pivots ({}), keeping step", …);
return Ok(Rc::new(ProofNode::Step(step.clone())));
```

So a resolution chain that none of the three inference routes can order will still surface as `th_resolution` in an elaborated proof. Round seven's six were all one shape, the unused `not_simplify` premise, and that shape is now handled. But round eight is the first full run on the new Carcara, and I have only confirmed one of those six on the cluster; the other five were outside the tenth-sample.

The practical consequence is small either way. If such a step does appear in round eight, the deployed checker still has the arm, tries resolution reconstruction, finds no pivot and records a trusted step — which is exactly what happened in round seven. After my deletion the same step would be an unhandled rule and also become a trusted step. Same verdict, different reason, no soundness difference.

So the honest summary: two are settled, and `th_resolution` is an empirical question that round eight will answer. If it does appear, that is a signal about Carcara's elaborator rather than about the checker, and the fix would belong on that side.

## Round eight results (collected 2026-09-17)

| | cvc5 | veriT |
|---|---|---|
| lean valid | 16,912 → **17,540** (+628) | 16,098 → **16,921** (+823) |
| timeout | 2,259 → 1,635 | 2,729 → 1,926 |
| error | 15 → 15 | 14 → **0** |
| holey | 2 → **0** | 17 → **10** |
| carcara valid | 19,188 → 19,190 | 18,683 → 18,685 |

**`valid → holey` 0 on both.** Losses: cvc5 3, all boundary (895.6, 861.8,
884.5 s against the 900 s limit); veriT 2, both `none` because veriT itself
failed to print a proof that run.

**The residue is now essentially the floor.** cvc5's 15 errors are all
`failed to parse`, the `ho_cong` group we are deliberately ignoring, and it
has **no holes at all**. veriT has **no errors** and 10 holes, every one of
them `lia_generic` — the oracle rule that carries no certificate and that
neither checker can close. Carcara's own rejections are unchanged in kind: 2
`equiv_simplify` (cvc5), 102 `and_simplify` and 8 `minus_simplify` (veriT).

**Every fix confirmed on the cluster:**

| benchmark | round 7 | round 8 |
|---|---|---|
| `ConcurrencySafety-Main/30_Function` | timeout | **valid 601 s** |
| `ConcurrencySafety-Main/32_pthread5` | timeout | **valid 405 s** |
| `QF_UF_h_Vlunc_ab_cti_max` | holey | **valid** |
| `QF_UF_h_BufAl_ab_fp_max` | holey | **valid** |
| the six `th_resolution` sledgehammer proofs | holey | **valid**, all six |
| `QF_IDL/parity/17.200.graph` | error (memory) | **valid 687 s** |
| `cggmp2005-O0`, `count_up_down-1-O0` | error (memory) | timeout — as predicted |

So all 8 formerly trusted resolution steps check, and the two parse
regressions are not merely recovered but faster than round *six* (769 s and
526 s there).

**The reflective checker at full scale**, over the proofs both rounds
validate:

| | cvc5 | veriT |
|---|---|---|
| all lean rule time | 132.4 h → **77.8 h** (0.59) | 138.2 h → **87.7 h** (0.63) |
| `resolution` | 87.4 h → **36.8 h** (0.42) | 73.3 h → **27.3 h** (0.37) |
| `contraction` | 1.77 h → 0.34 h (0.19) | 1.46 h → 0.48 h (0.33) |
| `reordering` | 2.70 h → **0** | 1.31 h → **0** |
| `or` | 1.01 per step | — |

`reordering` is gone entirely, as the pass intends. `or` is back at parity,
confirming the dispatch fix. `and`, `cong`, `subproof` and the rest sit at
1.00 ± 0.07.

**The deleted rules.** `bfun_elim`, `strict_resolution` and `th_resolution`
appear in **zero** round-eight elaborated proofs on both solvers, as do
`aci_simp`, `absorb` and `ac_simp`. The `th_resolution` question raised
before the round is settled empirically: carcara 69c92a64's remaining
"keeping step" fallback was never reached in 46,656 proofs.
