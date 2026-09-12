
## Turn: 2026-09-11 09:05:43 (session 315b089e)

## Summary

**cvc5 — complete.** Of 19,189 elaborated proofs, lean-smt validates **16,853 per-step / 16,876 native**, with **only 2 holey** (both `evaluate`) and the rest timeouts. That's the number that matters: round three's holey pile (241 `subproof`, 84 `poly_simp`, 34 `bind`, …) is gone — the audit and prior fixes hold up at corpus scale, zero trusted from any audited rule.

**veriT — ~69% done** (16,170 / 23,328 processed, 181 tasks running). This is the first-ever veriT run across all twelve logics, so it's the genuinely new evidence. Still a few hours out given the big UFLIA/QF_LIA/QF_UF arrays.

I'll leave veriT running and give you the full veriT breakdown (per-step vs native, holey rules, timeouts) once it finishes — or sooner if you want a partial. Want me to ping you on completion?

## Turn: 2026-09-11 09:09:00 (session 315b089e)

Partial veriT analysis (16,355 / 23,328 tasks; six QF logics not yet started). Of 12,874 elaborated proofs, **12,220 valid, 537 timeout, 49 holey** — 0.38% holey. The holey breakdown has three distinct root causes, none of them soundness failures (all correctly flagged as trusted/holey, never false-valid):

| rule | count | cause |
|---|---|---|
| `distinct_elim` | 33 | **kernel OOM on large `distinct` terms** — e.g. `TokenQueue.006` t44, 3382 steps, 10 GB RSS. The n≥3 non-Boolean path builds the full n(n−1)/2 conjunction with a `List.length` `decide` per pair — O(n³) kernel work on the big distincts in the Java-parser benchmarks. Pre-existing scaling issue, not from the audit. |
| `bool_simplify` | 9 | **slipped past the core pass** — reached lean as `bool_simplify` with "no reconstructor". It's in the `--core-rules` list but the core pass didn't reduce these instances, and lean has no direct handler. |
| `lia_generic` | 5 | omega couldn't close — expected veriT catch-all residue (outside omega's fragment). |
| `qnt_rm_unused` | 2 | **reconstruction bug** — "function expected" kernel error on some shape my `QUANT_UNUSED_VARS` handler mis-builds. |

So cvc5 came out essentially clean (2 holey), and veriT — the genuinely new data — surfaces three fresh checker gaps as expected (it's the solver that produces the odd shapes). The `qnt_rm_unused` "function expected" is a real bug; `bool_simplify` no-handler is a delegation gap; the `distinct_elim` OOM is a scaling problem in a reconstruction that predates this session.

veriT is still ~70% through. Want me to (a) wait for it to finish before touching anything, or (b) start digging into the two genuine bugs now (`qnt_rm_unused` shape and `bool_simplify` delegation) while the rest runs?

## Turn: 2026-09-11 10:21:42 (session 315b089e)

Done. Here's the report on all four.

## 1. `bool_simplify` not being elaborated — fixed (Carcara `4bd5e9a9`)

Root cause: Carcara's core-pass recipe `and_mp` (for `bool-and-mp-r`/`bool-and-mp-l`) picked which conjunct of `(and _ _)` was the modus-ponens implication by "the first conjunct that *looks* like `(=> _ _)`". When the **antecedent** conjunct is itself an implication — `(and (=> p q) (=> (=> p q) r))`, common in the ESC-Java proofs — it picked the antecedent and failed with "modus-ponens shape mismatch", leaving the step unreduced (→ "no reconstructor" in lean). Fix: take the implication's position from the rewrite label, not by guessing. `List_Node` now reduces all 35/35. Regression tests added for both labels with an implication antecedent.

## 2. `distinct_elim` — investigated + fixed the actual blow-up

The OOM (`javafe.*` enum distincts) is the **`convert` fallback**: when the RHS orientation differs from lean's native `distinct` reconstruction (which `polyeq`'s `(= a b)`↔`(= b a)` canonicalization causes), it proved the equality by pairing n² conjuncts through `Prop.and_elim`, **each embedding the whole n(n−1)/2 conjunct list** → O(n⁴) term. Measured: a single flipped pair at n=60 ran for minutes; ordered n=200 (via the `refl` fast path) was 1 s.

Fixed on the lean side (cheapest place): prove the equality by **congruence on the `∧`-chain** with `ne_symm_eq` at the flipped leaves — O(n). Flipped n=60 dropped from minutes to **175 ms**. I also documented, per your pointer to cvc5's `distinct_extension.h`, the **lazy alternative** for Carcara (derive only the used disequalities on demand, never materialize the conjunction) in `elaboration-opportunities.md §7` — the right move if a proof ever *uses* Θ(n²) pairs, but not needed once the congruence fix removed the blow-up.

## 3. `qnt_rm_unused` bug — fixed (lean `00f1b77`)

The shared `QUANT_UNUSED_VARS` reconstruction is **universal-only**: it instantiates each side by *applying* the quantified proposition, which is a function only for `∀`. Over an `∃` it set `ys := #[]` and applied `h : (∃ …)` as a function → `(kernel) function expected`. Added an `∃` handler via `Exists.elim`/`Exists.intro`, filling dropped binders with arbitrary inhabitants. `uf.903234` now valid (256 steps, trusted 0).

## 4. `evaluate` on the cvc5 proofs — what I found

The two holey cvc5 proofs are **QF_IDL** Averest bounded-model-checking benchmarks (`BinarySearch_safe_bgmc002`, `Partition_safe_bgmc003`), ~25 `evaluate` steps each, all failing with **`evaluate: not decidable and no atom to split on`** — lean synthesized a *classical* `Decidable` instance (so `decide` can't run) and `opaqueAtoms` found no propositional atom to case-split. I reproduced the plausible shapes locally — ground comparisons, and top- and nested Prop-equalities of decidable atoms like `(= (= (<= 2 3) (<= 1 5)) true)` — and **they all reconstruct fine**. So the real trigger is a narrower QF_IDL term I couldn't pin: the benchmarks aren't mirrored locally, and fetching them from the cluster repo is blocked by the guard (it flags the `/barrett` path even for a read). I've left this one **open and documented**; if you approve a one-line read of the benchmark I'll pin the exact term and fix it.

---

**State:** Carcara `4bd5e9a9`, lean-smt `00f1b77` (both on top of the audit commit `1ae1341`); suite **138/138**. `setup-alethe.sh` pins `4bd5e9a9`. These fixes are **not** in the running round four (it's on the pre-fix toolchain) — they'd land in a round five. And still pending from before: please `git -C ~/carcara/wt-diff push` — `4bd5e9a9` is unpushed.

## Turn: 2026-09-11 10:45:06 (session 315b089e)

The guard needs its own `cluster-approve` (your "approved" here doesn't reach it — approval must come from `cluster-approve` in a real terminal). The command is recorded in `~/.claude/cluster-pending.txt`. Please run `cluster-approve`, then I'll fetch it.

**Exact command** (read-only — `cat` the benchmark, redirect to a local scratch file):
```
cluster-run barrett2 'cat /barrett/scratch/benchmarks/benchmark_repos/SMT-LIB/non-incremental/QF_IDL/Averest/binary_search/BinarySearch_safe_bgmc002.smt2' > <scratch>/idl/BinarySearch.smt2
```
It reads one benchmark file and writes it into my session scratchpad locally; nothing is written on the cluster.

## Turn: 2026-09-11 11:05:16 (session 315b089e)

All four items are now resolved. Final summary:

## `evaluate` — root-caused and fixed

Fetched `BinarySearch_safe_bgmc002.smt2` and reproduced 27 evaluate holes. The failing step is `(= P true/false)` where **P is a ground Boolean formula containing equalities between propositions** — `(= (or …) (and …))`, every leaf `true`/`false`. Since `=` on `Prop` has no computable `DecidableEq`, the synthesized instance is classical (so `decide` can't run), and because every leaf is a constant, `opaqueAtoms` had nothing to case-split on → the error. My earlier local guesses missed it because they used *atomic* comparison sides, not nested *compound* Prop-equalities.

Fix: `decideGround` rewrites every propositional `=` to `↔` (`eq_iff_iff`) and lets `simp` evaluate the now-fully-decidable ground formula. **BinarySearch drops from 27 evaluate holes to 0.** Regression test `Test/Alethe/QF_UF/evaluate_ground`.

One thing the reproduction newly surfaced: those same proofs have **15 `ac_simp` holes** — `[ac_rfl_top]` failing on terms mixing arithmetic and Boolean structure (`¬F22 + -1*F22 ≥ 0 ∧ …`), where `AciNorm` handles the `∧` layer but the arithmetic AC fallback doesn't normalize the mixed shape. I've documented it in the audit but left it (separate rule, out of scope for the four items).

## All four requested items

| item | fix | commit |
|---|---|---|
| `bool_simplify` not elaborated | Carcara `and_mp` recipe takes the implication position from the label | Carcara `4bd5e9a9` |
| `distinct_elim` (investigate lazy) | lean congruence proof (O(n) vs O(n⁴)); lazy cvc5-style alternative documented | lean `00f1b77` + `elaboration-opportunities.md §7` |
| `qnt_rm_unused` bug | `∃` handler via `Exists.elim`/`intro` | lean `00f1b77` |
| `evaluate` explained | ground Prop-equality → `decideGround` (`eq_iff_iff`+simp) | lean `7e0afc2` |

**Suite 139/139.** lean-smt commits `1ae1341` → `00f1b77` → `7e0afc2` on `alethe`; Carcara `4bd5e9a9` (still **unpushed** — please `git -C ~/carcara/wt-diff push`). These land in a future round; round four is still running on the pre-fix toolchain.

## Turn: 2026-09-11 11:49:20 (session 315b089e)

You're right, and it's now fixed. `ac_simp` **should** have been eliminated by Carcara — it just wasn't asked to.

## What happened

`ac_simp` lived in the **veriT-only `LEGACY`** core-rule set (`qnt_cnf ite_intro bfun_elim ac_simp`). cvc5's `--core-rules` passed only `$SIMPLIFY` (the 14 `*_simplify` rules), so Carcara never reduced cvc5's `ac_simp` — lean-smt handled it natively. That's fine for pure-Boolean `ac_simp` (the reflective `AciNorm` normalizer), but the QF_IDL proofs have `ac_simp` over **mixed arithmetic/Boolean** terms (`¬F22 + -1*F22 ≥ 0 ∧ …`), which `AciNorm`'s AC fallback can't normalize → the 15 holes.

## Fix

Added `ac_simp` to the three core-rule lists — cvc5's `run-arms.sh`, and the shared `check-alethe.sh` / `alethe`-tactic defaults. Carcara then reduces all **45** of `BinarySearch`'s `ac_simp` steps to Boolean core rules, and the proof checks **fully valid end-to-end: 4133 steps, trusted 0, holes 0** (both the evaluate and ac_simp holes gone). Committed `eb249e4`; suite 139/139.

One trade-off I noted in the audit: reducing *all* `ac_simp` to core means the pure-Boolean ones lose `AciNorm`'s reflective efficiency (they become core chains — more kernel steps). If that step-count cost shows up in a future round, the alternative is to keep `ac_simp` reflective and teach lean-smt's handler to treat arithmetic subterms as opaque atoms — but for now Carcara-side elimination is the clean, correct fix you expected.

So `BinarySearch_safe_bgmc002` — the proof that surfaced both — is now completely clean. All the round-four holey categories are addressed: `bool_simplify`, `qnt_rm_unused` (∃), `distinct_elim` (OOM), `evaluate`, and `ac_simp`.

## Turn: 2026-09-11 12:00:02 (session 315b089e)

Committed. Direct answer to your question:

## Is pure-Boolean ACI reflective in lean-smt?

**`aci_simp`: yes** — it uses the verified `AciNorm` normalizer (kernel evaluation of a bitset normal form). **`ac_simp`: it was *not*** — it went straight to the non-reflective `Meta.AC.rewriteUnnormalizedTop`. I've now routed `ac_simp` through the same `AciNorm` path, so **simple single-layer Boolean `ac_simp` is now reflective too** (it treats every non-`∧`/`∨` subterm, arithmetic comparisons included, as an opaque atom).

## But the QF_IDL failures aren't simple Boolean

When I looked at the actual failing term it's not arithmetic (my earlier guess was wrong) — it's a **nested mixed `∧`/`∨`** conjunction that also carries the **absorbing element `false`**:
```
(and (not (>= (+ F22 (* -1 F22)) 0)) false (not (or …)))
```
`AciNorm` has two limits here: it flattens only **one** connective layer (a nested `∨` inside the `∧` is an opaque atom, so reordering *inside* it isn't seen), and it models the **neutral** element (`true` for `∧`) but **not the absorbing** one (`false`). So these fall back and the AC rewriter chokes.

So I kept both fixes: the reflective `AciNorm` routing (a genuine win for the simple cases, aligned with the "reflection wins" thesis), **and** `ac_simp` in the core-rule lists so Carcara reduces the hard nested/absorbing cases to Boolean core rules — `BinarySearch` checks fully valid (trusted 0) either way. A *fully* reflective solution would need a multi-layer, absorbing-aware normalizer, which I've noted in the audit as the follow-up if the core-chain step count ever matters.

**Suite 139/139.** Commits on `alethe`: `…7e0afc2` (evaluate) → `eb249e4` (ac_simp core rules) → `78af79d` (ac_simp reflective). Carcara `4bd5e9a9` still unpushed.

## Turn: 2026-09-11 12:04:15 (session 315b089e)

Read the whole normalizer. Short answer: they're **two very different extensions**. Absorbing is contained; multi-layer is a different data structure and a much harder soundness proof. Let me show both against the actual code.

## Where the current normalizer stands

`Tree` is a single connective layer: `unit` (neutral), `leaf i` (opaque atom — *including a nested opposite connective*), `node`. The normal form is `bits : Tree → Nat` (leaves as a bitset: AC from the set, idempotence from `|||`, neutral from `unit=0`). Soundness is "same `bits` ⇒ same denotation" (`denoteAnd_eq`). Two gaps for the failing `(and A false (not (or …)))`:

- **absorbing** `false`/`true` is reified as a plain `leaf` (line 156-157: `False => atom e`), so `(and … false …)` isn't collapsed;
- **single layer**: the nested `(or …)` is one opaque `leaf`, so if `ac_simp` reorders *inside* it, the two sides get different atoms.

## Absorbing element — contained (~40 lines, one new lemma)

Add a constructor and let the normal form carry a "bottom" that dominates. The key is that the denotation still unfolds to the original term, so the kernel check is unchanged.

```lean
inductive Tree | unit | absorb | leaf (i : Nat) | node (l r : Tree)   -- + absorb

def denoteAnd (ctx) : Tree → Prop
  | unit     => True
  | absorb   => False                       -- (and … false …) : the `False` in the term
  | leaf i   => ctx i
  | node l r => denoteAnd ctx l ∧ denoteAnd ctx r

def bits : Tree → Option Nat                 -- none = absorbing present ⇒ layer is ⊥
  | unit     => some 0
  | absorb   => none
  | leaf i   => some (1 <<< i)
  | node l r => match bits l, bits r with
    | some a, some b => some (a ||| b)
    | _, _           => none
```

The one new soundness lemma is that `bits t = none` forces the denotation:

```lean
theorem denoteAnd_bot {ctx} : ∀ t, bits t = none → denoteAnd ctx t = False   -- by induction; node case uses false_and/and_false
```

and `denoteAnd_eq` gains a `none`/`none` branch (both sides `False`), the `some`/`some` branch being today's proof. Reification changes two lines: `False => return .absorb` under `∧`, `True => return .absorb` under `∨`. **Crucially `denoteAnd (node absorb b)` is `False ∧ …`, which is exactly what `(and false …)` reconstructs to — so the kernel still checks `denoteAnd ctx tl` against `l` by unfolding, no new machinery.** This is a self-contained change I could land and prove.

## Multi-layer — substantially harder (new normal form + mutual-recursion proof)

The bitset trick fundamentally does not extend, because a leaf is no longer a context index — a nested `∨` layer's identity is *its own normal form*. So:

- **Data structure.** The tree alternates connectives, and the normal form becomes *nested*: an `∧`-layer's children are true atoms **or** normalized `∨`-layers, each of which recurses. A single `Nat` can't encode that; the normal form has to be a canonical nested object (e.g. sorted list of sorted sub-forms) compared structurally — and to keep leaf-equality cheap you hash-cons the sub-forms into the atom context, i.e. reindex.

- **Reification** descends *both* connectives, and an atom that is itself a layer is reified recursively and re-looked-up by its normal form, not syntactically.

- **Soundness** is the real cost: `denoteAnd`/`denoteOr` become **mutually recursive**, and "same canonical nested form ⇒ equal denotation" is a mutual induction over that alternation, plus a canonicalization-correctness proof (sorting/dedup of the nested children preserves denotation). That is a different order of proof effort from the current ~60 lines — and the kernel check is no longer one `Nat.lor` pass but a recursive merge, so it also costs more per step.

## Recommendation

Absorbing-only is worth doing if absorbing-without-nesting cases show up — it's small and preserves the "unfolds to `l`" property. But the QF_IDL failures are the *nested* kind (the reordering is inside the `(or …)`), so they need the multi-layer normalizer, which is a genuine mini-project (new normal-form type + mutual-induction soundness). Given the investigation's cost model — pay in elaboration, keep the kernel cheap — the Carcara core-reduction we already have is the better trade for those: it turns them into a handful of Boolean core steps at no proof-engineering cost, and the reflective `AciNorm` still handles the common single-layer `ac_simp`/`aci_simp`.

Want me to land the absorbing extension (tractable, verified), or leave the normalizer as-is with Carcara handling the nested cases?

## Turn: 2026-09-11 12:25:29 (session 315b089e)

Now I can answer precisely. Here's what the two rules actually do:

- **`absorb`**: `(= (op … c …) c)` — `c` is the operator's absorbing element (`false`/`and`, `true`/`or`, bit-vector zeros/ones) and occurs in `t` (flattened).
- **`aci_simp`**: runs `apply_aci_simp` on both sides — associativity, commutativity, idempotence, **and identity-element removal** (`identity_of_op`) — then compares multisets.

So the important precedent: **`aci_simp` already normalizes the *identity* element without that being in the "aci" name.** The acronym is a loose historical label, not an enumeration of the laws it applies. Folding in the *absorbing* (annihilator) element is the same category of extension — the operator's other distinguished constant.

## My recommendation on the name: don't rename

`aci_simp` is an Alethe **format** rule — emitted by veriT, checked by Carcara, cvc5's reconstruction, Isabelle's Alethe importer, and anything else consuming the format. Renaming it is a coordinated breaking change across that whole ecosystem and invalidates every existing proof and corpus, for a purely cosmetic gain — especially when the name already doesn't advertise the identity handling it does. So:

- **Keep `aci_simp`**, and document that it normalizes the connective's full monoid/lattice structure (identity *and* annihilator), the way it already silently handles identity.
- To make `absorb` **redundant** without a spec rename, have Carcara's elaborator **reduce `absorb` → `aci_simp`** (a local rewrite pass), so downstream — including lean-smt — only ever sees `aci_simp`. That gives you the "absorb is part of aci_simp" outcome you want, at the consumer, without forking the format.

If precise naming ever matters, that's a discussion for the Alethe maintainers, not something to unilaterally change from here.

## The two-tool change (keeping the name)

**Carcara** — two edits:
- `apply_aci_simp`: when a layer contains the operator's absorbing element, collapse that layer to the absorbing element (mirror `absorb`'s `is_absorbing`/`occurs` logic inside the normalizer). Then `aci_simp` accepts the absorbing cases.
- Elaborator: reduce `absorb` steps to `aci_simp` (so `absorb` disappears downstream). `absorb`'s checker stays for back-compat.

**lean-smt** — the `AciNorm` absorbing extension I sketched last turn (the `Tree.absorb` constructor + `bits : Tree → Option Nat` + the `denoteAnd_bot` lemma), which keeps the reflective single-layer path and makes `ac_simp`/`aci_simp` reconstruct absorbing single-layer cases by kernel evaluation. The nested cases stay with Carcara's core reduction, as you decided.

This is a real change in both repos with proof work on the lean side. Before I build it: good with **keeping `aci_simp`** and making `absorb` a reduced-away/subsumed rule (my recommendation), or do you want the rename — and if so, to what?

## Turn: 2026-09-11 12:31:15 (session 315b089e)

Good — let me think about it algebraically, because the algebra actually settles both the name *and* a soundness caveat.

## The laws in play

For a single operator, the rule normalizes modulo:

| law | `∧` / `∨` | in the name today? |
|---|---|---|
| associativity | ✓ | `a` |
| commutativity | ✓ | `c` |
| idempotence | ✓ | `i` |
| **identity** (unit: `x∧⊤=x`, `x∨⊥=x`) | ✓ (already!) | ✗ |
| **annihilator** (zero: `x∧⊥=⊥`, `x∨⊤=⊤`) | the one you're adding | ✗ |

Note the precedent: `aci_simp` **already** removes the identity element (`identity_of_op`), and that isn't in the acronym. So the acronym only ever named the *shuffle* laws (A, C, I), never the *constant* laws — which is why adding the annihilator doesn't really break the naming logic, it just makes the gap bigger.

## The algebraic structure

- A, C, I on one operator = a **semilattice**.
- with an identity = a **bounded semilattice** on that side (equivalently, a commutative idempotent monoid).
- adding the annihilator gives you the other bound: `⊤` and `⊥` — a **bounded semilattice** in the full sense (has both a top and a bottom). `(∧, ∨, ⊤, ⊥)` together is a **bounded (distributive) lattice** / Boolean algebra, but the rule is per-operator, so "bounded semilattice" is the exact fit.

So the honest algebraic names, ranked:

1. **`bounded_semilattice_simp`** — precise: exactly "ACI operator with identity and annihilator". Long but unambiguous, and it *names the case that isn't named now* (the bound).
2. **`semilattice_simp`** — concise; captures A+C+I in one standard word, and the bounds read as the natural "simplify" closure (you simplify away units and zeros of the semilattice). My pick for a short name.
3. **`lattice_simp`** — evocative but **I'd avoid it**: in lattice theory "absorption" is the law `a ∧ (a ∨ b) = a`, *not* the annihilator — so "lattice" invites confusion with a law this rule doesn't do, and "lattice" implies both operators interacting.
4. Staying in the acronym scheme — e.g. `acuz_simp` (a, c, u=unit, z=zero) or `aciz_simp` — I'd avoid these; they're cryptic and the identity was never spelled out anyway.

## The caveat the algebra exposes

`absorb` also covers **`bvmul`** (annihilator `0`). But `bvmul` is a commutative monoid with zero that is **not idempotent** (`x·x ≠ x`) — it is *not* a semilattice. So folding *all* of `absorb` into an idempotent normalizer would be unsound for `bvmul`: whatever the rule is called, its idempotent normal form must not be applied to `bvmul`.

This means the clean split is by structure, not by "absorb vs aci":
- **idempotent, bounded** operators (`∧`, `∨`, `bvand`, `bvor`) → the renamed `*_simp` (bounded semilattice), which now also eats the annihilator;
- **non-idempotent** monoid-with-zero (`bvmul`) → stays in `absorb` (or a `monoid_zero`-style rule).

So even under a rename, `absorb` doesn't fully disappear — only its semilattice cases merge in. That's an argument for a name that says *semilattice* (which correctly excludes `bvmul`) rather than something generic.

## Bottom line

If you rename, **`bounded_semilattice_simp`** (precise) or **`semilattice_simp`** (short) are the algebraically honest choices, and both correctly signal that `bvmul` is *not* in scope. My standing recommendation is still to keep `aci_simp` for the format and reduce `absorb`→`aci_simp` at the consumer — but if you do rename, I'd pick `semilattice_simp`. Want me to proceed on that basis (semilattice framing: merge the idempotent-operator absorbing cases into `aci_simp`/its rename in both repos, leave `bvmul` in `absorb`)?

## Turn: 2026-09-11 13:02:05 (session 315b089e)

Reading Carcara's own comment settles it cleanly. `aci_simp` already normalizes a whole hierarchy, and `is_idempotent` is the one predicate that tells the members apart:

- **all** its operators are associative (`is_assoc`): `and or + * bvadd bvor bvmul bvand bvxor concat`;
- all but `concat` are commutative monoids (associative + commutative + unit);
- only the **bounded semilattices** `and or bvand bvor` are idempotent.

## So what's the imprecision, exactly?

It's precisely **idempotence**, and it isn't only `bvmul` — it's the whole non-idempotent tail the rule already covers:

- `+ * bvadd bvmul` — commutative-**ring** operations: `(* x x)` is `x²`, `(+ x x)` is `2x`, not `x`;
- `bvxor` — an abelian group of exponent two: `(bvxor x x)` is `0`, not `x`;
- `concat` — not even commutative.

None of those is a semilattice. So calling the rule `semilattice_simp` while it still covers them **names only the idempotent subset** `{and, or, bvand, bvor}` and under-describes (mis-describes) the rest. That's a *nominal* imprecision — the name over-narrows the domain — **not** a soundness one.

## Does handling it properly complicate the code?

**No — it's already handled, and the distinguishing machinery is one predicate.** `apply_aci_simp` does:

```rust
let args = if is_idempotent(op) { flattened.dedup().filter(is_not_identity) }
           else                 { flattened.filter(is_not_identity) };
```

i.e. it dedups (semilattice) only for `{and,or,bvand,bvor}` and keeps multiplicity (commutative monoid) otherwise. The comment spells out the trap — "applying idempotence uniformly … would let `aci_simp` prove `(= (+ x x) x)`" — so the code is already sound across the hierarchy. Adding the **annihilator** rides on the same predicate structure: a per-operator `absorbing_of_op`, gated exactly like `identity_of_op` is now. No new complexity, just another one-line lookup.

## What that means for the name

- If the rule **stays general** (keeps the ring/group operators), `semilattice_simp` is wrong for them — the honest umbrella is the level they all share: **`comm_monoid_simp`** (associative-commutative with unit, the idempotent ones being the bounded-semilattice specialization). Adding the annihilator, `bounded_comm_monoid_simp` — but that's getting heavy.
- If the rule is (or is restricted to) the **idempotent** operators, `semilattice_simp` / `bounded_semilattice_simp` is *exact* — and the comment notes `poly_simp` already subsumes `aci_simp` on `{+,*,bvadd,bvmul}` anyway, so restricting isn't a real loss.

Worth noting for our side: lean-smt's reflective `AciNorm` only recognizes `∧`/`∨` (its `bits` bitset **is** idempotent set-union), so on the lean side the rule genuinely *is* a bounded-semilattice normalizer — `semilattice_simp` fits it perfectly; the ring/group generality only ever lives in Carcara's checker.

So: the precise recommendation is either **`semilattice_simp` + restrict the rule to `{and,or,bvand,bvor}`** (name exact, `poly_simp` covers the ring ops), or keep it general and call it **`comm_monoid_simp`**. Which direction do you want — restrict to the semilattices, or keep the ring operators under a monoid name?

## Turn: 2026-09-11 16:00:31 (session 315b089e)

Complete picture now — and no, `concat` isn't the only exception. Here's the algebraic tiering of everything `aci_simp` currently accepts (`is_assoc`), and where each would land if you restrict the rule to the semilattices:

| operators | structure | idempotent? | where they'd go |
|---|---|---|---|
| `and or bvand bvor` | bounded semilattice | yes | **`semilattice_simp`** |
| `+ * bvadd bvmul` | commutative ring | no | **`poly_simp`** (subsumes — it even takes `mod 2^w` for the BV sorts) |
| `bvxor` | abelian group, exponent 2 (`x⊕x=0`) | no | **neither** — see below |
| `concat` (`BvConcat`), `str.concat` | non-commutative monoid | no | **neither** — non-commutative |

So there are effectively **two** exceptions, not one:

- **`concat` / `str.concat`** — associative but not commutative, so `poly_simp` (which needs a commutative ring) can't take them. They only need associative flattening + unit removal, which is the tail of `apply_aci_simp` that ends in a *structural* `assert_eq` (the comment: "concat is not even commutative, so it never reaches the multiset comparison"). Restricting `semilattice_simp` orphans them unless you keep that non-commutative-associative branch somewhere.

- **`bvxor`** — this is the sneaky one. It *is* associative and commutative, so it looks like it should fall to `poly_simp` — but `poly_simp` models **rings** (`Polynomial::from_term`; there is no `BvXor` in `polynomial.rs`, and the authors' own comment lists only `{+,*,bvadd,bvmul}` as subsumed). `bvxor` lives in GF(2) where `x⊕x=0`, which is neither idempotence nor ring `+`. So it's covered by *no* other rule and would be genuinely orphaned.

So the clean statement is: restricting to `{and,or,bvand,bvor}` sends `{+,*,bvadd,bvmul}` to `poly_simp`, but leaves **`bvxor` and the two concats** with no home. If you want the restriction, those need a decision — most naturally, leave them in the old general `ac_simp`/`aci_simp` (or a small "associative flatten + unit" rule), since none of them is a semilattice or a ring.

Given that, the pragmatic split is: **`semilattice_simp`** for the idempotent four (the only ones lean-smt's reflective `AciNorm` handles anyway), `poly_simp` for the ring four, and keep the existing general AC rule for `bvxor`/`concat`/`str.concat` rather than orphaning them. Does that match how you want to carve it?

## Turn: 2026-09-11 16:06:01 (session 315b089e)

Neither is quite right, because `bvxor` and the concats **don't actually share a level** — lumping them repeats the same under-describing you're trying to avoid.

Look at what they have:

| | associative | commutative | unit | idempotent |
|---|---|---|---|---|
| `concat`, `str.concat` | ✓ | ✗ | ✓ (empty) | ✗ |
| `bvxor` | ✓ | ✓ | ✓ (`0`) | ✗ |

Their only common denominator is **associative monoid** (associative + unit). So:

- **`assoc_simp`** (associativity + unit flattening) is *accurate for the concats* — they're free (non-commutative) monoids, and associative flatten + unit removal is exactly their normalization.
- For **`bvxor`** `assoc_simp` under-describes it the same way `semilattice_simp` under-described `bvmul`: `bvxor` is **commutative**, so its normalization must reorder (multiset), which a pure `assoc_simp` wouldn't do. In fact that's what the current rule already does for it — `apply_aci_simp` on `bvxor` flattens + drops the unit + compares as a **multiset** (commutative monoid), *not* as a sequence. So `bvxor` sits at the **commutative-monoid** level, alongside `+ * bvadd bvmul` — it's just the one commutative-monoid operator `poly_simp` doesn't also cover (because `poly_simp` adds ring cancellation, and `bvxor`'s extra law is GF(2) involution `x⊕x=0`, not a ring).

And `ai_simp` is inaccurate for all of them: if `i` = *idempotent*, none qualify; if you meant `i` = *involutive*, that fits only `bvxor`, not the concats.

So the honest carve is three-way, not two:

- `assoc_simp` → `concat`, `str.concat` (non-commutative monoids) ✓ accurate;
- commutative-monoid tier → `bvxor` (with `+ * bvadd bvmul`), of which `poly_simp` already takes the ring four, leaving `bvxor` as the lone residue — better handled by a bitvector/GF(2) rule than grouped with the concats;
- `semilattice_simp` → `and or bvand bvor`.

So: `assoc_simp` is the right name **for the concats only**. Putting `bvxor` under it would be wrong (it's commutative); `bvxor` belongs with the commutative monoids / its own BV rule.

## Turn: 2026-09-11 16:08:31 (session 315b089e)

Here's the full table for the operators in play, with the simplification-relevant algebraic properties, the structure each combination names, and the rule that owns it.

## Operators × properties

| operator | assoc | comm | idempotent (`x∘x=x`) | unit (identity) | annihilator (zero) | self-inverse (`x∘x=unit`) | algebraic structure | simp rule |
|---|:---:|:---:|:---:|:---:|:---:|:---:|---|---|
| `and` | ✓ | ✓ | ✓ | `⊤` | `⊥` | ✗ | bounded semilattice | `semilattice_simp` |
| `or` | ✓ | ✓ | ✓ | `⊥` | `⊤` | ✗ | bounded semilattice | `semilattice_simp` |
| `bvand` | ✓ | ✓ | ✓ | `~0` (all ones) | `0` | ✗ | bounded semilattice | `semilattice_simp` |
| `bvor` | ✓ | ✓ | ✓ | `0` | `~0` (all ones) | ✗ | bounded semilattice | `semilattice_simp` |
| `+` | ✓ | ✓ | ✗ | `0` | — | ✗ (has inverse `−x`) | abelian group | `poly_simp` |
| `bvadd` | ✓ | ✓ | ✗ | `0` | — | ✗ (has inverse, mod `2^w`) | abelian group | `poly_simp` |
| `*` | ✓ | ✓ | ✗ | `1` | `0` | ✗ | commutative monoid with zero (ring ×) | `poly_simp` |
| `bvmul` | ✓ | ✓ | ✗ | `1` | `0` | ✗ | commutative monoid with zero (ring ×) | `poly_simp` |
| `bvxor` | ✓ | ✓ | ✗ | `0` | — | ✓ (`x⊕x=0`) | abelian group of exponent 2 (GF(2)) | (own BV/GF(2) rule) |
| `concat` (`BvConcat`) | ✓ | ✗ | ✗ | empty (width 0) | — | ✗ | free (non-commutative) monoid | `assoc_simp` |
| `str.concat` | ✓ | ✗ | ✗ | `""` | — | ✗ | free (non-commutative) monoid | `assoc_simp` |

## The property-combinations and their names

Building up from the shared base, each added law names a finer structure:

| properties | structure | normal form the checker uses |
|---|---|---|
| assoc + unit | **monoid** | flatten + drop unit; compare as a **sequence** (`assoc_simp`) |
| + commutative | **commutative monoid** | as above, compare as a **multiset** |
| + annihilator | commutative monoid **with zero** | multiset, but collapse to zero if it occurs |
| + idempotent | **bounded semilattice** | compare as a **set** (bitset) — `semilattice_simp` |
| commutative monoid + inverse | **abelian group** | ring/group normal form — `poly_simp` |
| abelian group, every `x` self-inverse | **abelian group of exponent 2** (GF(2) vector space) | GF(2) normal form — its own rule |

The clean reading: **idempotence** is the line between `semilattice_simp` and everything else; **commutativity** is the line between `assoc_simp` (concats) and the commutative tiers; and within the commutative non-idempotent tier, **which inverse/cancellation law holds** is the line between `poly_simp` (ring) and the lone `bvxor` (GF(2)).

Want me to drop this table into `docs-alethe/rule-audit.md` (or a new note) so the naming rationale is recorded alongside the `ac_simp`/`aci_simp` findings?

## Turn: 2026-09-11 16:10:13 (session b00f5c7c)

No — it never changed. `scripts/setup-alethe.sh` still builds **with** Mathlib by default and takes `--no-mathlib` to opt out:

- `scripts/setup-alethe.sh:26` — `no_mathlib=false`
- `scripts/setup-alethe.sh:37` — `--no-mathlib) no_mathlib=true`
- `README.md:94` — `scripts/setup-alethe.sh --no-mathlib    # the configuration the Alethe work uses`

There's no `--mathlib` flag anywhere. What *did* happen is on your working tree, not in the script: `lakefile.lean` and `lake-manifest.json` are currently the `no_mathlib` versions marked skip-worktree (`git ls-files -v` shows `S` for both), which is what that flag does once.

Given the Alethe work always uses the no-Mathlib config, flipping the default is the sensible change: default to the `no_mathlib` lakefile, add `--mathlib` for the Real reconstruction and its tests, and update the README line. Want me to do that?

## Turn: 2026-09-11 16:11:21 (session b00f5c7c)

Done. `scripts/setup-alethe.sh` now defaults to the no-Mathlib build and takes `--mathlib` to opt in:

- Default (`mathlib=false`): swaps in the `no_mathlib` lakefile/manifest and marks them skip-worktree — same code as before, just now the default path.
- `--mathlib`: the new branch at `scripts/setup-alethe.sh:71` undoes that — clears skip-worktree on `lakefile.lean`/`lake-manifest.json` and checks them back out from the branch — so switching back is symmetric instead of manual.
- Help text and `README.md:93` updated; `--no-mathlib` is now rejected as an unknown option, which is the right signal since its meaning would have silently inverted.

Verified: `bash -n` passes, `--help` renders the new text, the unknown-flag path errors, and the skip-worktree detection fires on your current tree (both files are `S`). I didn't run the script end to end — that would rebuild lean-smt and Carcara — and left the restore untriggered so your no-Mathlib config stays in place. Not committed.

## Turn: 2026-09-11 16:21:49 (session b00f5c7c)

Pushed: `75d6cb8` on `alethe` → `origin/alethe` (78af79d..75d6cb8).

Committed just `scripts/setup-alethe.sh` and `README.md`; the modified `CLAUDE-conversation-2026-09-10.md` is left alone since the logs go in their own `log:` commits here. The remote also printed that the repo moved to `git@github.com:HanielB/lean-smt.git` — the push worked through the redirect, but you may want to update the `origin` URL.

## Turn: 2026-09-11 16:24:36 (session b00f5c7c)

Split done and both branches pushed.

**`alethe`** (`3928766`) — technical only. Tracked non-source files are now just `.github/`, `.gitignore`, `AUTHORS`, `LICENSE`, `README.md`, `lakefile.lean`, `lake-manifest.json`, `lean-toolchain`, `scripts/`. The conversation logs and `docs-alethe/` were untracked with `git rm --cached` (files kept on disk) and added to `.gitignore` alongside `ALETHE-PLAN.md`. Nothing in `README.md`, the CI workflows, or the scripts referenced the moved paths, so no dangling references.

**`alethe-dev`** (`030169d`, branched from `75d6cb8`) — everything: the code as of the setup-script commit, `docs-alethe/` (paper, plots, `rule-audit.md`, `elaboration-opportunities.md`), all five `CLAUDE-conversation-*.md`, and `ALETHE-PLAN.md`.

Your working tree is back on `alethe` with all the dev files present but ignored, so the log hook keeps writing to `CLAUDE-conversation-2026-09-11.md` as before.

Two things to know:

- I left `lean-smt-artifact/`, `lean-smt-artifact.zip` (22 MB together) and the loose `perturbations_*`/`safenlp_example` benchmark files untracked on both branches — they look like scratch rather than record. Say the word and I'll add them to `alethe-dev`.
- Merging `alethe` into `alethe-dev` later would carry the removal commit over and delete the docs there. To refresh `alethe-dev` with new code, merge and then restore the paths: `git merge alethe && git checkout HEAD@{1} -- docs-alethe CLAUDE-conversation-*.md ALETHE-PLAN.md .gitignore && git commit`. If you'd rather avoid that friction, I can instead rebuild `alethe-dev` as an orphan branch holding *only* the dev material, with no code in it.

Also note the history of `alethe` still contains the logs and reports in earlier commits — removing them from the past would need a rewrite and force-push, which I didn't do.

## Turn: 2026-09-11 16:26:36 (session b00f5c7c)

History rewritten and force-pushed: `3928766...7e634c6 alethe -> alethe (forced update)`.

What happened:

- `git filter-branch --index-filter --prune-empty` over the 50 commits between the merge-base with `main` (`76b4eea`) and `alethe`, dropping `docs-alethe/`, `CLAUDE-conversation-*.md` and `ALETHE-PLAN.md` from every tree. `main`'s history is untouched — none of those paths ever existed before the branch point.
- 46 commits remain. Four became empty and were pruned: "Add the report on the Alethe checker", "Report the Sledgehammer round", "Add the cumulative-cost plot for the Sledgehammer round", and "log: round-four holey fixes".
- Verified the final tree is byte-identical to the pre-rewrite tip minus those paths, and `git log -- <paths>` over the new range is empty.
- Retitled the tip to "Ignore the development material kept only on alethe-dev", since after the rewrite it only adds the `.gitignore` rules.

Two safety nets hold the old history: the local ref `alethe-pre-rewrite` (`3928766`) and `alethe-dev` (`030169d`), which is still based on the pre-rewrite commits and carries all the logs and reports. Since `alethe-dev` now shares no rewritten ancestry with `alethe`, merging between them will be messy — if you want them to line up, say so and I'll rebuild `alethe-dev` on the new `alethe` (or as an orphan branch with just the dev material).

Everything is still in your working tree; only `fetch.sh`, the artifact zip/dir and the loose benchmark files remain untracked. Also, `git filter-branch` leaves its backup in `refs/original/` — I left it in place; it can be cleared later once you're happy with the result.

## Turn: 2026-09-11 16:27:58 (session 315b089e)

Done — the algebra table is in `docs-alethe/rule-audit.md` (section "Algebra of the AC-simplification rules", line 120), with the operator×property table, the property-combination/structure table, and the naming rationale (idempotence → `semilattice_simp`, commutativity → `assoc_simp` for the concats, inverse law → `poly_simp` vs the lone `bvxor`).

One thing to flag: **`docs-alethe/` is gitignored** in this repo (`.gitignore` line 6, `/docs-alethe`), so the doc is updated on disk but not version-controlled — and, as it turns out, my earlier "docs" commits this session only committed the code files (the `docs-alethe/…` paths were silently skipped by `git add`). The tracked, committed work is all the code (`Smt/…`, `Test/…`, `scripts/…`); the audit and elaboration-opportunities notes live on disk only.

If you'd like the audit docs tracked, I can either `git add -f docs-alethe/rule-audit.md` (force past the ignore) or move them somewhere not ignored — your call. Otherwise they stay as local working notes, consistent with how the repo is currently set up.

## Turn: 2026-09-11 16:30:05 (session b00f5c7c)

Done — `~/lean/lean-smt` is now on `alethe-dev`, and nothing in your working tree was touched in the process.

What I did, in order:

1. Restored `CLAUDE-conversation-2026-09-10.md` to its full 586 lines. The earlier switch back to `alethe` had dropped the last 28 (they were only in the `alethe-dev` commit).
2. `git checkout -B alethe-dev alethe` — since HEAD was already at `alethe`'s tip, this only repointed the branch; the working tree, including files being edited right now, stayed as-is.
3. Removed the four ignore lines from `.gitignore` and committed the dev material as `402afc7`: `docs-alethe/`, all five conversation logs, `ALETHE-PLAN.md`.
4. Force-pushed: `030169d...402afc7 alethe-dev`.

So `alethe-dev` is now exactly `alethe` (`7e634c6`, rewritten) plus one commit — they share history, so merges and rebases between them behave. Old refs kept locally: `alethe-pre-rewrite` (`3928766`) and tag `alethe-dev-old` (`030169d`).

One thing worth knowing: `docs-alethe/rule-audit.md` gained 58 lines at 16:26, during this session — a section on the algebra of the AC-simplification rules. Something else is writing in this repo (another session, or you). It's committed in `402afc7` now, but a parallel writer means switching branches here is not free.

Which leads to the one hazard: **don't run `git checkout alethe` in this directory.** `docs-alethe/` and the logs are tracked here and absent there, so git would delete them from disk, and any uncommitted edits would go with them. Use a second worktree instead:

```
git worktree add ~/lean/lean-smt-code alethe
```

Then code work happens here on `alethe-dev`, and when you want it on the clean branch, cherry-pick the code commits over in `~/lean/lean-smt-code` and push from there. Want me to set that worktree up?

## Turn: 2026-09-11 16:38:19 (session 315b089e)

Added. The two finite-field operators are in the table:

| operator | assoc | comm | idempotent | unit | annihilator | self-inverse | structure | rule |
|---|:-:|:-:|:-:|:-:|:-:|:-:|---|---|
| `ff.add` | ✓ | ✓ | ✗ | `0` | — | ✓ iff char `p=2` | abelian group (additive group of `GF(p)`, exponent `p`) | `poly_simp` (mod `p`) |
| `ff.mul` | ✓ | ✓ | ✗ | `1` | `0` | ✗ | commutative monoid with zero (mult. monoid of `GF(p)`) | `poly_simp` (mod `p`) |

They land in the **ring tier** with `+ * bvadd bvmul` — `poly_simp` with reduction mod `p` subsumes them, mirroring the mod-`2^w` handling of the bitvector ops. So finite fields don't add a new simp-rule owner; they extend `poly_simp`'s reach.

The one conceptual wrinkle I wrote up in the note: **`ff.add`'s self-inverse property is characteristic-dependent.** Its additive group has exponent = the field characteristic `p`, so for odd `p` it's not self-inverse, but for `p = 2` (i.e. `GF(2^k)`) `x + x = 0` — structurally the *same* exponent-2 abelian group as `bvxor`. Yet they get different owners: `ff.add` stays with `poly_simp` because it's the field's *ring* addition (mod-`p` reduction covers every characteristic, and the char-2 self-inverse law just falls out of reducing mod 2), whereas `bvxor` needs its own rule because in the bitvector theory it's a *bitwise* operator distinct from that theory's ring addition `bvadd` (`Z/2^w`). So "GF(2)-addition" appears twice in the table with two owners, and the deciding question is: *is the operator the canonical ring `+` of its sort, or a bitwise op that merely happens to be GF(2)-linear?*

(Still on disk only — `docs-alethe/` remains gitignored, so this isn't committed unless you want me to `git add -f` it.)

## Turn: 2026-09-11 16:40:31 (session 315b089e)

Committed on `alethe-dev` as `b68d9a3`. Thanks for the correction — you're right on both counts:

- **Branch**: we're on `alethe-dev`, not `alethe`. My code fixes from this session are all here (rebased, matching messages: `4c22527` audit → `b59fa65` qnt_rm_unused/distinct → `edfd908` evaluate → `90623ac`/`5f18168` ac_simp).
- **gitignore**: `alethe-dev`'s `.gitignore` is just `/.lake` and `/.claude` — `docs-alethe/` and the `CLAUDE-conversation-*.md` logs are **tracked** here (there are explicit `…-dev` commits that flip this: ignore the dev material on `alethe`, track it on `alethe-dev`). My earlier "docs-alethe is gitignored, won't commit" was reading the `alethe`-branch state — wrong for this branch.

So the finite-field table additions and the conversation log are now properly committed. The algebra table itself was already committed on this branch; only the `ff.add`/`ff.mul` rows and note were pending.

Net: on `alethe-dev`, `docs-alethe/rule-audit.md` now holds the full AC-simplification algebra table including the finite-field operators, and everything's committed and clean.

## Turn: 2026-09-11 17:42:42 (session 315b089e)

Short answer: not cleanly — and the reason sharpens the `ff.add` vs `bvxor` distinction from the table.

## Why it doesn't fit as-is

`poly_simp`'s normal form is a polynomial over ℤ, and for a bitvector term it reduces **mod `2^w`** — i.e. it models the ring **`Z / 2^w`**, which is `bvadd`/`bvmul` *with carries*. `bvxor` is a different ring on the *same sort*: it's **`(Z/2)^w`** — `w` independent bits, mod 2 each, **no carry**. So:

- Reducing mod `2^w` is the wrong quotient for xor. `bvxor` needs per-bit mod 2, not whole-value mod `2^w`.
- To include it, `poly_simp` would have to carry **two** bitvector arithmetics and pick per operator, and — the real trap — a term mixing a carry op (`bvadd`, `bvmul`) with a no-carry op (`bvxor`) on the same vectors spans *both* rings, so it has no single polynomial. Handling that means bit-level reasoning (essentially bitblasting), not polynomial normalization. That's a soundness hazard bolted onto a rule whose whole appeal is one clean ℤ-polynomial normal form.

## Where `bvxor` actually belongs

`bvxor` is associative, commutative, unit `0`, and self-inverse (`x⊕x=0`). Its normal form is just the **parity** of the atoms — an atom survives iff it appears an odd number of times. That is *exactly* lean-smt's `AciNorm` bitset machinery with `Nat.xor` (`^^^`) in place of `Nat.lor` (`|||`):

```
bits (leaf i)   = 1 <<< i
bits (node l r) = bits l ^^^ bits r     -- XOR instead of OR ⇒ parity ⇒ x⊕x cancels
```

with a `denoteXor`/soundness proof mirroring `denoteOr_eq`. So `bvxor` is a **sibling of `semilattice_simp`** (a reflective bitset normalizer, cheap in the kernel), not a member of `poly_simp`.

## The subtlety that makes `ff.add` different

You might object: `ff.add` over `GF(2^k)` is *also* char-2 / XOR-like, yet the table puts it in `poly_simp`. The difference isn't the algebra — it's that the **sort carries only one ring**. A finite field `GF(p)` has a single `+`/`*`, so `poly_simp` mod `p` owns `ff.add` unambiguously (and for `p=2` the mod-2 coefficient reduction *is* the parity normal form). The **bitvector sort carries two incompatible additive structures** — `bvadd` (`Z/2^w`, carry) and `bvxor` (`(Z/2)^w`, no carry) — so `poly_simp`, which fixes one modulus per sort, structurally can't own both. That "one ring per sort vs two" is the deciding line, and it's the same distinction as before (is the operator the canonical ring `+` of its sort?): `ff.add` yes → `poly_simp`; `bvxor` no → its own reflective xor-parity rule.

Want me to add this reasoning (the `bvxor`→xor-parity-bitset note and the "two rings on the bitvector sort" point) to the table's discussion in `rule-audit.md`?

## Turn: 2026-09-11 17:46:42 (session 315b089e)

Added and committed on `alethe-dev` (`ab58128`).

To your question — **you've got it right, with one refinement**: `bvxor` fits the `semilattice_simp` *machinery* cheaply, but not as the *same rule*.

**Cheap part (the machinery):** the entire `AciNorm` scaffold is reused unchanged — `Tree`, `reifyLayer`, the `RArray` atom context, `Tree.toExpr`, and the proof skeleton. You only:
- fold the leaf bitset with `Nat.xor` (`^^^`) instead of `Nat.lor` (`|||`),
- add a `denoteXor` (`node l r => Xor …`, `unit => False`),
- prove one soundness lemma `denoteXor_eq` mirroring `denoteOr_eq`.

The parity argument (same xor-bits ⇒ same odd-multiplicity atoms ⇒ equal xor) is slightly more than the OR/AND `∃`/`∀` arguments — it needs the `x⊕x=False` / `x⊕False=x` cancellation lemmas — but it's the same order (~50–70 lines). And for **Boolean `xor`** it's immediate (it's `Prop`-valued, reusing `Context = Nat → Prop`); only **bitvector `bvxor`** needs a `BitVec`-valued denotation (and BV isn't in lean-smt's scope yet).

**The refinement (why not literally *in* `semilattice_simp`):** OR is idempotent (keep the bit — `x∧x=x`) and XOR is involutive (toggle the bit — `x⊕x=0`). Those are *different folds* giving *different normal forms* — a single `bits` can't do both, so the checker branches on the operator anyway, and the name `semilattice_simp` asserts idempotence, which `bvxor` doesn't have (misnaming it exactly as `bvmul` would be).

So the clean design is a **shared module of reflective bitset normalizers parameterized by the fold** — OR for the bounded semilattices, XOR for the involutive/GF(2) operators, plain count for the bare commutative monoids — exposed as *separate rules*. Adding the XOR sibling is small; merging it under `semilattice_simp` would cost you the accuracy of both the name and the normal form. All of this is now written up in the doc's two new subsections.

## Turn: 2026-09-11 17:49:01 (session 315b089e)

Applying the same discipline as `semilattice_simp` — name the *structure* whose normal form the rule computes, and the structure has to be exact for every operator in it.

## What the rule normalizes

`bvxor` (and Boolean `xor`): associative, commutative, unit, and **self-inverse** (`x∘x = unit`). The normal form is the **parity** of the atoms. The algebraic name for "abelian group in which every element is its own inverse" is an **abelian group of exponent 2** — equivalently a **Boolean group**, equivalently a **GF(2)-vector space** (`(Z/2)^w`).

## Candidates

| name | verdict |
|---|---|
| **`boolean_group_simp`** | ✓ **my pick.** "Boolean group" is the standard name for an abelian group of exponent 2 — exactly the self-inverse law that makes parity the normal form. It's the precise sibling of `semilattice_simp` (both name a structure), and it correctly excludes `bvmul`, `+`, `bvadd`. |
| `xor_simp` | fine as a *transparent* name — everyone knows what xor does — but it's an operator name, not a structure name. It reads as "the xor operator's rule", so it doesn't advertise that it's the *property* (self-inverse) that matters, and it breaks the structural naming scheme the others follow. Acceptable if you value recognizability over consistency. |
| `parity_simp` | names the **normal form** rather than the structure — a different naming axis than `semilattice_simp`/`poly_simp` (which name structures). Accurate, but inconsistent. |
| `involutive_simp` | ✗ **avoid.** "Involutive" names a *unary* map with `f(f(x)) = x` (like `bvnot`, `¬`). The binary law here is *self-inverse* (`x∘x = e`), a different thing. The overlap invites confusion with a `not_not`-style rule. |
| `gf2_simp` | accurate but implies a *field*, and for Boolean `xor` you're not really working in GF(2) as a field, just the additive group; also cryptic. |
| `exponent_two_simp` | technically exact ("abelian group of exponent 2") but unreadable. |

## Recommendation

**`boolean_group_simp`.** It slots into the naming scheme as the exact structural sibling:

- `semilattice_simp` — idempotent commutative monoid → set normal form (OR fold)
- `boolean_group_simp` — self-inverse commutative monoid (abelian group of exponent 2) → parity normal form (XOR fold)
- `poly_simp` — commutative ring → polynomial normal form
- `assoc_simp` — free monoid (concats) → sequence normal form

If you'd rather optimize for immediate recognizability by proof consumers than for the structural scheme, `xor_simp` is the defensible runner-up. Want me to record `boolean_group_simp` (with `xor_simp` as the alternative) in the table?

## Structural AC rules, round-four status, report restructure (2026-09-11, session 315b089e)

**Round four finished** (both solvers, twelve SMT-LIB logics, 23,328 per solver). cvc5: unsat
20,037 / Carcara 19,194 / lean-smt valid 16,853 (timeout 2,287, holey 2). veriT: 19,196 / 17,823 /
15,334 (2,494, 54 — distinct_elim 33, lia_generic 10, bool_simplify 9, qnt_rm_unused 2). Native
arm: 16,876 / 15,343. CPU: Carcara 9.6 h + 6.5 h vs lean 198 h + 143 h. All holey categories
except lia_generic fixed since (evaluate/distinct_elim/bool_simplify/qnt_rm_unused).

**Structural AC rules** (you chose the four names: semilattice_simp, boolean_group_simp,
poly_simp, assoc_simp):
- Carcara `131f9a1f`: checkers for semilattice_simp (and/or/bvand/bvor; set normal form,
  annihilator folded in — absorb's law), boolean_group_simp (xor/bvxor; parity), assoc_simp
  (concat/str.++; sequence); core pass relabels aci_simp/absorb to the structural rule of their
  operator (checker-verified first) and emits ac_simp/shuffle/nary_elim layers as structural
  rules; expensive tier's clausal reduction now on semilattice_simp. Rule tests + core tests;
  all 221 rule tests green. Static rebuilt.
- lean-smt `82bc238`: AciNorm gains `Tree.absorb` + `bits : Tree → Option Nat` (annihilator,
  kernel-evaluated) and a parity normalizer for xor (`xbits` with Nat.xor, soundness via
  `parity ctx m n` over bit positions — XOr_interchange, parity_xor, parity_leaf, denoteXor_eq;
  compiled first try). Handlers: only poly_simp + the three structural rules; ac_simp/aci_simp/
  absorb removed. Core-rule lists carry `ac_simp aci_simp absorb`. Eight test proofs relabeled
  and re-validated; new tests semilattice_absorb, boolean_group. Suite 141/141.

**Report** (`docs-alethe/alethe-lean-smt.tex`, 15 pages): Evaluation rewritten around the four
configurations (cvc5/veriT × Carcara/lean-smt) for SMT-LIB round four (per-logic table) and
Sledgehammer; four Carcara-vs-lean-smt scatter plots (smtlib/seventeen × solver) and two cactus
plots from `~/exp/alethe-lean/plots-round4.py`; per-step-vs-one-term comparison moved to a final
section (plus a native paragraph); rules section describes the structural rules and the
annihilator/parity normalizers; Carcara section lists budget, α-bind→refl, structural rules,
bool_simplify fix. Counts refreshed (96 rules, ~4,900 lines, 52 lemmas).

## Turn: 2026-09-11 18:16:50 (session 315b089e)

All done — everything committed and the tree is clean. Here's the full picture.

## The four structural rules — implemented in both tools

**Carcara (`131f9a1f`)** — three new checkers, each with exactly its operators' normal form:

| rule | operators | normal form |
|---|---|---|
| `semilattice_simp` | `and or bvand bvor` | set; collapses to the annihilator when it occurs (`absorb`'s law folded in) |
| `boolean_group_simp` | `xor bvxor` | parity (odd multiplicity; `x⊕x` cancels) |
| `assoc_simp` | `concat str.++` | sequence |
| `poly_simp` | `+ * bvadd bvmul` (+ `ff.*`) | existing polynomial form |

The core pass **translates the legacy names**: `aci_simp`/`absorb` are relabeled to the structural rule of their operator (after that rule's checker accepts the conclusion), and the per-layer steps of nested `ac_simp`, `shuffle` and `nary_elim` are emitted as structural rules — so no legacy AC name survives it. All 221 rule tests + new core-translation tests green; static binary rebuilt.

**lean-smt (`82bc238`)** — reconstructs **only `poly_simp` + the three structural rules**; the `ac_simp`/`aci_simp`/`absorb` handlers are gone. The reflective `AciNorm` gained two things: the **annihilator** (`Tree.absorb`, `bits : Tree → Option Nat`, so `(and … false …) = false` is kernel-evaluated), and a **parity normalizer** for `boolean_group_simp` (bitset folded with `Nat.xor`; soundness via `parity` over bit positions with the interchange law — the whole module compiled first try). Eight test proofs relabeled and re-validated; two new tests. **Suite 141/141.**

## Status of the mechanization after round four

Round four (twelve logics, 23,328 benchmarks per solver) finished for **both** solvers:

| | unsat | Carcara | **lean-smt valid** | timeout | holey |
|---|---|---|---|---|---|
| cvc5 | 20,037 | 19,194 | **16,853** | 2,287 | 2 |
| veriT | 19,196 | 17,823 | **15,334** | 2,494 | 54 |

Rule coverage is essentially complete: the quantified and arithmetic logics are ~99%, and what's left is **scale** (timeouts on the huge QF_UF/QF_IDL proofs). Every holey category except veriT's oracle `lia_generic` is fixed since the run — `evaluate` (2), `distinct_elim` (33), `bool_simplify` (9), `qnt_rm_unused` (2) — each with a regression test. Sledgehammer stays at 99.7% / 97.0% with its residue fixed too. Native buys only +23/+9 proofs — the kernel's time is in the resolution chains, not the normalizers.

## Report (`docs-alethe/alethe-lean-smt.pdf`, 15 pages, `e7ad26e`)

Restructured as you asked: the Evaluation now compares just the **four configurations** on SMT-LIB round four (per-logic table) and Sledgehammer, with the **four Carcara-vs-lean-smt scatter plots** (SMT-LIB and SH × cvc5/veriT) plus four-configuration cactus curves; the **per-step vs one-term** material is a separate final section (with a native paragraph). Rules/Carcara sections describe the structural rules and normalizers; counts refreshed.

Two loose ends for you: **push Carcara** (`git -C ~/carcara/wt-diff push` — `131f9a1f` and its predecessors are unpushed), and note that a **round five** would be needed to see the post-fix numbers at corpus scale — round four ran on the pre-fix toolchain.

## Why Carcara does not check every unsat proof; memouts and slowdown in the report (2026-09-11)

**The Table-1 gap, measured** (unsat but not Carcara-valid): cvc5 843, veriT 1,373.
- cvc5: **842 of 843 have no proof to check** — the solver answered unsat inside its 120 s
  internal `--tlimit` but was killed by the 150 s external timeout while *printing* the proof
  (solver_rc=134, proof_bytes=0). 1 elaboration error. So essentially none of it is Carcara.
- veriT: 653 Carcara **parser** errors ("expected Real, got Int" despite
  `--allow-int-real-subtyping`; QF_UFLRA/mathsat 409, QF_LRA/meti-tarski 95, LassoRanker 85,
  QF_RDL/sal 47) + 226 rejected steps (and_simplify 24, ac_simp 13, rest past the stderr excerpt)
  + 252 holey (all `lia_generic`, no certificate) + 151 Carcara-check timeouts (130–230 MB proofs)
  + 62 memory kills during check/elaborate + 29 no-proof. Only the 653 + 226 are Carcara's to fix.

**Memouts.** First attribution attempt was wrong: task-level `terminationreason=memory` never lands
on the checker (all in solve/carcara/elab phases — verit-4: 46 solve, 68 check/elab, 84 elab). The
real checker memouts are the lean arm erroring with a memory message: cvc5 5, veriT 64 (SMT-LIB);
cvc5 0, veriT 21 (SH). Added as a `mem` column to both tables.

**Slowdown on commonly checked benchmarks** (both Carcara and lean-smt valid), elaboration
included: SMT-LIB cvc5 **213×** median over 12,773 (geomean 189×, p90 435×), veriT **497×** over
9,148 (geomean 516×, p90 1,184×); SH cvc5 234× over 2,843, veriT 483× over 2,414. Elaboration is
negligible (check-only medians 212/495/232/482). Per-logic column added to Table 1 — smallest
where proofs are largest (QF_UF 135× vs UF 369×), because the checker's fixed ~5 s library load
dominates on small proofs.

Table 1 transposed to solver-major (multirow) to fit the two new columns in llncs width. Report
now 16 pages, no undefined references.

## Turn: 2026-09-11 21:59:08 (session 315b089e)

Committed (`cba7dd3`, report now 16 pages). Here's the answer to your question, and the two additions.

## Why Carcara doesn't check every unsat proof

I measured it rather than guessed. The gap is **843** (cvc5) and **1,373** (veriT) — and for cvc5 it's essentially *not Carcara at all*:

**cvc5 — 842 of 843 have no proof to check.** The solver answered `unsat` inside its 120 s internal `--tlimit`, then was killed by the 150 s external timeout *while printing the proof*: `solver_rc=134`, `solver_time≈120 s`, `proof_bytes=0`. The runner records `no-proof`. Only 1 is a genuine elaboration error. So the unsat→Carcara drop for cvc5 measures proof *production*, not proof checking.

**veriT — 1,373, five causes:**

| n | cause |
|---|---|
| 653 | Carcara **parser** errors: "expected `Real`, got `Int`" on the proof text, *even with* `--allow-int-real-subtyping`. Concentrated in a few families: QF_UFLRA/`mathsat` 409, QF_LRA/`meti-tarski` 95 and `LassoRanker` 85, QF_RDL/`sal` 47 |
| 226 | steps Carcara's own checker rejects (identifiable: `and_simplify` 24, `ac_simp` 13; the rest have their rule line past the 2000-byte stderr excerpt the runner keeps) |
| 252 | holey — all `lia_generic`, veriT's oracle rule, which carries no certificate and which Carcara doesn't check either |
| 151 | Carcara's own 300 s check limit, on proofs of 130–230 MB |
| 62 | 12 GB exhausted during the check or elaboration |
| 29 | no proof (veriT killed at 150 s) |

So only the **653 parser errors + 226 rejected steps** are Carcara's to close, and the parser errors look like one defect in the integer/real subtyping of veriT's proof text. (I tried to reproduce that locally, but my local veriT is a different version and crashes on the sample benchmark with an internal assertion, so it's characterised from the cluster logs only.)

## Memouts

My first attribution was wrong and I corrected it: task-level `terminationreason=memory` **never** lands on the checker — those kills all happen during solving (46), Carcara's check/elaborate (68), or elaboration (84). The real checker memouts are the lean arm failing with a memory error: **5** (cvc5) and **64** (veriT) in SMT-LIB, **0** and **21** in Sledgehammer. Both tables now have a `mem` column.

## Slowdown on commonly checked benchmarks

On the proofs *both* validate, with elaboration counted on the checker's side:

| corpus | solver | common | median | geomean | p90 |
|---|---|---|---|---|---|
| SMT-LIB | cvc5 | 12,773 | **213×** | 189× | 435× |
| SMT-LIB | veriT | 9,148 | **497×** | 516× | 1,184× |
| Sledgehammer | cvc5 | 2,843 | **234×** | 234× | 409× |
| Sledgehammer | veriT | 2,414 | **483×** | 470× | 580× |

Elaboration is not the cost (check-only medians: 212/495/232/482). The per-logic factors are now the last column of Table 1, and they're counter-intuitive in a way worth noting: the slowdown is **smallest where proofs are largest** (QF_UF 135× vs UF 369×), because the checker's fixed ~5 s library load dominates on the small proofs while Carcara is nearly free there.

Table 1 is transposed to solver-major (multirow) so the two new columns fit the llncs text width.

## unsat column controlled for proof production; the veriT sort errors root-caused (2026-09-11)

**"unsat" → "proof".** The table's population is now the benchmarks for which the solver produced
a proof of the empty clause (`proof_bytes>0`, which the runner only sets when the solver exited 0,
so the proof is complete). cvc5 20,037 unsat → **19,195 with a proof** (842 killed mid-print,
solver_rc=134); veriT 19,196 → **19,167** (29 killed, rc=124). Sledgehammer unchanged. With that
denominator the cvc5 story is sharp: Carcara accepts **19,194 of 19,195** — the gap is *one*
elaboration error, not 843.

**The veriT sort errors: yes, they came up before, and they were mis-attributed.** Scanning every
past round for the signature: verit-2 (round two, three logics) already had **194 QF_LRA** cases;
round four has 653 because it adds the real-arithmetic logics (QF_UFLRA/mathsat 412, QF_LRA 192,
QF_RDL 49); verit-seventeen has 3. cvc5 rounds: zero, in all of them. The old report text had
claimed the arithmetic rejections were "almost entirely veriT's lia_generic" — wrong.

**Root cause found and fixed** (Carcara `92d8a42f`). `--allow-int-real-subtyping` was consulted for
the operators whose argument sorts are fixed and numeric (`+ - * /`, `abs`, the order comparisons)
but *not* for the polymorphic positions where the sorts merely have to agree: `=`/`distinct` (via
`check_sort_all_eq`), the two branches of `ite`, and the arguments of an uninterpreted function
(`make_app`). veriT writes an integer literal on one side of an equality with a Real-sorted term →
"sort error: expected 'Real', got 'Int'" at parse time, killing the whole proof. Minimal repro:
`(= x 0)` with `x : Real` fails while `(< x 0)` passes. Fixed with `check_sort_eq_poly` /
`check_sort_all_eq_poly` at exactly those three sites; `div`/`mod`/`to_int` stay strict
(`(div 1.0 2.0)` still rejected) and nothing changes with the flag off. Parser regression test
added; whole Carcara suite green (125+221+28+17+13+3+1+1). Static binary rebuilt; setup pin →
`92d8a42f`. Note the local veriT (2024.12.1) crashes on these LassoRanker benchmarks with an
internal assert, so the corpus-level confirmation has to wait for a rerun.

## Turn: 2026-09-11 22:12:44 (session 315b089e)

Both done — and the second question turned up a real bug.

## 1. `unsat` → `proof` (controlled for proof production)

The column now counts benchmarks where the solver **produced a proof of the empty clause**. I used the runner's `proof_bytes > 0`, and verified it's a sound proxy: there is no task with `solver_rc = 0` and an empty proof, so every counted proof came from a solver that exited cleanly.

| | unsat | **with proof** | Carcara |
|---|---|---|---|
| cvc5 SMT-LIB | 20,037 | **19,195** | 19,194 |
| veriT SMT-LIB | 19,196 | **19,167** | 17,823 |
| Sledgehammer | 2,869 / 2,681 | unchanged | 2,868 / 2,598 |

This changes the story completely for cvc5: **Carcara accepts 19,194 of 19,195 — the gap is one elaboration error**, not 843. The 842 were benchmarks killed mid-print (`solver_rc=134`), i.e. no proof existed to check.

## 2. Yes, it came up before — and it was mis-attributed

I scanned every past round for the signature:

| round | sort-error tasks |
|---|---|
| cvc5 (all rounds) | **0** |
| verit round 2 | **194** (all QF_LRA) |
| verit round 4 | 653 (QF_UFLRA 412, QF_LRA 192, QF_RDL 49) |
| verit Sledgehammer | 3 |

So round two already had essentially the same 192–194 QF_LRA cases. Round four only *exposes more* because it adds the real-arithmetic logics. And the previous report text claimed the arithmetic rejections were "almost entirely veriT's `lia_generic`" — that was wrong.

**Root cause, found and fixed** (`92d8a42f`): `--allow-int-real-subtyping` was consulted for operators whose argument sorts are fixed and numeric (`+ - * /`, `abs`, the order comparisons) but **not** for the *polymorphic* positions where sorts merely have to agree — `=`/`distinct` (via `check_sort_all_eq`), `ite`'s branches, and uninterpreted-function arguments (`make_app`). veriT writes an integer literal on one side of an equality with a Real term, so the proof died at parse time.

Minimal repro, decisive:
```
(= x 0)  with x : Real, flag on  →  sort error: expected 'Real', got 'Int'
(< x 0)  same setting            →  accepted
```
Fixed with `check_sort_eq_poly`/`check_sort_all_eq_poly` at exactly those three sites. `div`, `mod`, `to_int` stay strict (`(div 1.0 2.0)` still rejected), and nothing changes with the flag off. Parser regression test added; **whole Carcara suite green**; static binary rebuilt; setup pin → `92d8a42f`.

One caveat: my local veriT (2024.12.1) crashes with an internal assertion on these LassoRanker benchmarks, so I could only confirm the fix on the minimal reproductions and the test suite — corpus-level confirmation needs a rerun.

Report rebuilt at 16 pages, no undefined references (`eee2b4d`).

## veriT 2026.05, and the parser fix confirmed on real proofs (2026-09-11)

Was using the wrong local binary: `~/verit/veriT` (2024.12.1-3-gbaa0e77), which **aborts with an
internal assertion** (`Assert (DAG_attr.sort[src]) == (DAG_attr.sort[dest])`) on the QF_LRA
LassoRanker benchmarks — which is why "cannot reproduce locally" kept coming up. Deleted it at the
user's request; the local veriT is now `~/carcara/wt-corealethe/verit-2026.05/veriT` (2026.05, the
generation the cluster runs). Noted in memory. Side effect: `~/talks/talk-quantifiers/verit` is a
wrapper script that pointed at the deleted binary and is now broken (pre-existing demo, untouched).

With the 2026 build the parser fix is **confirmed end to end on real proofs**, not just minimal
repros. Generated proofs for four LassoRanker benchmarks from the failing families and A/B'd
against a pre-fix Carcara (built by reverting `92d8a42f` in a scratch build, tree restored after):

| benchmark | pre-fix | fixed |
|---|---|---|
| efegp.t2.c_Iteration1_Lasso_3-pieceTemplate | sort error: expected 'Real', got 'Int' | **valid** |
| disj_nightmare.t2.c_Iteration1_Loop_7-phaseTemplate | sort error | **valid** |
| agafp.t2.c_Iteration1_Lasso_4-pieceTemplate | sort error | **valid** |
| heidy7-simple.t2.c_Iteration2_Lasso_4-pieceTemplate | sort error | **valid** |

4/4 go from rejected-at-parse to fully valid. Report updated to say the affected families now
check valid rather than merely parse.

## Turn: 2026-09-11 22:31:18 (session 315b089e)

Done — and using the right binary changed the outcome materially.

**Deleted** `~/verit/veriT` (2024.12.1-3-gbaa0e77). The local veriT is now `~/carcara/wt-corealethe/verit-2026.05/veriT` — I've recorded that in memory so I don't reach for the wrong one again. I left the `~/verit` source checkout (44 MB git repo, with a few untracked scratch `.smt2` files) — say the word if you want that gone too.

**Why this mattered:** the 2024 build aborts with an internal assertion (`Assert (DAG_attr.sort[src]) == (DAG_attr.sort[dest]) failed`) on exactly the QF_LRA LassoRanker benchmarks I was trying to reproduce. That's what produced the "cannot reproduce locally" dead end twice. The 2026 build solves them fine.

**So the parser fix is now confirmed on real proofs**, not just minimal repros. I generated proofs with veriT 2026.05 for four benchmarks from the failing families and A/B'd them against a pre-fix Carcara (built by reverting `92d8a42f` in a scratch build, tree restored afterwards):

| benchmark | pre-fix | fixed |
|---|---|---|
| `efegp.t2.c_Iteration1_Lasso_3-pieceTemplate` | sort error | **valid** |
| `disj_nightmare.t2.c_Iteration1_Loop_7-phaseTemplate` | sort error | **valid** |
| `agafp.t2.c_Iteration1_Lasso_4-pieceTemplate` | sort error | **valid** |
| `heidy7-simple.t2.c_Iteration2_Lasso_4-pieceTemplate` | sort error | **valid** |

4/4 go from rejected-at-parse to **fully valid** — so those 653 veriT proofs aren't just parseable now, they check. The report says so explicitly (`b54882c`, still 16 pages).

One thing to flag: `~/talks/talk-quantifiers/verit` is a wrapper script that pointed at the deleted binary, so that talk demo is now broken. I left it alone since it's unrelated to this work — trivial to repoint at the 2026 build if you want.

## Turn: 2026-09-11 22:35:23 (session 315b089e)

Both trees clean. Here's the current picture.

## Fixed since round four — would disappear on a rerun

Round four ran on the pre-fix toolchain, so every holey category it measured except one is now closed:

| what failed | n | fix | confirmed |
|---|---|---|---|
| `evaluate` (ground Prop-equalities) | 2 cvc5 | `decideGround` (`eq_iff_iff`+simp) | 27→0 holes on the real benchmark, test |
| `distinct_elim` (kernel OOM) | 33 veriT | ∧-chain congruence, O(n) not O(n⁴) | flipped n=60: minutes→175 ms, test |
| `bool_simplify` unreduced | 9 veriT | Carcara `and_mp` recipe (`4bd5e9a9`) | 35/35 reduce, tests |
| `qnt_rm_unused` over `∃` | 2 veriT | new `∃` handler | real proof valid, test |
| `onepoint` | 47 SH veriT | general handler | tests |
| `qnt_simplify`, `bind` | 3 + 8 SH | handlers | tests |
| **Carcara parser sort errors** | **653 veriT** | polymorphic-position subtyping (`92d8a42f`) | **4/4 real proofs: sort error → valid** |

Suite 141/141. **None of this is measured at corpus scale** — that needs a round five.

## Genuinely open

1. **Scale — by far the dominant residue.** 2,287 (cvc5) + 2,494 (veriT) timeouts and 5 + 64 checker memouts in SMT-LIB. Not a rule gap; the timeouts start around 20,000 elaborated steps. The identified remedy is the reflective resolution checker (`elaboration-opportunities.md` §2), not yet built.
2. **226 veriT steps Carcara itself rejects** — 24 `and_simplify`, 13 `ac_simp`, 186 "expected terms to be equal" whose rule line falls past the runner's 2,000-byte stderr excerpt (likely the same class), 3 malformed terms. Carcara-side, uninvestigated.
3. **1 cvc5 Carcara elaboration error** (simplifying a quantified equality). Uninvestigated.
4. **Carcara's own scale limits on veriT proofs**: 151 exceed its 300 s, 62 exhaust 12 GB, on 130–230 MB proofs.
5. **`t21`, the chained-renaming `bind`** (1 SH veriT proof): a subproof that both renames a variable and flips an equality via `symm`, which Carcara accepts name-syntactically and which has no consistent reading as terms. Upstream remedy; the α-bind→`refl` pass removed every other instance.
6. **`beta_equiv` / `ho_cong`** — no Lean handler (they need λ-terms in the reconstruction). Latent rather than active: they appear in the text of 15 cvc5 SMT-LIB proofs but never surfaced as a trusted step in round four, because those proofs didn't reach the checker.

## By design, not failures

- **`lia_generic`** — veriT's oracle rule with no certificate: 252 make Carcara itself report holey, and 10 remain trusted in Lean where they fall outside `omega`'s fragment.
- **1 genuine `hole`** in a cvc5 Sledgehammer proof.
- **842 cvc5 / 29 veriT benchmarks with no proof** — the solver was killed mid-print. Now excluded from the table's denominator, since there is nothing to check.

## One action for you

`92d8a42f` (the parser fix) is **unpushed** — origin/bv-fixes is at `131f9a1f`. Everything else is pushed.

The honest summary: rule coverage is effectively complete for the twelve logics in scope, the remaining checker-side residue is *scale*, and the remaining Carcara-side residue is ~230 rejected veriT steps plus its own limits on very large proofs.

## Cross-check against the other evaluations (2026-09-11)

**`~/exp/alethe-core`** (Carcara core-ladder, 25,200 benchmarks per solver, 14 logics,
`carcara elaborate` with the hoist/polyeq/local/core/core-taut ladder):

| signature | veriT | cvc5 |
|---|---|---|
| sort error `expected 'Real', got 'Int'` | **674** (QF_UFLRA 412, QF_LRA 193, QF_RDL 59, **LRA 10**) | 0 |
| "expected terms to be equal" | 198 | 0 |
| `and_simplify` rejected | 24 | 0 |
| `ac_simp` rejected | 13 | 0 |
| `lia_generic` in the proof | 261 | 0 |

So **the same two Carcara-side failures are there**, independently, at essentially the same
counts (198/24/13 vs the lean round's 186/24/13 — the same ~230 steps), and the parser defect is
slightly *broader*: it also hits LRA, a logic the lean rounds do not cover. The parser fix
`92d8a42f` therefore recovers ~674 proofs there too. cvc5 is clean of all of it in both
evaluations.

**`~/exp/alethe-bv`** (cvc5 QF_BV/QF_UFBV, `carcara check` only, 24,218 tasks): **none** of these
failures appear — no sort errors, no rejected steps, no checking failures. But it is the heaviest
user of the rules I just restructured: `aci_simp` in 19,015 tasks, `absorb` in 16,586 (`ac_simp`
9,744 in the older `all-bv`). Verified no breakage:
- it runs `check`, not the core pass, and the legacy checkers were kept — all seven BV AC shapes
  (absorb bvand/bvor/bvmul, aci_simp bvadd/bvxor/concat/bvand-idem) still check;
- under the core pass the relabels are structurally right — bvand/bvor absorb and idempotence →
  `semilattice_simp`, bvmul absorb and bvadd → `poly_simp`, bvxor → `boolean_group_simp`, concat →
  `assoc_simp` — and `ac::relabel` only relabels after the *target* rule's checker accepts the
  conclusion, so it cannot turn a checking step into a rejected one.

Caveat: lean-smt's structural handlers cover the Prop operators only (`and`/`or`/`xor`); the
bitvector instances are out of its scope, as they were before.
