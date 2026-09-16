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
