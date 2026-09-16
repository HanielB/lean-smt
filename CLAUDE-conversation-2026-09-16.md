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
