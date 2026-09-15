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
