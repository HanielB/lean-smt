
## Turn: 2026-09-18 00:10:26 (session 6cc35fc7)

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

## Turn: 2026-09-18 00:56:34 (session 6cc35fc7)

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

## Turn: 2026-09-18 01:41:43 (session 6cc35fc7)

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

## Turn: 2026-09-18 09:47:21 (session 6cc35fc7)

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

## Turn: 2026-09-18 13:23:26 (session c3f0aae8)

Short version: I never bumped lean-cvc5. The design pushes the solver out of the pinned library and lets the proof arrive as *text*, so the cvc5 version becomes a runtime choice.

Three pieces, in the order they matter:

**1. `smt.alethe.cvc5` — an external binary option on the tactic** (`Smt/Alethe/Tactic.lean:53`). If it's set, `solveAletheExternal` (`Smt/Alethe/Tactic.lean:99`) writes the query to a temp file and shells out to that executable with the same solver options rendered as command-line flags (`--produce-proofs --proof-format-mode=alethe …`) plus `--dump-proofs`, and takes the Alethe text from stdout (`Tactic.lean:222-228`). Set it to `/usr/local/bin/cvc5` (1.3.4-dev here) and you are checking that build's proofs. Empty string keeps the in-process lean-cvc5 solver. The file-based route (`#check_alethe P.smt2 P.alethe`) is the same idea with no tactic at all: whatever binary produced the `.alethe` file is the cvc5 you are using.

**2. lean-cvc5 is demoted to a parser.** The pinned `7e33659` / cvc5 1.3.2 is used only for `InputParser` on the problem text, so `reconstructTerm`/`reconstructSort` are reused unchanged. SMT-LIB input is stable across cvc5 versions, so a version-skewed parser is harmless — the skew that would bite (proof rules) never touches it.

**3. RARE rules dispatch by name, from `rewrites.eo`, not from the pinned enumeration.** This was the actual release hell: `rare_rewrite` steps were mapped onto lean-cvc5's `ProofRewriteRule` enum, so any rule newer than the pinned build (`ite-eq`, `or-not-refl`) was unreconstructable — a new cvc5 rule required a lean-cvc5 release. Replaced by `Smt/Alethe/Rare/rewrites.eo` (a copy of the file Carcara runs with) + `gen.py` generating `Rules.lean`, and `Smt/Alethe/Rare.lean` looking the rule up by string name. A newer cvc5's rule set now costs one copy of the `.eo` file and one theorem per new rule.

The one place the skew still shows is the *in-process* path, where 1.3.2's Alethe printer emits names current cvc5 doesn't use (`ARITH_POLY_NORM_REL` as a hole, `arith-poly-norm` as a fake RARE rule). That's handled by `compatProof` (`Tactic.lean:129`), a line-level rename applied **only** when no external binary is given (`Tactic.lean:239`) — so the external route sees the real printer output untouched, and the shim disappears if lean-cvc5 ever ships ≥ 1.3.4.

## Turn: 2026-09-18 19:47:29 (session 6cc35fc7)

Nothing of mine is left running — the only Lean processes are your editor's language server (three days old), and memory is back to 16 GB available.

For the record: the waiter that was killed was a stale `until ! pgrep …` loop watching the SharedMemory omega count. That run had already finished and I read its result (0 omega calls) before the kill, so nothing was lost. No other background work is outstanding, and the tree is still clean apart from the conversation log.

## Done: the `Nat` re-keying in `Polynorm`

Both normalizers changed, `Smt/Reconstruct/Int/Polynorm.lean` and
`Smt/Reconstruct/Rat/Polynorm.lean`:

- `cmpVar` / `bleVar` decide the variable order in one pass of `Nat.blt`,
  `Nat.beq`, `Nat.ble` -- kernel-accelerated primitives -- in place of `Var`'s
  `LE`/`LT` instances, which put a `Bool` `<` under an `Or`/`And` `Decidable`
  chain. The order itself is unchanged (integer-sorted variables before
  rational-sorted, then by index), so nothing downstream moves.
- `cmpVars` compares two monomials' variable lists three ways in one pass.
  `Polynomial.addAux` used to ask `<` and then `=` over the same two lists:
  two traversals of two instance chains at every merge step.
- `Monomial.add` loses its `m₁.vars = m₂.vars` argument, which only ever
  guarded the call; `addAux` can then match on `cmpVars` without a dependent
  motive, and `denote_addAux` recovers the equation from `cmpVars_eq`.
- `Monomial.mul.insert` matches on `bleVar` instead of `if x ≤ y`.

Measured A/B in a single process (the old merge kept alongside the new one, so
a busy machine moves both equally), on the same monomials:

| monomials | distinct vars | old | new | |
|---|---|---|---|---|
| 176 |  25 |  441 ms |  203 ms | 2.17x |
| 176 | 176 |  845 ms |  334 ms | 2.53x |
| 352 |  25 | 1009 ms |  456 ms | 2.21x |
| 704 |  25 | 1729 ms | 1035 ms | 1.67x |

End to end, the clocksynchro QF_LRA proof (6,318 steps, 1,141 `la_generic`),
the two builds run back to back:

| | old | new | |
|---|---|---|---|
| whole proof | 211.2 s | 155.3 s | 1.36x |
| `la_generic` | 179.4 s | 125.8 s | 1.43x |
| `la_generic` kernel | 167.9 s | 115.1 s | 1.46x |
| `poly_simp` (261 steps) | 1.61 s | 1.39 s | 1.16x |

Rules that do not touch the normalizer moved about 7% between the two runs
(`resolution` 1.07x, `cong` 1.08x), so read the `la_generic` figure as ~1.34x
after that drift. Below the 1.55x I estimated: the micro A/B is one variable
per monomial, while real polynomials carry constant monomials whose `vars` is
`[]`, where the old comparison was already cheap.

`lake test`: 151 tests, all passing. Nothing committed.

Note on the earlier absolute numbers in this file: the same proof took 375 s
and the same single step 455 ms of kernel when I first measured them, against
211 s and 148 ms for the *same* code today. The machine was in a slower state
then, so only today's back-to-back pairs should be compared.

## Turn: 2026-09-18 21:53:30 (session 6cc35fc7)

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
