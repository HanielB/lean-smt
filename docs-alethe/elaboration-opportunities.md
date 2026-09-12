# Paying in elaboration to make verified checking cheaper

What Carcara's elaboration could do to the proof so that lean-smt's check of it costs less. The
question is asked from the kernel's side: the checker's cost is overwhelmingly the kernel's, so the
only elaborations worth their price are the ones that change what the kernel has to do. Numbers are
from the twelve-logic round (cvc5, 20,408 tasks aggregated when it was cancelled), the earlier
three-logic round (both solvers), the Sledgehammer round, and two proofs profiled step by step.

## Where the time goes

On the 243 validated proofs of 20,000 steps or more, the median split of the checker's time is

| phase | share | ms per step |
|---|---|---|
| parse (S-expressions) | 4 % | — |
| realize (cvc5's parser, with sharing) | 1 % | 0.11 |
| reconstruct, kernel excluded | 10 % | 1.5 |
| **kernel** | **84 %** | **14.4** |

and on the hard QF_UF families it is higher still: QG-classification 75 % (94 % on the profiled
`gensys_icl771`, 62,402 steps, 586 s of kernel in 621 s), NEQ 82 %, PEQ 75 %. Everything before
the kernel is a rounding error at this scale — the realization through cvc5's parser costs a tenth
of a millisecond per step thanks to the shared-term protocol. So "cheaper checking" means "less
kernel work", and the kernel's work is determined by the shape of the proof terms the reconstructor
builds, which in turn is determined by which rules the proof uses and how large their steps are.

## What the kernel finds expensive

Three lessons from this project, each measured, each the same lesson: **the kernel is a term
rewriter, and it is fast at evaluating closed computations and slow at everything else.**

1. *Unfolding lemma applications over explicit data.* A `resolution` over a chain of `n` premises is
   `n − 1` applications of `orN_resolution`, each carrying both clauses as explicit `List Prop` and
   proved by `eraseIdx`/`++`/`getElem` reductions the kernel performs on those lists. On the QG proof
   the 565 steps with 32 or more premises take 513 of the 586 kernel seconds; the per-link cost is
   about 10 ms below 64 premises and 18 ms above, at a median clause width of 2 — so the cost is
   the *links*, not the width, and it is superlinear only mildly. Across 977 validated QF_UF proofs a
   least-squares fit of kernel time on per-rule step counts (R² = 0.89) puts `resolution` at
   179 ms/step and `reordering` at 168, against `cong` at 5 and `symm`/`trans` at zero.
2. *Unification instead of evaluation.* `poly_norm` proved `l.toPolynomial = r.toPolynomial` by
   `Eq.refl`, and the kernel unified the two applications by lazy delta, in lockstep, with a cost
   that grew with the size of the coefficients: two atoms with coefficients of 2³¹ ran for half an
   hour. Deciding the same equality (`of_decide_eq_true`) is instant, because the kernel then
   *evaluates* each side once. That change alone was 84 of the round's holey proofs.
3. *Structural recursion over the wrong data structure.* The first `aci_simp` normalizer, a nested
   inductive with an insertion sort, cost 34 s on a 200-atom layer; a flat tree whose normal form is
   a bitset built with `Nat.shiftLeft`/`Nat.lor` — operations the kernel accelerates — costs 33 ms.
   The polynomial normalizer's move from repeated sorted insertion to one merge sort had the same
   character (25 s → 1.3 s on 400 variables).

The pattern is that **reflection wins**: hand the kernel a closed computation on `Nat`s and lists
of indices and one `decide`, not a chain of lemma instances over `Prop`-valued lists.

## What elaboration adds today

For cvc5 the pipeline is close to neutral: `polyeq local core-simp-rare` leaves the step count
within 0.1 % (199.6 M → 199.4 M), the only large movement being the 1.6 M `*_simplify` steps
replayed as 1.56 M `rare_rewrite` lemmas. For veriT it is not: the same pipeline grows the proofs by
**61 %** (100.9 M → 162.6 M steps), and the growth is exactly the canonicalization that makes the
proof checkable step by step —

| added by `polyeq local` (veriT, three logics) | steps |
|---|---|
| `resolution` (from `th_resolution`, 21.3 M → 0) | +30.0 M |
| `eq_symmetric` | +20.9 M |
| `equiv2` | +17.0 M |
| `reordering` | +8.0 M |
| `weakening` | +1.6 M |

— and every one of those steps is a kernel call. Since the checker's cost is per step, veriT pays
about 1.6× for the same derivation. This is the largest "elaboration price" currently paid, and it
is paid for the *checker's* benefit (explicit pivots, binary resolution, explicit symmetry), so it is
the first place to look for a better bargain.

## Opportunities

Ordered by expected effect on the kernel, with what each would cost in elaboration.

### 1. Do not emit what the consumer treats as free

lean-smt's clauses are sets: `concludeClause` closes any permutation, duplicate removal or
weakening of a computed clause by one `orN_of_map` application, and `orient` accepts an equality
premise in either direction. So for this consumer, `reordering` (8.0 M steps for veriT, 7.2 M for
cvc5 in the twelve-logic round), `eq_symmetric` (20.9 M for veriT) and the `contraction`/`weakening`
steps that `uncrowd` and `budget` add are pure overhead: each is a kernel call whose only content is
an index map. They are not slow individually — none appears among the profiled slow steps — but at
tens of millions of steps the fixed cost of a kernel call and its reconstruction (a few
milliseconds) is hours over the corpus. **Opportunity:** a consumer profile in `local` (say
`--consumer lean`) that resolves symmetry and clause order *in place* — orienting the equality in
the step that uses it, permuting the premise clause in the resolution that consumes it — instead of
materializing a step for each. The elaboration cost is nil; the information is already in `local`.
Expected effect: on the order of 25–30 % fewer steps for veriT proofs, a few percent for cvc5.

### 2. Keep resolution chains long, and let the consumer evaluate them

The per-link cost of `orN_resolution` is the wall. Splitting long chains (`budget`) bounds memory —
it turned the two chains the kernel could not check on `in-de31-O0` into pieces of a few seconds
each — but buys little time: on the QG proof it saved 4 % (586 → 560 s), because the links are the
same links. Binarizing (`--resolution-budget 2`) makes it worse: 39,517 → 56,537 steps, each a
kernel call. The real fix is on the lean-smt side and it is the reflection lesson: **a verified
resolution checker that takes the whole chain as data** — the literals as indices into an atom
context, the pivots as indices — and evaluates it with one `decide`, the way `AciNorm` evaluates a
connective layer. That would turn 513 s of the QG proof's kernel time into the cost of one
evaluation per step, plausibly two orders of magnitude less, and it would also remove the need for
`budget`. What Carcara should do to *enable* it is what it does now and should keep doing: emit
pivots as `:args` (`local`) and keep steps as multi-premise chains rather than binary trees. What it
should *not* do is `uncrowd` into more steps for this consumer.

### 3. Close renaming binds by reflexivity, and drop their subproofs — done (Carcara `20235088`)

A `bind` whose two sides are the same formula up to bound-variable names — every `bind` veriT
writes with identity substitutions, and every pure renaming — is closed in lean-smt by `Eq.refl`
(`Expr` equality is α-equivalence), cheaper than the `forall_congr` chain and independent of the
subproof. That subproof is dead weight: for a chained renaming
(`((y S) (z S) (:= x y) (:= y z))`) veriT derives the equality by `symm`/`cong` steps that hold only
name-syntactically — Carcara accepts them because its `symm` and `cong` are syntactic and only
`refl` and `bind` consult the substitution — and they have no consistent reading as terms of the
block, which is why lean-smt could not check them. **Opportunity:** in `polyeq` (which already
canonicalizes contexts), detect a `bind` whose sides are α-equivalent and replace the whole block
by a single trivially-checked step; and when they are not — the one Sledgehammer proof lean-smt
still cannot close renames *and* flips an equality by `eq_symmetric` inside such a block —
regenerate the subproof from the two sides rather than keep veriT's, since the checker cannot give
those steps a meaning. The corpora carry 354 k `bind` steps in cvc5's twelve-logic
round and 29 k / 15 k in the Sledgehammer rounds, plus their subproofs; how many are renamings is
not yet counted, but the identity-substitution `bind` is veriT's standard way to enter a binder.
*Implemented:* the `polyeq` pass now replaces every `bind` subproof whose sides are strictly
α-equivalent by one `refl` step at the subproof's depth (`polyeq::subproof::alpha_bind_to_refl`).
On the Sledgehammer proof behind `Test/Alethe/UF/chained_bind` this removes 14 of 28 `bind`
subproofs and takes the elaborated proof from 444 to 209 steps, with lean-smt's verdict unchanged
(only `t21`, the rename-and-flip block, stays trusted).

### 4. Pre-evaluate what the kernel would otherwise unfold

`poly_simp` and `poly_simp_rel` are now cheap only because the equality is *decided*; the same is
true of `evaluate`. Carcara's `core-simp-rare` replays the `*_simplify` rules as `rare_rewrite`
lemmas — 1.56 M of them for cvc5 — each a rewrite-rule instance the reconstructor turns into a
theorem application. That is fine per step but it is the largest single addition the pipeline
makes for cvc5. **Opportunity:** where a simplification is a constant fold or a normalization the
consumer decides anyway (`evaluate`, arithmetic normalization), emit that rule rather than a chain
of `rare_rewrite` steps; `core-no-rare` and `core-taut` already exist as rungs of this ladder and
their effect on the checker has not been measured.

### 5. `refl` is not free

The regression puts `refl` at 110 ms per step, third after `resolution` and `reordering`. It should
cost nothing; the likely explanations are large shared terms whose `Eq.refl` the kernel checks
against a stated type under `let` unfolding inside contexts, or an attribution artefact (a
subproof's cost landing on its many `refl`s). **Opportunity:** measure before acting; if real, the
`polyeq` pass could keep `refl` steps whose two sides are syntactically identical out of contexts
where unfolding is needed, or lean-smt could pin their type once. Unmeasured.

### 6. `budget`, as done

Worth keeping for feasibility: it is the difference between a checkable proof and an out-of-memory
on the longest chains (327 premises), at 90 extra steps in 39,517 and no measurable cost elsewhere.
Not a throughput tool; see 2.

## What not to spend elaboration on

* Realization and parsing: 5 % together, already linear in the DAG size.
* Clause width: the profiled resolutions have a median width of 2 and no slow step had 100 or more
  literals; the per-link cost does not depend on it.
* Splitting steps finer than the consumer needs (binary resolution, `uncrowd`): every added step is
  a kernel call, and the kernel's fixed cost per call is what the count buys.

## In one sentence

The kernel charges per lemma application over explicit `Prop` lists and almost nothing for a closed
evaluation; elaboration should therefore stop materializing bookkeeping steps the consumer resolves
for free (1, 3), keep the information that lets the consumer evaluate whole chains at once (2), and
prefer decided rules to rewrite chains (4) — while the decisive gain, a reflective resolution
checker, is on lean-smt's side of the line.

## 7. Break down `distinct_elim` so the consumer never builds a quadratic term — done (lean) + a lazy option

`distinct_elim` rewrites `(distinct x₁ … xₙ)` to the conjunction of the `n(n−1)/2` pairwise
disequalities. lean-smt reconstructs `(distinct …)` natively to exactly that conjunction, in
lexicographic pair order with orientation `xᵢ ≠ xⱼ` (`i < j`), so when the step's right-hand side
matches that order and orientation the equality closes by `Eq.refl` — measured at **1 s of kernel
for n = 200 (19 900 disequalities)**.

The out-of-memory cases in the ESC-Java (`javafe.*`) proofs — the large enum-style distincts —
are the ones where the right-hand conjunction does **not** match. `polyeq` canonicalizes `(= a b)`
against `(= b a)` (`mod_reordering`), which flips the orientation of some disequalities while
keeping their positions. lean-smt's fallback then proved `(distinct …) = (and …)` by pairing each
of the `n²` target conjuncts with a source conjunct through `Prop.and_elim`, and **each
`and_elim` embeds the whole `n²`-element conjunct list** — an O(n⁴) proof term. A single flipped
pair at n = 60 (1 770 disequalities) was enough to run for minutes; at the ESC-Java sizes it is the
"excessive memory consumption" the kernel reports.

**Fixed on the consumer side (the cheapest place):** lean-smt now proves the equality of two
disequality conjunctions that agree pairwise up to orientation by **congruence on the `∧`-chain**,
with `ne_symm_eq : (a ≠ b) = (b ≠ a)` at the flipped leaves — an O(n) proof, so the flipped n = 60
case drops from minutes to 175 ms and the ESC-Java distincts no longer exhaust memory. A genuine
*reordering* of the pairs still falls back to the quadratic conversion, but veriT and cvc5 emit the
pairs in lexicographic order, so that path is not exercised in the corpora.

**The lazy alternative, for the record (cvc5's `distinct_extension.h` shape).** Even the linear
congruence proof materializes the whole `(and …)` — O(n²) nodes — when downstream only a handful of
disequalities are used to close the branch. A Carcara pass could instead *derive the needed
disequalities on demand*: keep `(distinct …)` unexpanded and, wherever the proof consumes a
`(not (= xᵢ xⱼ))` (today via `distinct_elim` followed by `and`/`and_elim` projections), emit a
single-pair step `(distinct xs) ⊢ (not (= xᵢ xⱼ))` that lean-smt reconstructs by one projection
through the native `distinct` conjunction. That never builds the full conjunction and is the right
move when n is large and the used pairs are few — the analogue of cvc5's lazy distinct extension.
It is more invasive (it rewrites the elaboration of the projection chain, not just one step) and
was not needed once the congruence fix removed the blow-up, so it is left as the next step if a
proof ever *uses* Θ(n²) of the pairs.

## 8. Name the AC rules by the operator's structure — done (Carcara `131f9a1f`)

`aci_simp` covered a hierarchy (semilattices, exponent-two groups, free monoids, rings) under one
normal form, with `absorb` for the annihilator on the side, and lean-smt had three different
reconstructions behind it. The rules are now `semilattice_simp`, `boolean_group_simp`,
`assoc_simp` and `poly_simp`, each with exactly its operators' normal form, and the core pass
relabels the legacy names (see `rule-audit.md`, "The structural AC rules"). For the kernel the
gain is that every `and`/`or`/`xor` layer, annihilator included, is now one reflective
evaluation, where the AC rewriter had been building rewrite chains — and the nested cases the
single-layer normalizer cannot see are decomposed by Carcara into per-layer structural steps.

## 9. Read `ac_simp`'s premises in the checker — done (Carcara `13e721d7`)

veriT emits `ac_simp` with `:premises` when the flattening of a subterm was derived earlier —
notably a rewrite under a binder, packaged as a `bind` subproof — so the conclusion is congruence
over those equalities rather than a purely structural flattening. Carcara's *checker* ignored
`:premises` entirely and compared the conclusion's right-hand side against the structural normal
form of its left, so it rejected every such step:

```
(assume h1 (= a b))
(step t2 (cl (= (and (and a c) c) (and b c))) :rule ac_simp :premises (h1))
  error: expected terms to be equal: '(and b c)' and '(and a c)'
```

The cost was not a checking gap but a *lost proof*: elaboration validates as it goes, so the whole
proof came back with neither an elaborated result nor a verdict (`elab=none, lean=none`). The
elaborator has had a premise-aware decomposition all along; it was only ever reached for steps
whose premises happen to be redundant, which is why the ~11 k proofs that use `ac_simp` with
premises the checker could ignore were unaffected.

The checker now builds a rewrite map from the unit-equality premises and mirrors the elaborator's
two routes — the historical reading (both orientations, stopping at a replacement) and, failing
that, meeting in the middle (forward orientation, continuing past a replacement, both sides
normalized to a common form). The meet route is tried *only* when the step has premises, so a
premise-free instance keeps its strict structural reading, and premises that are not unit
equalities are ignored rather than rejected, leaving such a step exactly as it checked before.

Scale: 199 SMT-LIB veriT proofs in round four were lost this way (13 attributed in the logs plus
186 whose rule name fell past the runner's 2 KB stderr cap), 175 of them QF_UFIDL
(`pete2`/`pete`/`uclid`) and 24 QF_LIA. They now check, and Carcara decomposes the step into
`cong`/`trans`/`semilattice_simp`, which lean-smt already reconstructs — no lean-smt change was
needed.
