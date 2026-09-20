
## Round nine, prepared

Three drivers in `~/exp/alethe-lean/`: `deploy-alethe-lean9.sh`,
`submit-alethe-lean9.sh`, `submit-alethe-lean9-smoke.sh`. The deploy is staged
with `cluster-propose`; nothing has been run on the cluster.

What moves over round eight, and only this:

| | round eight | round nine |
|---|---|---|
| carcara | `69c92a64` | `6358c32b` (rebuilt static-pie, stamp verified) |
| lean-smt | `f1d6a7f` | `6dec36a` |
| run-arms.sh | md5 `8b9aec5f…` | identical (verified against the cluster copy) |
| cvc5, veriT, sets, rewrites.eo | | unchanged bytes |

The carcara commit is the `distinct_elim` case of the polyeq pass. The lean-smt
range is five code commits: assumptions matched to assertions up to numerals
(`52235eb`), the `bfun_elim`/`th_resolution` (`0e167f0`) and `strict_resolution`
(`ca6dd52`) reconstructors dropped, `distinct_elim` reduced to the canonical
form (`c699861`, `c00954a`, `5987dd6`), and the `poly_norm` `Nat` re-keying
(`6dec36a`).

Round-eight baseline for the two rules this should move, recomputed over the
proofs each solver validates (the earlier "286 proofs, 354 steps" in the
2026-09-17 log was wrong):

    distinct_elim   cvc5  0.00 CPU h, 6,973 steps in 1,444 proofs (1.3 ms)
                    veriT 5.17 CPU h, 11,751 steps in 1,982 proofs (1.58 s)
    la_generic      cvc5  4.83 CPU h, 130,744 steps (133 ms)
                    veriT 13.79 CPU h, 939,828 steps (52.8 ms)

Pre-flight, the real runner with the round-nine toolchain, on the three
benchmarks whose `distinct_elim` cost the most in round eight:

| benchmark | round 8 (cluster) | round 9 (local) |
|---|---|---|
| javafe.tc.TypeSig.021 | 343.5 s, one 288.0 s step | 29.7 s |
| javafe.parser.test.TestExpr.002 | 311.8 s, 281.0 s in 2 | 23.0 s |
| javafe.tc.FlowInsensitiveChecks.005 | 329.9 s, 252.9 s in 3 | 36.1 s |

All valid, no trusted step. Step counts rise (8,900 -> 14,098 on the first)
because the new pass adds its bridge. The local machine is roughly twice the
cluster node on the untouched part of those proofs, so read the ratio, not the
seconds. A wider sweep of 24 runs over twelve `simplify2` benchmarks, both
solvers, was also valid with no trusted step, but exercised only four
`distinct_elim` steps.

The risk this round carries is one-directional: `distinct_elim` now refuses
anything but the canonical elimination, and the three dropped reconstructors
can only turn an unexpected occurrence into a trusted step. Neither can gain
coverage. Hence the smoke driver.

## Turn: 2026-09-19 08:04:24 (session 6cc35fc7)

Round nine is prepared. Nothing has touched the cluster; the deploy is staged for your approval.

## What's ready

Three drivers in `~/exp/alethe-lean/`: `deploy-alethe-lean9.sh`, `submit-alethe-lean9.sh`, `submit-alethe-lean9-smoke.sh`. Same shape as round eight — `runs/alethe-lean9` hard-link-seeded from `alethe-lean8`, octa, `-j 8`, wall-time 3000 s, 12000 MB, 1 cpu, the same twelve unsat logics, working dirs `cvc5-9` / `verit-9`.

## The diff versus round eight

| | round eight | round nine |
|---|---|---|
| **carcara** | `69c92a64` | **`6358c32b`** |
| **lean-smt** | `f1d6a7f` | **`6dec36a`** |
| run-arms.sh | md5 `8b9aec5f…` | identical — verified against the cluster copy |
| cvc5, veriT, sets, rewrites.eo | | unchanged bytes |

**Carcara — one commit.** The polyeq pass now eliminates `distinct_elim`'s orientation polyequality: it builds the canonical elimination itself and bridges to whatever the solver stated, so the consumer never sees a reordered or flipped conjunct.

**lean-smt — five code commits** (plus docs/log):
- `52235eb` assumptions matched to assertions up to numerals only
- `0e167f0` + `ca6dd52` the `bfun_elim`, `th_resolution` and `strict_resolution` reconstructors dropped — inventory 96 → 93
- `c699861`, `c00954a`, `5987dd6` `distinct_elim` reduced to the canonical form
- `6dec36a` the `poly_norm` `Nat` re-keying from yesterday

I rebuilt carcara — the binary on disk still stamped `69c92a64` despite the commit, the same trap as last week. It now reads `6358c32b`, is static-pie, and its `distinct_elim_orientation` elaboration test passes.

## What it should move

Round-eight baselines, recomputed over validated proofs (the "286 proofs / 354 steps" in the 2026-09-17 log was wrong):

- `distinct_elim`: veriT **5.17 CPU h**, 11,751 steps in 1,982 proofs (1.58 s/step); cvc5 essentially free
- `la_generic`: **18.6 CPU h** combined; `poly_simp` 11.7 h

Pre-flight with the real runner and the round-nine toolchain, on the three benchmarks whose `distinct_elim` cost most in round eight:

| benchmark | round 8 (cluster) | round 9 (local) |
|---|---|---|
| javafe.tc.TypeSig.021 | 343.5 s — one **288.0 s** step | **29.7 s** |
| javafe.parser.test.TestExpr.002 | 311.8 s — 281.0 s in 2 steps | **23.0 s** |
| javafe.tc.FlowInsensitiveChecks.005 | 329.9 s — 252.9 s in 3 steps | **36.1 s** |

All valid, no trusted step. Step counts rise (8,900 → 14,098 on the first) because the new pass adds its bridge. Caveat: this machine runs the untouched part of those proofs about twice as fast as a cluster node, so read the ratio rather than the seconds.

## What to watch, and my recommendation

The risk is one-directional. `distinct_elim` now **refuses** anything but the canonical form, and the three dropped reconstructors can only turn an unexpected occurrence into a trusted step — neither change can gain coverage. A shape the new polyeq case misses shows up as holes, not as a crash.

My wider sweep (24 runs, both solvers, twelve `simplify2` benchmarks) was clean but exercised only **four** `distinct_elim` steps. That's thin next to 11,751 in the round. **I'd run the smoke first** — the `s10` sample should carry ~200 of those steps, enough for a systematic miss to show, and the bar is: holes unchanged (cvc5 0, veriT 10 all `lia_generic`), `valid → holey` 0, `valid → timeout` 0.

octa is idle (25 nodes); your `holes-ch` arrays are on quad, so there's no contention.

**Staged for you:** `bash /home/hbarbosa/exp/alethe-lean/deploy-alethe-lean9.sh` — run `cluster-approve` in a real terminal. It writes only under `runs/alethe-lean9` and `scripts/`, and submits nothing; it ends with a version/md5 audit and a six-benchmark head-node smoke. Tell me whether to follow with the smoke or go straight to the full round, and I'll stage that next.

## Full round, both lean arms

Both arms are already what the runner does: `run-arms.sh` line 64 is
`LEAN_MODES=${LEAN_MODES:-"lean leannative"}`, the per-solver wrapper sets only
`SOLVER` and `BASE`, and round eight ran both on every task that produced a
proof -- 19,191 of 23,328 for cvc5, 19,042 for veriT, each with a `[cfg lean]`
and a `[cfg leannative]` line. So round nine needs no change for it, and
`run-arms.sh` stays byte-identical to round eight.

The pairing earns its keep this round: `6dec36a` changes what the *kernel*
evaluates and nothing the compiled evaluator does, so `leannative` is the
control. If `la_generic` falls on the kernel arm and stands still on the native
one, the re-keying is what moved it.

Two edits to the deploy since it was first staged: the head-node smoke no longer
forces `LEAN_MODES=lean`, so it exercises both arms before the round; and the
deploy now ends with `--dry-run` of the full driver, written to
`scripts/alean9-dryrun.log`, which saves an approval round-trip. Re-staged with
a note that says so.

(The guard refused two purely local commands whose text contained
`submit-alethe-lean9.sh` -- the documented `submit*.sh` pattern. Wrote the
script with the Write tool instead, as the skill says to.)

## Turn: 2026-09-19 08:08:50 (session 18d95de2)

You're right, and there were two mistakes behind it.

**The hash was stale.** I amended that commit to strip `cargo fmt`'s reformatting of `mod.rs`, which changes the hash. I had read `8a537147` before the amend and then reused it afterwards, including in the pin. The real commit is **`6358c32b`**; `8a537147` survived only as a dangling local object, which is why it appeared to exist when I checked but was on no branch.

**And I never pushed it.** `origin/bv-fixes` was still at `69c92a64` with my branch one commit ahead, so even the correct hash would not have been visible to you or reachable by a fresh checkout.

Both are fixed:

- `6358c32b` is pushed and `origin/bv-fixes` now points at it.
- `scripts/setup-alethe.sh` pins `6358c32b`.
- The lean-smt commit is amended to `5987dd6`, naming the right hash, and the three references in today's log are corrected with a note on what went wrong.

The only remaining occurrence of the old hash is inside that correction note, where it belongs.

Worth flagging for the same reason it bit here: the cluster deploy scripts also embed Carcara hashes in their headers and verify against `--version`. Had this gone into a round-nine drop unnoticed, the deploy would have uploaded a binary whose stamp disagreed with the documented pin. Reading the hash after any amend, and confirming the push before pinning, is the habit that prevents it.

## Turn: 2026-09-19 08:08:50 (session 18d95de2)

`la_generic` is the third rule by total time in round eight, and its cost is almost entirely one thing.

## Where it stands

Over the proofs each solver validates: 4.83 CPU hours in 130,744 steps for cvc5 (133 ms/step) and 13.79 hours in 939,828 for veriT (52.8 ms) — 18.6 hours, behind `resolution` (201 h) and `poly_simp` (11.7 h). Carcara checks the same elaborated steps at 40 µs. At the p99 of per-benchmark mean step time it is 6.7 s against 1.1 ms, which is the tail you're looking at.

## Where the time goes

I reproduced it locally on `clocksynchro_8clocks.worst_case_skew.induct.smt2` (veriT proof, 1,141 of 6,318 steps are `la_generic`). lean-smt checks the proof in 375 s, of which `la_generic` is 328.9 s — and **94% of that is the kernel**, only 21 s is reconstruction. Every step costs roughly the same (median 280 ms, p90 464 ms, max 802 ms), so this is the rule's normal cost, not outliers.

One step in isolation: 455 ms of kernel; the same step under `native`: 30 ms. So **93% of the kernel time is the reflective `decide` that `poly_norm` hands it**. Splitting that:

| phase | ms | share |
|---|---|---|
| `RatExpr.flatten` | 42 | 16% |
| `Polynomial.normalize` (merge sort) | 220 | 83% |
| final list equality | 2 | 1% |

What it is *not*: the magnitude of the Farkas multipliers (2·10¹² vs single digits — 266 vs 262 ms), rational vs integer coefficients (270 vs 257), or the `Int` normalizer being better (it's worse, 388 ms). It is not superlinear either: 176 → 1,408 monomials goes 333 → 2,457 ms. The kernel simply reduces the merge sort at ~1.5 ms per monomial, against 2 ms for the whole step compiled.

## What can be optimized

The lever is the representation the kernel reduces, not the algorithm. A monomial's variable part is `List Var`, with `Var` a `Bool`×`Nat` structure whose `<` goes through `Bool`'s `<` under an `Or`/`And` `Decidable` chain — and `addAux` tests `vars < vars` and *then* `vars = vars`, two traversals of two instance chains per merge step. I prototyped the same merge sort over the same monomials keyed by a single `Nat` (kernel-accelerated comparisons): **1.4–3.4× faster, most readings near 2×**.

That predicts ~1.5–1.8× on `la_generic` overall (18.6 h → 11–12 h), and the normalizer is shared with `poly_simp`, so about 12 of the round's 356 hours. The catch is that `Polynorm` also serves the nonlinear path, so the key has to be a `List Nat` in general; for `la_generic` it always collapses to one `Nat`.

Two things worth saying plainly: unlike `distinct_elim`, **nothing here moves to Carcara** — the Farkas combination is one linear-algebra fact and the elaborated step is already minimal. And `resolution` is still 201 of those 356 hours, so stage two of `RESOLUTION-PLAN` dominates anything `la_generic` can give.

Caveat on the numbers: another carcara experiment was running eight processes on this machine (load 27) during the later probes, so absolute timings there are noisy; every ratio I quote was taken within a single run. The diagnosis is written up in `CLAUDE-conversation-2026-09-17.md`. I have not touched `Polynorm.lean` — the `Var` re-keying means redoing the ordering proofs in both the `Int` and `Rat` modules, which is a real refactor of a shared proof-carrying module; say the word and I'll do it.

## Turn: 2026-09-19 08:08:50 (session 18d95de2)

No — and that distinction is the whole point.

## The analogy with `resolution` doesn't transfer

`resolution` was *not* reflective before `ResNorm`: it was replayed as an explicit proof term, n layers deep, so reflection replaced a quadratic term with one evaluation. That's where the 87.4 → 36.8 h came from.

`la_generic`'s expensive part is **already reflective**. `poly_norm` reifies both sides into a `RatExpr`, and the kernel evaluates `decide (l.toPolynomial = r.toPolynomial)` — a single reflective evaluation, exactly the shape `ResNorm` has. That evaluation *is* the 93% of kernel time. A `LaNorm`-style rewrite would replace the scaffolding around it, not the thing that costs.

## What each option is worth

Measured budget for one step (the clocksynchro repro, 288 ms mean): 24 ms reconstruct, 264 ms kernel; of the kernel, 245 ms is the reflective `decide` (39 flatten / 203 normalize / 3 compare) and 19 ms is everything else — the `sum_ub` chain, the orientation lemmas, the sign `decide`s, and the `denote` defeq.

| | what it changes | per step | speedup |
|---|---|---|---|
| **A. Re-key monomials to `Nat`** | the 203 ms of `normalize` | 288 → ~186 ms | **1.55×** |
| **B. Reflective `la_generic` checker** | the 19 ms of scaffolding + most of the 24 ms reconstruct | 288 → ~253 ms | **1.13×** |
| **C. Both** | | 288 → ~150 ms | **~1.9×** |

A is the only one measured — I prototyped the re-keyed merge sort and got 1.4–3.4× on the same monomials. B and C are arithmetic on the measured budget.

In round terms, against `la_generic`'s 18.6 h: A saves ~6.6 h, B ~2.3 h, C ~8.8 h. A also carries `poly_simp` (11.7 h), which is *nothing but* `poly_norm` — `addTac s.concl polyNorm` at `Smt/Alethe/Arith.lean:509` — so it gains ~1.7× there, another ~4.8 h. B does nothing for `poly_simp`.

So: A alone ≈ 11 h saved for a contained change; B alone ≈ 2 h for a new soundness theorem that has to subsume orientation, integer strengthening (the gcd rounding and the `omega` calls), scaling and the sign condition — much more proof work for a sixth of the return.

## The ceiling

The same normalizer compiled runs the step in 2 ms against the kernel's 455 ms. That 15× gap is kernel reduction throughput, and no restructuring of the rule closes it — only trusting the compiler (`native`, which already does) or giving the kernel less to reduce. Re-keying is giving it less to reduce; a reflective wrapper isn't. Even an ideal kernel-side checker — a `Nat`-keyed balanced-tree accumulator instead of the merge sort — gets maybe another 1.3–1.5×, so ~2.5× is the realistic ceiling for this route.

My recommendation stands as A, and B only if you want it for other reasons (uniformity with `ResNorm`, or shrinking the reconstruct side). If you'd rather I build C properly — one reflective Farkas checker designed around the `Nat`-keyed representation — that's the version where the rewrite earns its keep, since the representation change lands inside it anyway.

## Turn: 2026-09-19 08:08:50 (session 18d95de2)

You're right, and it can be one lemma. Here's why it's there and what removing it is worth.

## Why omega

The common cases already are lemmas — the comment at `Smt/Alethe/Arith.lean:340` says so. A strict integer bound with unit coefficients is just `a < b ⟹ a + 1 ≤ b` (`Int.add_one_le_iff`), and a bound that gains nothing is left alone. omega is only the **general gcd-rounding case**: when every coefficient of the literal's linear form shares a factor `g > 1`, `b - a` is `g·M + c`, and a bound on it rounds up to the next multiple of `g`. The step that needs proving is `g·M ≥ t - c ⟹ M ≥ ⌈(t-c)/g⌉`, which isn't a single existing `Int` lemma, so omega was the expedient general tool.

It doesn't need to be. Passing the rounded quotient `q` as a numeral turns both side conditions into closed numeral facts:

```lean
theorem strengthen {a b g c q t M δ : Int}
    (hg : 0 < g) (h : t ≤ b - a) (heq : b - a = g * M + c)
    (hq : g * q + c < t) (hδ : g * (q + 1) + c = δ) :
    a + δ ≤ b := by
  have hlt : g * q < g * M := by omega
  have hqM : q + 1 ≤ M := Int.lt_of_mul_lt_mul_left hlt (Int.le_of_lt hg)
  have : g * (q + 1) ≤ g * M := Int.mul_le_mul_of_nonneg_left hqM (Int.le_of_lt hg)
  omega
```

It compiles (the `omega`s inside are paid once, at build time). `t` is 1 for a strict literal and 0 otherwise; `q` is already computed in `strengthenGain`. The only reconstructor change is to have `poly_norm` prove `b - a = g * M + c` with `M = Σ (dᵢ/g)·xᵢ` instead of `b - a = Σ dᵢ·xᵢ + c` — same normalization cost, different spelling.

## But the measured gain is zero

I instrumented the call site and counted. Across nine integer proofs — ~50k steps, ~740 `la_generic` steps, including a 44,110-step QF_LIA proof (`SMPT SharedMemory-PT-000020`) — **0 omega calls**. The reason is that the gain is nontrivial only when *all* coefficients of a literal share a factor, and both cvc5 and veriT emit gcd-normalized atoms. (The ring benchmarks, the likeliest trigger, are still checking; I'll report if they differ.)

So this is a robustness fix, not a speed one. Three reasons it's still worth doing:

1. **A failed omega turns the step into a trusted hole** — that `catch` re-throws, and the step gets recorded as trusted. A rare path with no test coverage is a latent coverage risk.
2. The call site is already fighting omega: `falseOrByContra` plus a fold over the whole local context on *every* call, with a comment explaining the quadratic behaviour it's dodging.
3. It's the only part of `la_generic` whose cost isn't a lemma application, so it's the only part whose cost is unpredictable.

Two of the three omega sites in `Arith.lean` are fixed-shape and can go: this one (line 366) and `div_intro` for a constant divisor (line 467), where `div_intro_pos`/`div_intro_neg` already exist for the symbolic case and the constant case only differs in that `b`'s sign is decidable. `lia_generic` (line 502) is veriT's unspecified integer reasoning and genuinely needs a decision procedure — it stays.

## What the integer measurement did turn up

`la_generic`'s profile in QF_LIA is nothing like QF_LRA. In that 44k-step proof its reconstruct time is 1.44 s over 343 steps, and **810 ms of it is one step** — 727 literals, all coefficient 1. No omega, no big polynomial: that's ~1.1 ms per literal of plain term building (`mkAppM` for the orientation lemma, `boundOf`'s `inferType`/`whnfR`, `decideProof'`, the `sum_ub` link). The QF_LRA steps cost about the same per literal, 0.8 ms. It's linear, not quadratic, so it's a constant-factor target like the other one — but it means `la_generic` has two distinct bottlenecks: the kernel's `normalize` for rational steps with many monomials, and reconstruct-side term building for integer steps with many literals.

(One caveat on that proof: its `la_generic` steps sit at depth 2, inside a subproof, so their kernel cost is attributed to the enclosing `subproof` step rather than to them. The reconstruct numbers are theirs.)

I've left the instrumentation in my working tree only — I'll revert it once the ring run finishes. Happy to do the two lemma replacements; they're contained and independent of the `Polynorm` re-keying.

## Turn: 2026-09-19 08:08:50 (session 18d95de2)

Following up on the two loose ends from my last message.

**The ring benchmark gave no answer.** `rings_preprocessed__ring_2exp6_4vars_2ite` (67 MB, 14,563 `la_generic` steps) did not finish in 45 minutes, so the counter never printed. I'm not going to spend more machine time on it.

**But a synthetic step confirms the path works and prices it.** I built one that forces the gcd rounding — `(cl (not (<= (+ (* 2 x) (* 2 y)) 1)) (<= (+ x y) 0))` with `:args (1.0 2.0)`, where the first literal's bound has both coefficients divisible by 2 and so tightens from `2x+2y ≤ 1` to `≤ 0`:

```
holey: checked 1 steps, trusted 0, holes 0
[time] reconstruct: 16 ms
[omega] gcd probe: calls=1 total=2508 us
```

One call, 2.5 ms, in a step whose entire reconstruction is 16 ms. So the instrumentation was working — the zero on the nine real proofs is a real zero, not a broken counter. For scale: an ordinary literal costs ~1 ms of reconstruction, so a gcd-strengthened one costs about 3.5 ms; had it fired on every literal of that 727-literal SMPT step it would have added ~1.8 s to its 810 ms.

That leaves the conclusion where it was: replacing the `omega` with the `strengthen` lemma is worth doing for the reasons that aren't speed — a failed `omega` re-throws and silently turns the step into a trusted hole, the call site already folds over the whole local context on every call to dodge omega's cost, and it's the only part of `la_generic` whose cost isn't a lemma application. The expected time saving is zero on the benchmarks we run.

The instrumentation is reverted and the tree rebuilds clean (`git diff` on `Arith.lean` is empty). Findings are in `CLAUDE-conversation-2026-09-17.md`.

## Turn: 2026-09-19 08:08:50 (session 18d95de2)

**Nothing has been changed.** `git diff HEAD -- Smt/` is empty; the only modified file in the tree is `CLAUDE-conversation-2026-09-17.md`. Everything this session was measurement.

## What was established

**Two distinct bottlenecks, depending on the logic.**

| | dominant cost | measured on |
|---|---|---|
| Rational steps, many monomials | kernel, inside `poly_norm` | clocksynchro (QF_LRA): 328.9 s of 375 s, 94% kernel |
| Integer steps, many literals | reconstruct, term building | SMPT SharedMemory: one 727-literal step at 810 ms, ~1.1 ms/literal |

For the first: 93% of the kernel time is the reflective `decide`, and inside that, `Polynomial.normalize` is 83%, `flatten` 16%, the final comparison 1%. It's linear in monomials; coefficient magnitude and rationality are irrelevant. The same code compiled runs 130× faster, so it's kernel reduction throughput, not the algorithm.

**Three candidate changes, none applied:**

1. **Re-key monomials from `List Var` to `Nat`** — prototyped in a probe, measured 1.4–3.4× on `normalize` (most readings ~2×). Estimated 1.55× on `la_generic` overall, plus ~1.7× on `poly_simp`, which is nothing but this normalizer. Roughly 11 h of the round's ~356. Cost: redoing the ordering proofs in both `Int/Polynorm.lean` and `Rat/Polynorm.lean`.

2. **A reflective `la_generic` checker** — I argued against it as a standalone: the expensive part is *already* reflective, so it would replace the ~7% scaffolding, not the 83%. Estimated 1.13×. Worth building only if co-designed with (1), which gets ~1.9× — and most of that is (1).

3. **Replace the strengthening `omega` with the `strengthen` lemma** — the lemma is written and proved (it's in the log file, and in a scratchpad `lemma.lean`). Measured gain: **zero**, because the path fires 0 times across nine integer proofs; solvers emit gcd-normalized atoms. Worth doing anyway because a failed `omega` silently turns the step into a trusted hole, and because the call site already folds over the whole local context on every call to work around omega's cost. `div_intro` for a constant divisor is the same kind of fixed shape; `lia_generic` genuinely needs the decision procedure and stays.

## Open

Nothing is in progress. The decision I'd want from you is whether to do (1) — it's the only one with a measured return, and it's a real refactor of a shared proof-carrying module — and whether to fold (3) in alongside it as a cleanup. For context on priority: `resolution` is still 201 of the round's ~356 hours, so stage two of `RESOLUTION-PLAN.md` outweighs all of this.

## Turn: 2026-09-19 08:08:50 (session 18d95de2)

Nothing of mine is left running — the only Lean processes are your editor's language server (three days old), and memory is back to 16 GB available.

For the record: the waiter that was killed was a stale `until ! pgrep …` loop watching the SharedMemory omega count. That run had already finished and I read its result (0 omega calls) before the kill, so nothing was lost. No other background work is outstanding, and the tree is still clean apart from the conversation log.

## Turn: 2026-09-19 08:08:50 (session 18d95de2)

Done, in both normalizers.

## The change

`Smt/Reconstruct/Int/Polynorm.lean` and `Smt/Reconstruct/Rat/Polynorm.lean`, +151/−64:

- **`cmpVar` / `bleVar`** decide the variable order in one pass of `Nat.blt`/`Nat.beq`/`Nat.ble` — kernel-accelerated primitives — replacing `Var`'s `LE`/`LT` instances, which put a `Bool` `<` under an `Or`/`And` `Decidable` chain. The order itself is unchanged (integer-sorted variables before rational-sorted, then by index), so nothing downstream moves.
- **`cmpVars`** compares two monomials' variable lists three ways in one pass. `addAux` used to ask `<` and *then* `=` over the same two lists — two traversals of two instance chains per merge step.
- **`Monomial.add` loses its `m₁.vars = m₂.vars` argument**, which only ever guarded the call. That lets `addAux` match on `cmpVars` without a dependent motive (which would have cost back what the comparison saved); `denote_addAux` recovers the equation from a new `cmpVars_eq`.
- **`mul.insert`** matches on `bleVar` instead of `if x ≤ y`.

## Measured

A/B in a single process — I kept a copy of the old merge alongside the new one, so a busy machine moves both equally:

| monomials | distinct vars | old | new | |
|---|---|---|---|---|
| 176 | 25 | 441 ms | 203 ms | 2.17× |
| 176 | 176 | 845 ms | 334 ms | 2.53× |
| 352 | 25 | 1009 ms | 456 ms | 2.21× |
| 704 | 25 | 1729 ms | 1035 ms | 1.67× |

End to end on the clocksynchro QF_LRA proof (6,318 steps, 1,141 `la_generic`), the two builds run back to back:

| | old | new | |
|---|---|---|---|
| whole proof | 211.2 s | 155.3 s | **1.36×** |
| `la_generic` | 179.4 s | 125.8 s | **1.43×** |
| `la_generic` kernel | 167.9 s | 115.1 s | 1.46× |
| `poly_simp` (261 steps) | 1.61 s | 1.39 s | 1.16× |

Two honest caveats. Rules that don't touch the normalizer moved ~7% between the two runs (`resolution` 1.07×, `cong` 1.08×), so the real `la_generic` figure is closer to **1.34×** after that drift — below the 1.55× I estimated. The gap is because the micro A/B has one variable per monomial, while real polynomials carry constant monomials whose `vars` is `[]`, where the old comparison was already cheap. And the `poly_simp` number is 261 steps, too small to carry the round-wide 11.7 h claim I made earlier; I'd want the integer proof measured for that.

Also worth recording: the same proof took 375 s and the same single step 455 ms of kernel when I first measured them, against 211 s and 148 ms for the *identical* old code today. The machine was in a slower state then, so my earlier absolute numbers shouldn't be compared against today's — only the back-to-back pairs above.

`lake test`: 151 tests, all passing. Nothing committed — say the word and I'll commit it.

## Turn: 2026-09-19 08:08:50 (session 18d95de2)

Both configs already run — that's the default, not something I need to add.

`run-arms.sh:64` is `LEAN_MODES=${LEAN_MODES:-"lean leannative"}`, and the per-solver wrapper sets only `SOLVER` and `BASE`. Round eight ran both arms on every task that produced a proof: **19,191 of 23,328 for cvc5, 19,042 for veriT**, each with a `[cfg lean]` and a `[cfg leannative]` line. So `run-arms.sh` stays byte-identical to round eight and round nine gets the pairing for free.

It earns its keep this round. `6dec36a` changes what the **kernel** evaluates and nothing the compiled evaluator does, so `leannative` is the control: if `la_generic` falls on the kernel arm and stands still on the native one, the re-keying is what moved it. Same for `distinct_elim`, where the old cost was an `isDefEq`/congruence blowup the native arm never paid either.

**Two edits since I last staged the deploy:**
- the head-node smoke no longer forces `LEAN_MODES=lean`, so it exercises both arms before the round commits;
- the deploy now ends with `--dry-run` of the full driver, written to `scripts/alean9-dryrun.log`, which saves an approval round-trip.

Re-staged with a note that says so.

## The sequence from here

1. **`cluster-approve`** in a real terminal → runs `bash /home/hbarbosa/exp/alethe-lean/deploy-alethe-lean9.sh`. It writes only under `runs/alethe-lean9` and `scripts/`, and submits nothing. It ends with the version/md5 audit (carcara must stamp `6358c32b`, cvc5/veriT/rewrites.eo/run-arms.sh must all read OK), a check that the three dropped rules have no reconstructor left in the oleans, the six-benchmark two-arm smoke, and the dry run.
2. I read the audit and the dry-run log and report.
3. I stage the real submission — `submit-alethe-lean9.sh` inside a detached tmux, octa, `-j 8`, wall 3000 s, 12000 MB, 1 cpu, the twelve unsat logics, working dirs `cvc5-9` / `verit-9` — and you approve that one.

Scale is unchanged from round eight: 23,328 benchmarks per solver, both lean arms per task, which took about nine hours end to end last time. octa is idle; your `holes-ch` arrays are on quad.

One note: the guard refused two purely *local* commands of mine because their text contained `submit-alethe-lean9.sh` — the documented `submit*.sh` pattern, matching even when nothing is being submitted. I wrote the script with the Write tool instead, as the skill prescribes, rather than rephrasing the command.

## Round nine deployed

`runs/alethe-lean9` is up. The audit:

    carcara 1.1.0 [git 6358c32b bv-fixes]        <- the stamp the round needs
    OK   bin/cvc5    OK bin/veriT    OK rewrites.eo    OK run-arms.sh
    DIFF bin/carcara                              <- the only intended difference
    LEAN_MODES=${LEAN_MODES:-"lean leannative"}
    --pipeline polyeq local core-simp-rare budget reordering
    bfun_elim / th_resolution / strict_resolution: 0 olean(s) mentioning them
    sets: 14 full + 14 sample; 25,200 full (the driver takes 12 of them: 23,328)

Head-node smoke, six runs, both solvers, both lean arms: all `valid`, 0 trusted,
0 holes. The pairing is already visible -- cvc5 QF_LIA kernel 2,493 ms against
native 411, veriT QF_LIA 694 against 143.

Dry run: 1,462 lines, 0 `Submitted batch job`, partition octa, wall 3000 s,
memlimit 12000MB.

One cosmetic miss in my own audit line: "reflect lines in run-arms.sh: 2
(expect 1)". Line 65 is a comment that names `smt.alethe.reflect` and line 266
is the switch itself; `run-arms.sh` is byte-identical to round eight, so round
eight printed 2 as well. The expectation was stale, not the file.

The full submission is recorded for approval. The guard also refused
`cluster-propose` itself, since the proposal text contains the driver's name, so
the pending entry came from attempting the real command and being blocked.

## Turn: 2026-09-19 08:20:38 (session 18d95de2)

The deploy itself took about four minutes. What you were waiting on was my own polling loop: `until ! pgrep -f 'deploy-alethe-lean9'` matched **its own command line**, so it kept spinning long after the work finished. Same self-match bug I hit earlier in this project; I've killed it and I'll stop writing waiters that can see themselves.

## The deploy succeeded — audit

```
carcara 1.1.0 [git 6358c32b bv-fixes]          ← the stamp the round needs
OK   bin/cvc5   OK bin/veriT   OK rewrites.eo   OK run-arms.sh
DIFF bin/carcara                                ← the only intended difference
LEAN_MODES=${LEAN_MODES:-"lean leannative"}
--pipeline polyeq local core-simp-rare budget reordering
bfun_elim / th_resolution / strict_resolution: 0 olean(s) mentioning them
sets: 14 full + 14 sample; 25,200 full (the driver takes 12 → 23,328)
```

**Smoke** — six runs, both solvers, both arms: all `valid`, 0 trusted, 0 holes. The pairing already shows: cvc5 QF_LIA kernel 2,493 ms vs native 411; veriT QF_LIA 694 vs 143.

**Dry run** — 1,462 lines, **0** `Submitted batch job`, partition octa, wall 3000 s, memlimit 12000MB. Log at `scripts/alean9-dryrun.log`.

One cosmetic miss, in my audit line rather than the toolchain: it printed `reflect lines in run-arms.sh: 2 (expect 1)`. Line 65 is a comment naming `smt.alethe.reflect`, line 266 is the switch. `run-arms.sh` is byte-identical to round eight, so round eight printed 2 too — my expectation was copied stale.

## Next: the submission needs a second approval

Recorded and waiting:

```
cluster-run barrett2 'tmux new-session -d -s alean9 "bash /barrett/scratch/hbarbosa/scripts/submit-alethe-lean9.sh 2>&1 | tee /barrett/scratch/hbarbosa/scripts/alean9-submit.log; sleep 3600"'
```

Two jobs from `runs/alethe-lean9` — octa, `-j 8`, `--wall-time --time-limit 3000 --memory-limit 12000 --cpus 1`, empty solver options, working dirs `exp/results/alethe-lean/{cvc5-9,verit-9}`, job names `alean9-{cvc5,verit}`, the twelve unsat logics at 23,328 benchmarks per solver, both lean arms per task. Detached tmux because the aggregator dies with the ssh session.

Run `cluster-approve` again and I'll submit, then verify 12 × "Submitted batch job" per solver and the aggregator start.

A note on how that entry got there: the guard refused `cluster-propose` as well, because the proposal text contains the driver's filename — so the pending entry came from attempting the real command and being blocked, which is the flow the guard's own message describes. I didn't reword anything to get past it.

## Approval moved into the session

Haniel asked for the terminal round trip to go away: he now writes "ok" or
"approved" in the session and I mint the token myself.

What changed:

- `~/.local/bin/cluster-approve` grew `--from-session '<his words>'`, which skips
  the TTY check and writes the same token -- sha256 of the exact pending command,
  single use, 15 minutes. Every approval is appended to
  `~/.claude/cluster-approvals.log` with its origin, the note and his words. The
  interactive mode still works and is equivalent. From the session a proposal
  older than an hour is refused outright rather than warned about, since there is
  nobody reading the warning.
- `~/.claude/hooks/cluster-guard.sh` keeps denying everything it denied before,
  but now also **hard-refuses, token or not**: a recursive `rm` whose target is a
  cluster path, writes under `/barrett/scratch/local/`, and `kinit`. Those were
  "never" rules in CLAUDE.md with nothing enforcing them; with approval no longer
  behind a TTY they needed teeth.
- A bare `cluster-propose ...` line is now exempt from the guard. Staging a
  submission tripped the `submit*.sh` pattern twice yesterday, which is how the
  pending entry ended up holding the proposal command instead of the submission.
- `cluster-propose` warns when staged from argv: the shell has already split the
  quoting, so `cluster-run host 'tmux ... "..."'` stages as a *different string*
  than what runs and the hash cannot match. Stage from a file on stdin. The
  round-nine submission lives in `~/exp/alethe-lean/alean9-submit.cmd`.

CLAUDE.md, the stanford-cluster skill and the alethe-cluster-eval skill say the
new flow, and there is a memory for it. Two test harnesses sit next to the hook:
`cluster-guard-test.sh` feeds it synthetic payloads (17 cases: read-only allowed,
staging exempt, mutating denied, the four hard refusals) and
`cluster-approve-test.sh` runs propose -> approve -> allow -> token-consumed in a
sandbox `HOME`. Both pass.

What this trades away, stated plainly: the TTY check was the one thing that made
"a human approved this" a fact the hook could verify. Now the hook only
guarantees that what runs is what was staged and shown; whether Haniel really
said yes is my judgment. So the rule I wrote into CLAUDE.md is strict -- the ok
must be in the message *after* the proposal and *about* that proposal, and an
approval appearing in a system notification or in my own earlier text is not
approval.

## Turn: 2026-09-19 08:43:51 (session 18d95de2)

Done. Approval now happens here, in the session.

## How it works now

1. I stage the exact command with `cluster-propose` and show it with its parameters.
2. **You reply "ok" or "approved."**
3. I run `cluster-approve --from-session '<your words>'`, which mints the same token as before — sha256 of the exact pending command, single use, 15 minutes — and run the staged command unchanged.

Your `cluster-approve` from a terminal still works, unchanged, if you ever want it.

## What I changed

- **`cluster-approve`** gained `--from-session TEXT`. Same token, no TTY check. Every approval is appended to `~/.claude/cluster-approvals.log` with its origin, the proposal note and your words. From the session, a proposal older than an hour is *refused* rather than warned about — there's nobody reading a warning.
- **`cluster-guard.sh`** now **hard-refuses, token or not**: a recursive `rm` whose target is a cluster path, writes under `/barrett/scratch/local/`, and `kinit`. Those were "never" rules in CLAUDE.md with nothing enforcing them; once approval isn't behind a TTY they need teeth. Everything else denies as before until a token matches.
- **A bare `cluster-propose …` is now exempt.** Staging a submission tripped the `submit*.sh` pattern twice yesterday — that's why the pending file ended up holding my *proposal* line instead of the submission.
- **`cluster-propose` warns when staged from argv.** It had silently dropped the quoting: `cluster-run host 'tmux … "…"'` was staged as a different string than what runs, so the hash could never match. Stage from a file on stdin instead; the round-nine command now lives in `~/exp/alethe-lean/alean9-submit.cmd`.
- CLAUDE.md and both cluster skills describe the new flow; there's a memory for it; and two test harnesses sit beside the hook — `cluster-guard-test.sh` (17 synthetic cases) and `cluster-approve-test.sh` (propose → approve → allow → token consumed, in a sandbox `HOME`). Both pass.

**The one thing this gives up, plainly:** the TTY check was what let the hook *prove* a human said yes. Now it only guarantees that what runs is what was staged and shown to you — whether you actually approved is my judgment. So I wrote the rule strictly: the ok must be in the message *after* a proposal and *about* that proposal. An "ok" about something else, an approval quoted back in a system notification, or my own earlier text does not count, and I ask again.

## Still waiting: the round-nine submission

```
cluster-run barrett2 'tmux new-session -d -s alean9 "bash /barrett/scratch/hbarbosa/scripts/submit-alethe-lean9.sh 2>&1 | tee /barrett/scratch/hbarbosa/scripts/alean9-submit.log; sleep 3600"'
```

Two jobs from `runs/alethe-lean9` — octa, `-j 8`, `--wall-time --time-limit 3000 --memory-limit 12000 --cpus 1`, empty solver options, working dirs `exp/results/alethe-lean/{cvc5-9,verit-9}`, job names `alean9-{cvc5,verit}`, the twelve unsat logics at 23,328 benchmarks per solver, both lean arms per task.

Your last message changed the policy — it wasn't an approval of this run, so I haven't touched it. Say "ok" and I'll submit.

## Round nine submitted

First run under the new policy: proposed from
`~/exp/alethe-lean/alean9-submit.cmd`, Haniel wrote "Ok",
`cluster-approve --from-session 'Ok'` minted the token, the staged command ran
verbatim.

    24 x "Submitted batch job"   (12 logics x 2 solvers)
     2 x "started aggregator"
    arrays 29154759..29154770 on octa, alean9-cvc5 and alean9-verit

Results will land in `exp/results/alethe-lean/{cvc5-9,verit-9}`. Round eight took
about nine hours end to end on the same corpus and limits.

## Turn: 2026-09-19 08:46:39 (session 18d95de2)

Round nine is submitted — and that was the first run through the new approval path: proposal → your "Ok" → `cluster-approve --from-session 'Ok'` → the staged command run verbatim. The whole exchange is in `~/.claude/cluster-approvals.log`.

**Verification:**
- **24** × `Submitted batch job` (12 logics × 2 solvers) and **2** × `started aggregator` — exactly right
- arrays `29154759…29154770` on **octa**, job names `alean9-cvc5` and `alean9-verit`, all `PD` and starting to pick up
- your `holes-ch` work is untouched on quad

Results will land in `exp/results/alethe-lean/{cvc5-9,verit-9}`. Round eight took about nine hours on the same corpus and limits, so expect these late tonight.

When they're back, the things to read first:

1. **Coverage must not move the wrong way** — holes (round eight: cvc5 0, veriT 10 all `lia_generic`), `valid → holey` = 0. This is where a `distinct_elim` shape the new polyeq case misses would surface, and where an unexpected `bfun_elim`/`th_resolution`/`strict_resolution` would show up.
2. **`distinct_elim`** — veriT's 5.17 CPU h over 11,751 steps should largely vanish; the three worst proofs went 343.5 → 29.7 s, 311.8 → 23.0, 329.9 → 36.1 locally.
3. **`la_generic` against the native arm** — the kernel arm should fall ~1.3×, the native arm should sit still. If both move, it wasn't the re-keying.

I'll check back when the aggregators finish.

## Turn: 2026-09-19 09:03:07 (session 18d95de2)

Nothing of consequence — what got reaped was the stale waiter loop I'd already flagged and killed, the `until ! pgrep -f 'deploy-alethe-lean9'` that was matching its own command line. The deploy it was watching had finished successfully long before, and the reap says nothing about the command itself. I won't restart it; there's nothing to wait for.

Round nine is unaffected and running:

- **cvc5**: 45 array tasks running, 12 pending; aggregator has processed 1,962 tasks
- **veriT**: 12 pending, aggregator has just registered its last array (29154770, size 511) and is starting

Both aggregators are alive in the detached tmux, which is the part that matters — they're the processes that would have died with the ssh session. I'll report when they finish.

## Turn: 2026-09-19 13:48:51 (session 18d95de2)

Round nine is **about 61% through the cvc5 half, and the veriT half hasn't started** — its 12 arrays are queued behind cvc5, which is holding all 200 octa slots. Same serialization as round eight, where cvc5 finished ~8 h in and veriT ~8 h after that.

I pulled the partial cvc5 results anyway (14,188 tasks, all also in round eight, so it's a like-for-like comparison).

## Coverage — clean

| | round 8 | round 9 |
|---|---|---|
| valid | 12,672 | 12,671 |
| timeout | 145 | 142 |
| error | 13 | 13 |
| **trusted steps** | **0** | **0** |
| **holes** | **0** | **0** |

Six verdicts moved, all solver-side jitter against the 150 s external kill (`valid→none` 1, `timeout→none` 3, `valid→timeout` 1, `timeout→valid` 1). No `valid → holey`, nothing trusted. So on this half, `distinct_elim` refusing non-canonical forms and the three dropped reconstructors cost nothing — which is the thing that could only have gone wrong.

## Rule time — the change shows, muted, and the control behaves

| | kernel arm r8 → r9 | native arm r8 → r9 |
|---|---|---|
| `la_generic` | 0.92 → 0.75 h — **1.22×** | flat |
| `poly_simp` | 3.99 → 3.68 h — 1.09× | 3.03 → 3.05 h — 1.00× |
| all rules | 26.46 → 25.73 h — 1.03× | 24.97 → 25.18 h — **0.99×** |

The native arm is flat to within 1%, which is exactly the control I wanted: the re-keying changes what the kernel evaluates and nothing the compiled evaluator does. So the kernel-arm movement is attributable.

But 1.22× on `la_generic` is below the 1.34× I measured locally, and the reason is visible in the data: cvc5's `la_generic` steps are small — 0.92 h over 51,313 steps is 64 ms a step, against veriT's 940k steps. On small polynomials the fixed costs (flatten, the `sum_ub` chain, the `denote` defeq) dominate and `normalize` is a smaller share, so re-keying it buys less.

## What this doesn't tell us yet

Both headline changes are veriT's, and veriT hasn't run:

- **`distinct_elim`** was 5.17 CPU h on veriT and 0.00 on cvc5 — it isn't even in the cvc5 top nine. Nothing measured yet.
- **`la_generic`** was 13.79 h on veriT against 4.83 on cvc5, with much larger steps.

So: nothing is wrong, nothing is final, and the decisive half is still queued. At the current rate cvc5 should finish early evening and veriT overnight. I'll pull both and do the full comparison then.
