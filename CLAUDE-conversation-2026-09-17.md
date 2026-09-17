
## Turn: 2026-09-17 07:18:37 (session 6cc35fc7)

Round eight is complete, and it is the best round so far.

| | cvc5 | veriT |
|---|---|---|
| valid | 16,912 → **17,540** (+628) | 16,098 → **16,921** (+823) |
| timeout | 2,259 → 1,635 | 2,729 → 1,926 |
| error | 15 → 15 | 14 → **0** |
| holey | 2 → **0** | 17 → **10** |

`valid → holey` is zero on both. cvc5 loses three proofs, all sitting between 862 and 896 seconds in round seven against a 900 second limit. veriT loses two, both because veriT itself failed to print a proof that run.

**The residue is now essentially the floor.** cvc5 has no holes at all, and its 15 errors are the `ho_cong` group you told me to set aside. veriT has no errors, and its 10 holes are every one `lia_generic`, the oracle rule that carries no certificate and that Carcara cannot check either.

**Answering the question you asked before the round**: none of the three deleted rules appear in a single round-eight elaborated proof, on either solver. `th_resolution` was the one I could not promise, since Carcara still has a "keeping step" fallback for chains it cannot order. That fallback was never reached across 46,656 proofs, so the deletion is settled empirically rather than by argument.

**Every fix confirmed on the cluster.** The two parse regressions came back not merely recovered but faster than round *six*: `30_Function` at 601 s against 769 s there, `32_pthread5` at 405 s against 526 s. All eight formerly trusted resolution steps now check. The `QF_IDL/parity` memory failure validates in 687 s. The two Dartagnan memory failures became timeouts, exactly as I predicted from the local runs.

**The reflective checker, at full scale**, over proofs both rounds validate:

| | cvc5 | veriT |
|---|---|---|
| all rule time | 132.4 h → **77.8 h** | 138.2 h → **87.7 h** |
| `resolution` | 87.4 h → **36.8 h** (0.42) | 73.3 h → **27.3 h** (0.37) |
| `contraction` | 0.19 | 0.33 |
| `reordering` | **eliminated** | **eliminated** |

`or` is back at parity, so the dispatch fix held, and every other rule sits within 7% of round seven.

The natural next step is updating the report to round eight, but the other session has `summary-of-changes.tex` and three source files in flight, so tell me when you want me to touch `docs-alethe` and I'll coordinate rather than collide.

## Turn: 2026-09-17 10:04:53 (session 6cc35fc7)

The figure copy was inside the command the guard blocked, so it never ran and the rebuild used round-seven figures. Fixing:

## Turn: 2026-09-17 10:04:53 (session 6cc35fc7)

The report is on round eight, commit `7895e7e`. PDF rebuilt at 25 pages.

**What changed in substance**

Both tables and the six SMT-LIB and native figures are regenerated. The Sledgehammer figures are untouched, since that corpus did not rerun.

Section 2.2 no longer *proposes* the reflective resolution checker; it describes and measures it. Over the proofs both rounds validate, `resolution` falls from 87.4 to 36.8 CPU hours on cvc5 and from 73.3 to 27.3 on veriT, and the whole rule time from 132.4 to 77.8 and 138.2 to 87.7, with verdicts unchanged. It also records which clausal rules deliberately do *not* go through it, and why, and that `reordering` has left the figure because Carcara's pass now removes those steps. The figure confirms this: `reordering` is absent from the top sixteen and `contraction` has dropped near the bottom.

Section 3.2 gains the three defects found this week — the parser's quadratic binding environment, the quadratic closed-term check, and the quadratic premise scan in `cong` — and now reports the memory exhaustions as gone rather than as a standing residue.

The "what is left" paragraph is rewritten. cvc5 leaves no proof with a trusted step and veriT ends in no error; the residue is 10 `lia_generic` holes and the 15 higher-order proofs you set aside.

**Two things worth noting.** The checker's total CPU went *up*, 177 to 212 hours and 167 to 223, even though it is faster per proof. That is because the 628 and 823 newly validated proofs are the expensive ones, and I said so in the text rather than leaving it looking like a regression.

Also, the build guard caught something useful. My first rebuild bundled the figure copy into a command the guard rejected for missing SyncTeX, so the copy never ran and the PDF was rebuilt against round-seven figures. I noticed when the figure checksums did not match, copied them properly and rebuilt. The committed PDF has the round-eight figures.

## Turn: 2026-09-17 14:12:09 (session 6cc35fc7)

Added to the report as `5fd6abc`, PDF rebuilt.

To restate the answer plainly: the median is the typical proof and the total is the heavy tail, and for this rule those are almost disjoint populations. The typical proof has a few dozen resolution steps, where the reflective path's setup cost cancels most of its advantage, so it gains about 12%. The proofs that hold the time have thousands, and they gain about 2.6×. Since the figure plots a median over benchmarks, it shows you the first number, and the total shows you the second.

The check that makes this trustworthy rather than a story: the resolution step count over the shared proofs is the same in both rounds to within two steps out of six million, so nothing was removed, and the per-proof ratio sits below 1 across the whole distribution rather than only at the top.

It also matters for how the round should be read. Coverage tracks the tail, not the median, which is why 628 and 823 proofs crossed from timeout to validated while the whole-proof medians moved hardly at all. The report now says all of this next to the figure instead of leaving the two numbers to contradict each other.

## Turn: 2026-09-17 14:15:38 (session 6cc35fc7)

Rebuilt: 10 pages, no errors, no undefined references, four spacing warnings. The output is byte-identical to the committed PDF, so there is nothing to commit — the version in the repo was already current with its source and already carried SyncTeX.

I also checked the content against the code before rebuilding, since I changed the code after that document was written. It is consistent: it records `bfun_elim`, `th_resolution` and `strict_resolution` as dropped reconstructors, "no corpus of the evaluation emitting them after the pipeline", which round eight has now confirmed — all three appear in zero elaborated proofs across 46,656.

One thing that document does not yet reflect: it was written before round eight finished, so where it describes the evaluation it is still describing round seven's state. The main report is the one I brought to round eight. If you want the summary aligned too, tell me and I'll go through it, though it is the other session's document and I'd rather not edit it in parallel with them without knowing they're done.

## Turn: 2026-09-17 14:24:07 (session 6cc35fc7)

## The `distinct_elim` tail, diagnosed

It is entirely veriT's. cvc5 spends essentially nothing on the rule: 6,973 steps, under a hundredth of a CPU hour, worst case 34 ms. veriT spends **5.17 CPU hours** on 11,751 steps, and **all of it** sits in **286 proofs** — 222 in `simplify2`, 52 in `boogie`, the rest in `sexpr` and one hardware family. Between them those 286 proofs contain just **354 distinct_elim steps**, so the cost is a few hundred individual steps, each taking seconds to minutes. For the median proof in that group the rule is **67% of all its rule time**, and for the worst 97%.

I reproduced the heaviest one, `javafe.tc.TypeSig.021`. Its single `distinct_elim` step takes **73.3 seconds of the proof's 84.3 seconds of reconstruction** — 87% of the work for one step out of 8,900.

**The mechanism has three parts.**

The rule rewrites `(distinct x₁ … x₁₄₈)` into the conjunction of all 10,878 pairwise disequalities. The reconstructor has a fast path, `distinctCongEq`, which walks both conjunctions in lockstep and proves them equal by congruence when the pairs sit in the same positions and differ only in orientation. I measured that path: it is linear, about 8 µs per pair, so it would handle 10,878 pairs in roughly 90 ms.

It never gets the chance. veriT emits the pairs in lexicographic order for the first **6,396** of them and then diverges — one element, `T_javafe.ast.VarInit`, is displaced, and every subsequent position is shifted. Because the walk is all-or-nothing, it discards the 6,396 pairs it had already matched and returns nothing.

Control then falls to the general conversion, which for each of the 10,877 target conjuncts calls `src.findIdx?` — a **linear scan** over the 10,878 source conjuncts. That is about 59 million expression comparisons, and at roughly 1.2 µs each it accounts for the 73 seconds almost exactly.

**This is the same bug class I fixed last week in `cong`**, where premise alignment scanned the whole premise list per argument and exhausted 10 GB on an 8,449-conjunct congruence. The remedy there was to index the premises by their two sides in a hash map, and the identical remedy applies here: index the source conjuncts by their unordered pair, turning the scan into a lookup and the conversion linear. On this proof that should take the step from 73 seconds to well under one, and it would recover essentially all 5.16 CPU hours.

A second, smaller improvement is available in the fast path: making it resynchronise instead of bailing at the first positional mismatch, so the common case of a single displaced element does not cost the whole conjunction. But the indexing fix alone removes the quadratic behaviour, and I would do that first and measure before deciding whether the second is worth the complexity.

I have not changed any code — you asked for a diagnosis, and this is where it stands.

## Turn: 2026-09-17 14:42:15 (session 6cc35fc7)

Carcara does not reject it because the step is perfectly canonical. My earlier diagnosis was wrong, and here is the correction.

**Carcara's `distinct_elim` is strictly positional**: for `i < j` in lexicographic order it requires conjunct `k` to be `(not (= aᵢ aⱼ))` or that pair flipped. Parsed properly, veriT's conjunction satisfies this exactly — all 10,878 pairs at their lexicographic positions, 8,280 in the same orientation and 2,598 flipped. My first pass used a regex that silently dropped one conjunct, which shifted every position after it and produced an apparent mismatch at index 6,396. That was an artefact of my extraction, not a property of the proof.

**The real cause is a spelling difference, not an ordering one.** lean-smt reconstructs `(distinct x…)` through `buildDistinct`, which emits `Ne x y`. The proof's conjunction is written `(not (= x y))`, which reconstructs as `Not (Eq x y)`. Those are definitionally equal, since `Ne` is *defined* as `¬(a = b)`, but they are not syntactically equal.

`distinctCongEq`'s leaf test tries syntactic equality first, which fails, then tries the flipped-pair case. For a pair in the *same* order that flip test does not fire either, so it returns nothing — at conjunct **zero**. I confirmed this directly:

| left spelling | right spelling | `distinctCongEq` |
|---|---|---|
| `Ne` | `Not (Eq …)` | **none, 0 ms** |
| `Ne` | `Ne` | some, 12 ms for 1,770 pairs |

So the fast path aborts on the first conjunct, and control falls to the general conversion, whose per-conjunct `findIdx?` is a linear scan over all 10,878 sources — about 59 million expression comparisons, which is the 73 seconds. The `isDefEq` guard ahead of it does not save the step either, because 2,598 pairs really are flipped and `Ne a b` is not definitionally `Ne b a`, so it fails at the first flip, index 9.

**What this changes about the fix.** The indexing change I proposed still helps, but it is no longer the main point. The direct fix is in the leaf test: compare the two *pairs* rather than the two propositions, so that a same-order pair is closed by reflexivity up to unfolding and a flipped one by the symmetry lemma. That lets the linear path run and should take this step from 73 seconds to roughly 90 milliseconds, recovering essentially all 5.16 CPU hours across the 286 affected proofs.

Two lessons I'd rather state than bury. The tail was not veriT emitting anything unusual, so nothing is to be fixed on the solver or Carcara side. And I should have measured before asserting the ordering claim — the probe that settled it took two minutes, while the regex that misled me looked authoritative.

## Turn: 2026-09-17 15:45:26 (session 6cc35fc7)

Here is where this stands, including one thing I got wrong and one that stopped me.

**Done in lean-smt** (`c699861`, `c00954a`). The leaf test now compares the *pairs* rather than the propositions, so the `Ne` versus `¬(… = …)` spelling no longer aborts the fast path at conjunct zero. Reconstruction of the worst step fell from 73.3 s to 391 ms. I also indexed the pair lookup in the projection route, removing the quadratic scan there; the proof term is unchanged, so that is purely build time. Tests pass 150 after each.

**Your Carcara instruction cannot be done the cheap way, and I should tell you why.** Canonicalising the orientations inside the conjunction is observable downstream. In the proof I studied, the conjunction is consumed by `and` steps that project conjuncts **by index**:

```
(step t1308 (cl @p_16484) :rule and :premises (t140) :args (6396))
(step t1309 (cl @p_18747) :rule and :premises (t140) :args (7528))
```

Their stated conclusions are whatever orientation veriT wrote at those positions. So a uniform substitution of the canonical conjunction — the trick `canonicalize_skolems` uses and which I had hoped to copy — would break those steps. Canonicalising in the polyeq pass therefore means either rewriting consumers transitively, or emitting a bridge from canonical to stated, and the bridge just relocates the cost. I did not implement either, because both are real designs rather than small changes and the second may not pay.

**What the canonical form would be worth, measured**: if the orientations were canonical, the whole equality is one ascribed `Eq.refl` that the kernel checks in **46 ms** at 10,878 conjuncts, scaling linearly. That is the 800× still on the table, and it is why your instinct about where to fix this is right even though the route is harder than it looked.

**I have not made lean-smt fail on non-canonical order**, deliberately. Today 2,598 of the 10,878 pairs are flipped, so failing now would turn those 286 proofs into trusted steps — a regression — until the Carcara side lands. That ordering has to be Carcara first.

**One correction and one caveat.** My leaf fix made the step 73.7 s → 37.7 s, not to nothing: the congruence chain it builds is cheap to construct but costs the kernel 37 s, because each of the 10,878 levels carries the conjunction type. I tried routing large conjunctions to the projection route instead and got a worse number, but the machine is at load average 18 with your other session's Carcara runs, so that measurement and the one before it are not comparable. I reverted that change rather than keep a behaviour switch I cannot currently justify. A clean comparison of the two routes needs an idle machine.

## Turn: 2026-09-17 16:22:28 (session 6cc35fc7)

Correct, and that is the right place. Let me read how the pass builds a bridge and what the existing handler in that file looks like.

## Turn: 2026-09-17 16:22:28 (session 6cc35fc7)

I didn't stop by choice — your message arrived as an interrupt while I was mid-investigation, which cancelled the turn.

Where I had got to: `PolyeqElaborator` already has exactly the machinery needed. `elaborate` bridges two terms equal modulo equality reordering, `build_cong` emits a single `cong` step over the argument lists with one premise per differing argument, and `flip_equality` handles the `(= x y)` against `(= y x)` leaf. So for a `distinct_elim` whose conjunction has 2,598 flipped pairs out of 10,878, the bridge would be one `cong` step with 2,598 premises, each a small `flip_equality` derivation. That is the shape your instruction implies, and it is cheap on Carcara's side.

What I still had open, and it bears on whether this pays: lean-smt's `cong` reconstructor folds an n-ary `and` with `congr (congrArg op h₁) h₂`, which is the same right-nested congruence shape that costs the kernel 37 s at this size. So the bridge may move the cost from the `distinct_elim` step to the `cong` step rather than remove it. The `distinct_elim` step itself would become an ascribed `rfl` at 46 ms, which is the part that clearly wins.

I can implement it and find out — the handler goes in `src/elaborator/polyeq/clausification.rs` next to `bfun_elim`, registered in `get_elaboration_function`, emitting `distinct_elim` to the canonical conjunction, then `elaborate` for the bridge, then `trans`. Shall I go ahead? I ask only because of the measurement risk, not the design: if the `cong` turns out to cost what the old path cost, we will have moved the problem and will want lean-smt's n-ary `and` congruence addressed too.

One practical note: the machine is at load average 18 with your other session's Carcara runs, so I will not be able to give you a trustworthy before-and-after timing until that quietens. I can write and test the change for correctness now and measure later.

## Turn: 2026-09-17 16:30:00 (session 6cc35fc7)

`bfun_elim` is an exact template: compute the canonical conclusion, return unchanged if it matches, else bridge with `elaborate` and join. For `distinct_elim` the conclusion is an equality, so the join is just `trans`.

## Turn: 2026-09-17 16:30:00 (session 6cc35fc7)

Done, in Carcara commit `6358c32b`, as the missed case in the polyeq pass's rule table alongside `bfun_elim`.

**What it does.** A `distinct_elim` step is rewritten to conclude the canonical elimination — the pairs in lexicographic order, each `(not (= aᵢ aⱼ))` with `i < j`, which is exactly what the checker recomputes — and `PolyeqElaborator::elaborate` bridges from there to the stated conclusion. The step's own conclusion is unchanged, which is necessary rather than tidy: its consumers include `and` steps that project a conjunct by index and so read the orientation the producer wrote.

**Measured on the heaviest case in the corpus**, `javafe.tc.TypeSig.021`:

| | before | after |
|---|---|---|
| the `distinct_elim` step | 73.7 s | **0.84 s** |
| the bridge's `cong`, 2,598 premises | — | 31.5 s, of which 31.3 s kernel |
| elaborated steps | 8,900 | 14,098 |

So the rule is fixed, and the risk I flagged before starting is real: about 31 s moves to the congruence that the bridge makes explicit. That residue is not a `distinct_elim` problem any more — it is lean-smt's n-ary `and` congruence, which folds right-nested so the kernel pays for the conjunction type at each of 10,878 levels. That is the same shape `AciNorm` and `ResNorm` exist to avoid, and it is now a clean separate target.

Net on that proof is about 2.3×, with 414 Carcara tests passing and three new elaboration cases covering the canonical, one-flipped and binary shapes.

Two process notes. `cargo fmt` reformatted the whole crate again, exactly as it did earlier this session; I staged only my files, but the first commit still swallowed its reformatting of `mod.rs`, so I amended it to carry just the one registration line and reverted the other 32 files. And I have not bumped lean-smt's Carcara pin, so nothing about round nine changes until you want it to.

## Turn: 2026-09-17 16:54:16 (session 6cc35fc7)

Waiting on the test tally before committing.

## Turn: 2026-09-17 16:54:48 (session 6cc35fc7)

Simplified, in `186b0c7`.

**What the checker does now.** After the Boolean `false` case, it walks the two conjunct lists once, requiring the same pair at the same position *in the same order*. If that holds, the two sides differ only in spelling — `Ne p q` from the reconstruction of `distinct`, `¬(p = q)` from `(not (= p q))` — so the whole equality is a single ascribed `Eq.refl`, which the kernel checks in one pass at 46 ms for 10,878 conjuncts. Anything else is refused with a message naming the offending conjunct, and becomes a trusted step.

The arm went from about 70 lines to 30, and `distinctCongEq` is gone with the leniency it existed for. Net 98 deletions against 75 insertions, most of the insertions being the new fixture.

**Tests.** `lake test` passes 151. I re-elaborated `distinct_flip` through the new Carcara pass, so it now exercises what the pipeline actually produces: a canonical `distinct_elim` plus the `eq_symmetric`/`cong` bridge, 14 steps, valid. I also added `distinct_noncanonical`, which is the same proof *before* the pass, kept deliberately as the guard on the contract — it checks that the step is refused and that the rest of the proof still goes through.

**One coupling to be aware of.** This commit bumps the Carcara pin to `6358c32b`, because the two halves only work together: the checker now depends on the elaborator canonicalizing. Running this lean-smt against an older Carcara would turn the 286 affected veriT proofs into trusted steps. The pin and the code moved in the same commit for that reason.

The `distinct_elim` rule itself is now settled. What remains from this thread is the bridge's `cong` over 2,598 premises at 31 s, which is lean-smt's n-ary `and` congruence rather than anything to do with `distinct`.

## Turn: 2026-09-17 16:55:32 (session 6cc35fc7)

That was the earlier test run finishing in the background; it reports the same 151 passing, no failures, so nothing changes. The only modification left in the tree is `RESOLUTION-PLAN.md`, which is your edit, not mine.

The `distinct_elim` work is complete across both repos:

- **Carcara `6358c32b`** — the missed case in the `polyeq` pass, canonicalizing the orientation and bridging to the stated conclusion, with three elaboration tests.
- **lean-smt `186b0c7`** — the checker accepts only the canonical form, closing it with one ascribed `rfl`, and pins Carcara to that commit since the two halves depend on each other.

Nothing is running and nothing is queued on the cluster.

## Correction (2026-09-17)

The Carcara commit is **`6358c32b`**, not `8a537147`. Two mistakes of mine,
both caught by Haniel noticing the hash was absent from `bv-fixes`:

1. I amended that commit to strip `cargo fmt`'s reformatting of
   `src/elaborator/mod.rs`, which changed its hash. I had read the hash before
   the amend and reused it afterwards, including in the lean-smt pin.
2. I never pushed it. `origin/bv-fixes` still pointed at `69c92a64` while my
   branch sat one commit ahead, so the pin named an object that existed only as
   a dangling local commit.

Now: `6358c32b` is pushed to `origin/bv-fixes`, `scripts/setup-alethe.sh` pins
it, and the references above are corrected. The lesson for the cluster drops
too -- read the hash *after* any amend, and confirm the push before pinning.
