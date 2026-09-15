# A reflective resolution checker for the Alethe checker

## Context

The paper's per-rule figure (`docs-alethe/alethe-lean-smt.tex` §2.2, round six, twelve
SMT-LIB logics, both solvers pooled) says `resolution` is **51 % of the checker's total
time**. §"What is left" already names the remedy — *"the reflective resolution checker
described in the accompanying notes, not a rule"* — and those notes
(`docs-alethe/elaboration-opportunities.md` §2) sketch it in three sentences: *literals as
indices into an atom context, pivots as indices, the whole chain evaluated at once, the way
`AciNorm` evaluates a connective layer*. This plan is that design, costed, with the key
kernel assumptions measured rather than assumed.

Today (`Smt/Alethe/Clause.lean:84-120`) a resolution step is replayed **link by link**: for
each pair of premises `reconstructResolution` (`Smt/Reconstruct/Prop.lean:269-288`)
materializes both clauses as `List Prop` expressions of the *full* literal propositions,
applies `Prop.orN_resolution`, and then `dedup` materializes the deduplicated clause again
and closes it with `orN_of_map` (`Smt/Alethe/Lemmas.lean:170`) — whose `qs.getD j False` is
linear in `j`, so a wide working clause costs the kernel O(width²) per link.

## The numbers

**Measured on this machine** (Lean 4.33, scratch files, `set_option profiler true`):

* The kernel *does* reduce `Nat.div`, `Nat.mod`, `land`, `lor`, `xor`, `shiftLeft` on
  literals — checked directly, including `1 <<< 300`. A 230-iteration bitset fold over a
  459-bit `Nat`, closed by `rfl`, is **free** (whole file, including startup: 0.22 s).
* Converting a reflective clause denotation to a real `Or` chain costs the kernel
  **~50 µs per literal** (2 000 literals: `type checking took 105ms`, against 314 ms of
  *elaboration* that the real checker does not pay, since it builds the term directly).
  That is the same ballpark as `AciNorm` in production (`semilattice_simp`, 4.3 ms median).

So the reflective cost model is **≈ 50 µs × (total literals in the step)**, flat in the
number of links. Today's is ~10 ms per *link* (the notes' measurement), with a width-cubed
term on wide chains.

**Profile of the one benchmark in the repo** (`steps.csv`, 6 913 steps):

| | steps | time | note |
|---|---|---|---|
| all `resolution` | 673 | 2.11 s (8.5 % of the run) | 70 % of it kernel — the most kernel-bound rule |
| 2–3 premises | 669 | ~0.9 s | median **1.24 ms**/step |
| the 230-premise chain (`t6906`) | 1 (+3 budget offcuts) | **1.18 s** | **56 %** of all resolution time |

That big step is worth looking at, because it is the shape the design is aimed at: **one
230-literal clause resolved against 229 unit clauses to give `(cl )`** — 459 literals, 459
distinct. It is literally unit propagation. Today each of the 229 links materializes the
shrinking working clause and re-indexes it through a linear `getD`: Θ(230³) kernel work on
`Prop` terms, 1.18 s. Reflectively it is 229 iterations of four GMP operations on a 58-byte
number, plus one denotation pass over 459 literals: **~25 ms, a 50× step**.

### Expected gain, honestly

* **Long chains and wide clauses: one to two orders of magnitude.** This is the mode behind
  the 2 287 + 2 494 SMT-LIB timeouts (they start around 20 000 elaborated steps), behind
  the checker memouts, and behind the need for Carcara's `budget` split.
* **Short chains: perhaps 3–5×** on the kernel half — a 4-literal step is ~0.2 ms of
  denotation against a 1.24 ms median today — but the floor is the fixed per-step cost of
  reconstruction plus a kernel call, which reflection does not remove.
* **Corpus-wide: ~1.5–2×** (Amdahl on 51 %). With 178 M `resolution` steps in the round,
  much of that 51 % is step *count*, and step count only falls with Stage 2.

**The timeouts, not the median, are the deliverable.** For calibration, SMTCoq's reflective
SAT checker in CPP 2011 was ~6× faster than LCF-style reconstruction *and* finished 28 %
more witnesses in the same timeout; that second margin is the one that matters here.

## What the four reference implementations say

**`AciNorm.lean`** (in this repo) is the template and the proof that the pattern works
here: a deep-embedded `Tree` of leaf indices, a `denoteOr` that unfolds *definitionally* to
the real formula, a normal form the kernel computes with GMP-accelerated `Nat.shiftLeft`/
`lor`, and one soundness theorem applied as a term. Its `denoteOr_iff` and
`testBit_one_shiftLeft` are close to copy-paste for the bitset half below.

**SMTCoq** (`theories/checker/fol/State.v`, `MainChecker.v`) contributes three decisions.
Literals are ints with polarity in bit 0, so the complement is `l lxor 1`. `C.resolve`
**computes** the resolvent and its spec is the one-directional `interp c1 → interp c2 →
interp (resolve c1 c2)` — no pivot in the certificate, no "exactly one pivot" side
condition, no equality test; the failure of a bad proof surfaces once, at the end. And the
whole state invariant is "every cell of the clause store is true", with the array default
set to the true clause, so there are no bounds obligations anywhere — which is why their
trace-fold correctness proof is eight lines. What *not* to copy is the closed-world deep
embedding of terms (`Terms.v`, 2 687 lines, plus ~5 000 more for `CompDec`/`BVList`/
`FArray`) that reflecting the theory reasoning forces on them; here atoms stay opaque Lean
`Prop`s behind a `Nat → Prop` context and only the clausal skeleton is reflected.

**Carcara** (`~/carcara/wt-diff/src/resolution.rs`) is the baseline being measured against,
and it has three paths: replay the `:args` chain, else `greedy_resolution` (pivots inferred
from the conclusion), else RUP. On this branch the args are explicitly *hints* — the same
status this plan gives them. Two decisions are load-bearing and we match both. **It
interns**: a literal is `(u32 negation count, &Rc<Term>)` and `Rc`'s `PartialEq` is
`Arc::ptr_eq` (`src/ast/rc.rs:16`), so no term is ever traversed while checking. **It does
not binarize**: `greedy_resolution` checks an n-premise chain in one pass over Σ|premise|
literals, building no intermediate clause — which is why it is three to four decades faster
per step, and why Carcara grew a `budget` pass whose module doc names lean-smt as the
consumer that needs chains split. The bitset fold below reaches the same asymptotics
without importing greedy's argument, which needs both a "at most one pivot eliminated per
premise" cap and a same-premise pivot buffer, each with an unsoundness counterexample
inline (`src/resolution.rs:160`, `:168`).

**Lean's own LRAT checker** (`Std/Tactic/BVDecide/LRAT/`, ~5 500 lines) settles the
question it was consulted for, in the negative and usefully. It is **not kernel-evaluated**:
`bv_decide` compiles `verifyBVExpr expr cert` natively, runs it, and then *mints a fresh
axiom* asserting the result (`Lean/Meta/Native.lean:18-87`; `ofReduceBool` was deprecated
in favour of this in 2026-02). Its trust profile is `native_decide`'s. The reason is
structural: its clause DB is `Array (Option Clause)` and its assignment is an `Array
Assignment` mutated in place with a trail for undo — and Lean's `Array` is a structure
wrapping a `List` (`Init/Prelude.lean:3198`), so in the kernel every `get`/`modify` is a
list traversal. The number to take away is the proof cost: **~3 400 of its lines verify the
mutate-and-undo discipline of that array, against 84 lines for the actual proof induction**
(`LRATCheckerSound.lean`). A functional bitset has no such state, so it pays none of it.

Four of its ideas do port, and two are worth taking now: **put the untrusted parser inside
the checked function** (`verifyCert` parses the certificate `String` as part of the `Bool`
computation, so the parser costs nothing in trust), and **treat a bad hint as a rejection,
not a panic** (`confirmRupHint` uses total `clauses[id]?`). Its `_result`/`_sound` split —
"the machine returned exactly `insert f c`" separately from "the logical content is
preserved" — is the right shape for Stage 2's store. Alethe needs no RAT analogue at all:
resolution steps carry explicit premises, so the hint property is free.

## The design

### Stage 1 — a per-step reflective clause checker

New module `Smt/Reconstruct/Prop/ResNorm.lean` — next to `AciNorm.lean`, not under
`Smt/Alethe/`, since it is a general verified component — in its exact two-halves shape: a
`@[expose] public section` with the verified core, then a `public meta section` with
reification and the proof-term builder. No tactic and **no `native_decide`**: the trusted
base is unchanged, everything is kernel-checked. That is also why this is the right lever
and `native` was not — the paper measures `native_decide` at ~8 % of median checking time,
because *"what the kernel spends its time on is the resolution chains and the congruences,
which `native` does not touch"*.

**Representation.** A literal is a `Nat`: `2*i` for atom `i`, `2*i+1` for its negation. A
clause has two representations — a `List Nat` whose denotation unfolds definitionally to
the premise's real `Or` chain, and a `Nat` bitset on which resolution and containment are
single GMP operations. `AciNorm` already does exactly this (`Tree` for structure, `bits`
for semantics, `denoteOr_iff` between them).

```lean
abbrev Context := Nat → Prop                      -- atom index ↦ Prop, an RArray in practice
def denoteLit (ctx : Context) (l : Nat) : Prop :=  -- match on a Bool: no `cond` delta, no `Decidable`
  match Nat.beq (l % 2) 0 with | true => ctx (l / 2) | false => ¬ ctx (l / 2)
def denoteCl (ctx : Context) : List Nat → Prop    -- mirrors `orN`: [] ↦ False, [l] ↦ denoteLit, l::ls ↦ ∨
def negLit (l : Nat) : Nat :=                     -- NOT `l ^^^ 1`: `omega` cannot see `Nat.xor`
  match Nat.beq (l % 2) 0 with | true => l + 1 | false => l - 1
def dropLit (p : Nat) : List Nat → List Nat       -- every occurrence of `p` removed
def resolve (acc c : List Nat) (p : Nat) : List Nat := dropLit p acc ++ dropLit (negLit p) c
def mask : List Nat → Nat                         -- the clause as a bitset, `AciNorm.bits` minus absorb
```

`denoteCl` mirrors `Smt.Reconstruct.Prop.orN` (`Smt/Reconstruct/Prop/Core.lean:56`) and
`mkClause` (`Smt/Alethe/Basic.lean:182`) case for case — `False` for the empty clause, the
last literal bare — so `denoteCl ctx c` **is** the premise's stated proposition up to
unfolding, at the measured ~50 µs per literal, once per premise instead of once per link.

`resolve` is **unconditionally sound for any `p`**: if the pivot does not occur, `dropLit`
removes nothing and the result contains the whole premise. So, as in SMTCoq, the pivot is a
hint and never a side condition, and there is no failure mode inside the fold. It also
reproduces Alethe's asymmetry — *every* occurrence of the pivot leaves the running clause,
only the *first* occurrence of its negation leaves the next premise, the rest of that
premise is appended (`carcara/src/elaborator/budget.rs:54-56`) — because under set
semantics "every" and "first" coincide on the premise side, and a tautological premise
`(cl l (not l))` resolved on `l` keeps its `l`, only `negLit p` having been dropped. Two
warts in the current code go with it: the "resolve again while the pivot remains" `while`
loop (`Clause.lean:103-111`) and its tautology guard, which caused the 2.2 M-iteration hang
fixed in `4a37a9b`.

**The only checked thing is the final containment**, as one GMP operation:

```lean
def chain : List (List Nat) → List Nat → List Nat → List Nat  -- premises, pivots, accumulator
  | c :: cs, p :: ps, acc => chain cs ps (resolve acc c p)
  | _,       _,       acc => acc                              -- total: no `Option`
def check (c₀ : List Nat) (cs : List (List Nat)) (ps : List Nat) (m : Nat) : Bool :=
  Nat.beq (Nat.lor (mask (chain cs ps c₀)) m) m
```

`m` is the target's mask, passed as a **raw literal** with its own one-shot side condition
`Nat.beq (mask tgt) m = true`, so `mask tgt` is computed once rather than twice. `chain`
recurses structurally on the premise list — no well-founded recursion, which the kernel
would not unfold (the `poly_norm` lesson).

**Carry the accumulator as a bitset, not as a list.** The form above is the easiest to
prove, but `dropLit p acc ++ …` copies the accumulator at every link, so `chain` costs
Θ(#premises × |acc|) — about 53 k reductions for the 230-premise step, good against Θ(230³)
but not good. Carrying it as a `Nat` makes every link four GMP operations:

```lean
def clearLit (m l : Nat) : Nat := m ^^^ (m &&& (1 <<< l))      -- no `Nat.ldiff` without Mathlib
def maskExcept (p : Nat) : List Nat → Nat                      -- `mask (dropLit p c)`, one pass
def chainMask : List (List Nat) → List Nat → Nat → Nat
  | c :: cs, p :: ps, acc => chainMask cs ps (clearLit acc p ||| maskExcept (negLit p) c)
  | _,       _,       acc => acc
```

The extra proof is a bridge between the two views —
`denoteMask ctx m := ∃ l, m.testBit l = true ∧ denoteLit ctx l`, with
`denoteCl ctx c → denoteMask ctx (mask c)` and `denoteMask ctx (mask t) → denoteCl ctx t` —
and that is `AciNorm`'s `denoteOr_iff` (`AciNorm.lean:157-185`), already written.
`clearLit`'s spec follows from `Nat.testBit_xor`, `Nat.testBit_and` and
`AciNorm.testBit_one_shiftLeft`. Build the list form first if the proofs fight back; ship
the bitset form. (Note the bitset is per *step*, over that step's few hundred literals —
LRAT's objection that `Nat.lor` is linear in the variable count does not bite at this size.)

**Soundness** comes out **fully constructive: no `Classical.em`, no `propext`** (`AciNorm`
needs `propext` only because it proves `Prop = Prop`; everything here is an implication).
The key lemma splits on the *disjunction*, not on the atom:

```lean
theorem denoteCl_dropLit (p) : ∀ c, denoteCl ctx c → denoteLit ctx p ∨ denoteCl ctx (dropLit p c)
theorem denoteLit_negLit (l) : denoteLit ctx (negLit l) → denoteLit ctx l → False
theorem denoteCl_mono (h : ∀ l ∈ c, l ∈ t) : denoteCl ctx c → denoteCl ctx t   -- subsumes append
theorem denoteCl_resolve : denoteCl ctx acc → denoteCl ctx c → denoteCl ctx (resolve acc c p)
theorem subset_of_masks : … → ∀ l ∈ r, l ∈ t
theorem check_sound : … → denoteCl ctx c₀ → denoteImp ctx cs (denoteCl ctx tgt)
```

`denoteLit_negLit` needs exactly two arithmetic facts — `negLit l / 2 = l / 2` and the
parity flip — both closed by `omega` after `Nat.div_add_mod`, which is why `negLit` must not
be spelled `^^^`. Premises are consumed through a curried `denoteImp ctx cs q` rather than a
`denoteAll` conjunction, so the term carries no `And.intro` type arguments (which would
duplicate every clause list). Assert `#print axioms check_sound` in the unit test.

**The encoding's one limitation, and it is real.** Carcara counts negations rather than
collapsing parity: `p`, `¬¬p`, `¬¬¬p` are three distinct literals and a complement is n±1
in either direction (`src/resolution.rs:189`), with a regression test
(`stacked_negations_within_a_premise`) for a real cvc5 pattern. A single parity bit cannot
express that: for a complementary pair `(f, ¬f)` where `f` is itself `¬g`, the encodings are
`(id g, neg)` and `(id ¬g, neg)` — not a parity flip, and no atom table fixes it, because
`¬¬g` and `g` are different Lean `Prop`s and the denotation must produce the literal
syntactically. So **Stage 1 handles literals with at most one leading negation and falls
back otherwise** — detect it in the reifier and return `none`. That is not a shortcut:
Carcara's own `rup_chain` fallback carries the same restriction, commented *"stacked
negations make chain adjacency ambiguous, and don't occur in the proofs this fallback
targets"*.

**Reify from the premise's `Expr`, not from its `Array cvc5.Term`.** `denoteCl ctx [a,b,c]`
is *syntactically* `a ∨ (b ∨ c)`, so walking the right `Or`-spine of `Premise.concl` makes
flattening a no-op in the denotation — which is what makes the `or` rule (whose premise is
the unit clause `(cl (or l₁ … lₙ))`) fall out for free. Map a `concl` of `False` to `[]`
explicitly. Atom interning is a `Std.HashMap Expr Nat` in the meta layer, so the kernel
compares only `Nat`s — Carcara's `ptr_eq`, transposed.

**The meta layer must run `check` itself before emitting anything.** `chain`, `resolve`,
`mask` and `check` are ordinary (non-`meta`) definitions, so the reconstructor calls the
same compiled functions the kernel will reduce, under `set_option compiler.relaxedMetaCheck
true`, exactly as `AciNorm.proveEq` calls `Tree.bits` (`AciNorm.lean:408`). On `false`,
return `none` and fall back, rather than emit a term whose rejection surfaces as an
unreadable kernel mismatch on a 10⁵-node term. Pivot *search* moves to `Nat` too
(`findPivot`/`hasPivot` become `negLit`/`List.contains`), which is faster and makes the two
layers agree by construction. When no pivot is found, pass a fresh index `2 * atoms.size`
rather than throwing: it occurs in no clause, so `resolve` degenerates to `acc ++ c` —
today's `orN_append_left` fallback (`Prop.lean:288`), except it keeps both premises.

**Dispatch.** `reconstructClausal` (`Smt/Alethe/Clause.lean:133`) routes
`resolution`/`th_resolution`/`strict_resolution` and also `contraction`/`reordering`/`or`/
`weakening` — the same check with zero pivots — through this one path, *after* the
`(cl (not true))` special case and *before* the existing code.
`concludeClause`/`reindexClause`/`fixClause` stay as the fallback behind
`smt.alethe.reflect` (default off until the A/B is green). A second option is a **size
threshold**: on a 2-premise, 2-literal step the reflective path builds an `RArray` context
and two `Nat` lists where the present code emits a three-line term, so it may be slower
there — and 669 of 673 steps in the profiled proof are that shape while 4 hold 56 % of the
time. Gate on premise count first, then measure whether the threshold can go to zero.

One difference to note rather than fix: Carcara's `contraction` is multiset containment,
`reordering` exact multiset equality, `weakening` a positional *prefix*, `or` a positional
unpacking. The subset test here is more permissive than all four. That is sound — we still
produce a proof of the *stated* conclusion — and it is already true of `concludeClause`.

### Stage 2 — batch the clausal subgraph (behind a flag)

Stage 1 still pays one reconstruction and one kernel call per step, and at 178 M resolution
steps that is the remaining floor. Stage 2 is SMTCoq's shape: a clause **store** of
bitsets, steps referring to earlier clauses by index, one fold and one evaluation for a
whole run of consecutive clausal steps, with SMTCoq's `S.valid` invariant (every cell
satisfied) and its true-clause default so there are no bounds obligations. Boundary cost is
one denotation conversion per clause entering or leaving the run. Structure the proof as
LRAT's `_result`/`_sound` split. SMTCoq's `smtTrace.ml` slot allocation (select/occur/alloc,
~120 lines, "similar to register allocation") ports directly as an untrusted meta-level pass
to bound the store — as does LRAT's `Trim.lean` lesson that pruning the certificate before
checking is worth doing and costs nothing in trust.

The store must be a persistent structure the kernel can index — **not** `Array`. LRAT's
experience says a balanced tree (`Std.TreeMap`) or a hand-rolled `Nat` trie, and that
choosing the persistent structure over the mutable one removes the single most expensive
part of the verification as well.

Cost: it weakens the per-step trust granularity and error localization the checker
deliberately has (`Reconstruct.lean:356-377` re-checks a rejected batch step by step to
attribute the failure), so it must be a flag with the fallback intact. Build it only once
Stage 1 is measured.

## Effort

`AciNorm.lean` — the same shape, already in this repo — is 462 lines, ~320 of them the
verified core, and its `denoteOr_iff`/`testBit` lemmas are close to copy-paste. SMTCoq's
corresponding core (`C.or` + `C.resolve` + proofs ≈ 190 lines, `set_resolve` 25, the trace
fold 70) is an independent estimate of the same quantity.

| | estimate |
|---|---|
| ~~Step 0: confirm the kernel reduces `Nat.div`/`mod`/bit ops~~ | **done — it does** |
| verified core (`denoteLit/Cl`, `negLit`, `dropLit`, `resolve`, `chain`, `mask`, `check`, soundness) | ~300 lines, 1–2 days |
| reification + `reconstructClausal` rewiring + option gate | ~200 lines, 1 day |
| regression tests | 0.5 day |
| Stage 2 (store, fold, slot allocation, flag) | ~300 lines + a store invariant, 2–3 days |

## Risks

1. **Amdahl.** Even a perfect result caps the corpus-median win near 2×.
2. **The 50 µs/literal denotation is the new floor** and it is irreducible — any approach
   must relate the premise `Prop`s to the representation. It makes the reflective step cost
   linear in the step's total literal count, which is the right shape, but it means the win
   on 4-literal steps is bounded.
3. **Stacked negations** (above) are a completeness gap, covered by the fallback.
4. **Silent regressions to guard with tests.** `(cl (not true))` → empty clause
   (`Clause.lean:137-142`) cannot be done reflectively and must stay, and stay first.
   `fixClause`'s AC fallback still covers left-nested `Or`s a right-spine reifier will not
   flatten, so fall back rather than fail. `smt.alethe.checkInner` re-does the kernel work
   in `MetaM` and should skip reflective steps. `sharedSizeIncr`/`batchSize`
   (`Reconstruct.lean:305-318`) will see much smaller steps, so kernel batches will silently
   grow — re-tune. Leave `Smt/Reconstruct/Prop.lean`'s cvc5 `.RESOLUTION` path alone.

## Verification

1. `lake build` with the `no_mathlib` lakefile (project rule: `git update-index
   --skip-worktree lakefile.lean lake-manifest.json`, never commit those).
2. `lake test` — `Test/Alethe/**` unchanged, plus a `Test/Unit/ResNorm.lean` in the
   `Test/Unit/AciNorm.lean` idiom (kernel `rfl` examples for each literal shape, a
   500-literal chain to time the kernel, negative cases, `#print axioms check_sound`), and
   new `.smt2`/`.alethe`/`.lean`/`.expected` quadruples: a 230-premise chain; a tautological
   `(cl l (not l))` premise; a chain with no `:args` (cf. `simple_nopivots`); a stacked-
   negation pivot (must fall back, not fail); `contraction`/`reordering`/`or`/`weakening`;
   an empty-clause conclusion; a ~1 000-literal clause. **Run the suite with
   `smt.alethe.reflect` both on and off.**
3. A/B on `perturbations_0.onnxhyperrectangle_1684.vnnlib.smt2.alethe` with `#check_alethe
   … timings csv`, against today's baseline (`resolution` 673 steps / 2.11 s, `t6906.t1`
   alone at 608 ms).
4. Then one gated cluster round (round eight) against the round-six per-rule series, per
   the `stanford-cluster` rules — staged with `cluster-propose`, never run unapproved.
