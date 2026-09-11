# Rule audit: lean-smt's Alethe handlers against Carcara's checkers

For every rule lean-smt reconstructs, what Carcara's checker accepts (`src/checker/rules/*.rs` of
`~/carcara/wt-diff`, branch `bv-fixes`) was compared with what the Lean handler accepts
(`Smt/Alethe/{Clause,Prop,UF,Arith,Quant,Rare}.lean`). The point is that anything Carcara lets
through *after* the `polyeq local core-simp-rare budget` pipeline must reconstruct: every
difference found here was a way for a Carcara-valid proof to come out of lean-smt with a trusted
step. The audit covers the 95 rules with a Lean handler, plus the rules the corpora emit without
one. Where a difference is a strict Carcara-side generalization that no corpus exercises, it is
recorded rather than implemented.

Date: 2026-09-10. Carcara at `20235088`, lean-smt branch `alethe`.

## Fixed in this audit

| rule | Carcara accepts | lean-smt accepted | fix | test |
|---|---|---|---|---|
| `cong` on two binary equalities | any of the four argument orientations (`(= (= a b) (= c d))` from `a=c,b=d`, `b=c,a=d`, `a=d,b=c` or `b=d,a=c`; veriT orders equality arguments as it likes, and the core recipe for `eq_symmetric` produces exactly this shape) | positional only | `reconstructCong` tries the straight alignment, then the three flipped ones, and straightens the flipped side(s) with `UF.eq_symm` around the congruence | `Test/Alethe/QF_UF/cong_flip` |
| `distinct_elim` over Booleans | three or more Boolean arguments → `(= (distinct ps) false)` | only the conjunction-of-disequalities form | new lemma `distinct_bool_false` (no three propositions are pairwise distinct) applied to conjuncts 0, 1 and n−1 of the reconstruction | `Test/Alethe/QF_UF/distinct_bool` |
| `la_tautology` | two forms: one literal whose sides differ by a constant, and `(or φ₁ φ₂)` over two bounds on the same term (five cases) | routed to `la_generic`, whose coefficient inference gave the first argument-less literal the multiplier 0, and which rejected the `or` form | unit multipliers when the step has no `:args`; the `or` form is proved as the clause of its disjuncts (the same `Or` chain) | `Test/Alethe/QF_LIA/la_tautology` |
| `resolution` | the empty clause from the single premise `(cl (not true))` | at least two premises | special case: `h trivial` | (shape not in the corpora; covered by the unit test of the special case in `Test/Alethe/M0`-style proofs only through `resolution`'s general path — a dedicated file was not added because cvc5/veriT do not emit it after `local`) |
| `lia_generic` | trusted by Carcara (a hole unless `--lia-solver`) | no handler → trusted | `omega` from the negations of the literals (the standard `falseOrByContra` + local-facts pattern); a step outside omega's fragment is still trusted | `Test/Alethe/QF_LIA/lia_generic` |

## Rules whose Lean handler is at least as permissive as Carcara's

Verified by reading both sides; no change needed.

**Clausal** (`Clause.lean`): `resolution`/`th_resolution`/`strict_resolution` with `:args` pivots
or pivot search per link; `contraction`, `reordering`, `weakening`, `or` — clauses are closed as
sets by `concludeClause`, so lean-smt accepts every permutation, duplication and weakening Carcara
does (and more: Carcara's `strict_resolution` is order-sensitive). `subproof` — the discharged
assumptions in any order.

**CNF and connectives** (`Prop.lean`): `and`, `not_or`, `and_pos`, `or_neg` require the index
argument exactly as Carcara does (`assert_num_args(args, 1)`); `and_neg`, `or_pos`, `implies_*`,
`equiv_*`, `not_equiv*`, `ite*`, `not_ite*`, `xor*`, `not_xor*`, `not_not`, `true`, `false`,
`not_and`, `implies`, `not_implies*` — shape-for-shape. `and_intro` with a non-unit premise: Carcara
matches the premise clause against an `(or …)` conjunct; lean-smt's `And.intro` over the premises'
conclusions gets the same `Or` chain for free. `connective_def`/`qnt_duality`: all five shapes
(`xor`, `=`, `ite`, `forall`, `exists`). `bfun_elim`: the application form (the quantifier form is
reduced by the core pass, as configured). `ite_then_intro`/`ite_else_intro`.

**Equality** (`UF.lean`): `refl`/`eq_reflexive` — Carcara accepts α-equivalent sides and the
context applied to the left, the right or both; lean-smt's `Eq.refl` pinned to the stated type
covers all of them (Expr equality is α-equivalence, and the anchor's substitutions are `let`s the
kernel unfolds on either side). `symm`, `not_symm`, `eq_symmetric` (both forms), `trans` (links in
either orientation, reflexive links skipped, matched up to the substitutions), `eq_transitive`,
`eq_congruent`, `eq_congruent_pred` (premises in any order, either orientation — Carcara consumes
them in order), `evaluate` (plus the split on opaque Boolean atoms), `aci_simp`, `ac_simp`,
`absorb`, `rare_rewrite` (per the rule table; coverage is measured on the corpora, not audited
rule by rule here).

**Arithmetic** (`Arith.lean`): `la_generic` — `negate_disequality` shapes (`<`, `≤`, `>`, `≥`,
`=`, negations, `not (= …)`), `to_real` transparent, integer strengthening with the gcd argument
(Carcara's `is_integer_valued`/gcd-with-constant; lean-smt rounds every integer bound, which is
sound and at least as strong), rational coefficients cleared by the lcm over the integers;
`bounded_farkas` (multipliers of the bounds inferred as `la_generic_partial` infers them);
`la_disequality`, `la_totality`, `la_rw_eq`, `la_mult_pos`/`la_mult_neg` (the
`(=> (and (⋈ m 0) (⋈ a b)) (⋈' (* m a) (* m b)))` form), `div_intro` (three forms),
`div_by_zero_intro`, `poly_simp` (both sorts, division by a nonzero constant folded into the
multiplier), `poly_simp_rel` (integer, rational, and integer sides with rational coefficients).

**Quantifiers** (`Quant.lean`): `forall_inst` (`(:= x t)` and positional arguments, sorts checked
by cvc5's parser), `bind` (vanilla and generalized clausal form; α-equivalent sides by `Eq.refl`),
`let` (identical pairs need no premise, as in Carcara), `sko_ex`/`sko_forall` (sequential
skolems), `onepoint` (n points, kept variables, guards under `∃`, both quantifiers),
`qnt_simplify`, `qnt_rm_unused` (any subset of the prefix, including all of it), `qnt_join` (any
nesting depth — nested and flat prefixes are the same `Expr`), `miniscope_*`.

## Remaining differences, deliberately left

| rule | Carcara | lean-smt | why left |
|---|---|---|---|
| `resolution` | when the hinted chain fails, falls back to greedy resolution and then to RUP | hint per link, else pivot search per link | RUP has no cheap kernel proof; after `local` the hints are always present and correct, and the per-link search covers the greedy case |
| `qnt_join` | deduplicates repeated binder names across the merged prefix (`(forall ((x S)) (forall ((x S)) φ))` = `(forall ((x S)) φ)`) | the vacuous outer binder stays | shadowing a bound name in a nested prefix does not occur in the corpora; would need `qnt_rm_unused` on top |
| `sko_ex`/`sko_forall` | when binder names repeat, matches assignments by position | by name | repeated names in one skolemized prefix do not occur |
| `poly_simp_rel` | the `(to_real (- x₁ x₂))` premise form and a sign condition on mixed sorts | integer, rational and int-sides/rational-coefficients forms | mixed `to_real` premises come from proofs without `--proof-elim-subtypes`; the corpora are generated with it |
| `poly_simp` | bit-vector and modulo cases; division by zero as an atom | integers and rationals | out of the logics in scope |
| `la_mult_sign` | multiset parity of the monomial's factors, `(not (= x 0))` hypotheses | cvc5's `ARITH_MULT_SIGN` shape | zero occurrences in the corpora |
| `eq_transitive` | any order of the `(not (= …))` literals that forms a chain | the chain in the listed order | `local` canonicalizes `eq_transitive` |
| `absorb` | nested applications flattened | one layer | zero occurrences |
| `evaluate` | strings, bit-vectors | arithmetic and Boolean | out of scope |
| `ac_simp`, `qnt_cnf`, `ite_intro`, `*_simplify` | native | delegated to the core pass (`--core-rules`) | by design |

## Emitted by the corpora with no Lean handler

| rule | steps (Sledgehammer cvc5 / veriT, SMT-LIB round three) | status |
|---|---|---|
| `lia_generic` | veriT LIA proofs | now `omega` (above) |
| `beta_equiv`, `ho_cong` | 212 / 212 (Sledgehammer HO fragments) | not supported: they need λ-terms in the reconstruction (`Smt.Reconstruct` has no `LAMBDA`); a Carcara-side β-normalization before checking would remove both |
| `hole` | as emitted | trusted and counted separately, as intended |

Carcara's other 120-odd rules (bit-vectors, strings, arrays, cutting planes, pseudo-Boolean
blasting, `mult_*`, `to_int_*`, `nary_elim`, `eq_mp`, `strict_refl`, `shuffle`, `bind_let`,
`tautology`, `la_mult_abs_comparison`, `log2_intro`, `mod_simplify`) are outside the logics in
scope or are not emitted by either solver in the corpora.

## Method note

The comparison read each Carcara checker for the *set of conclusions it accepts* and looked for
inputs the Lean handler would reject: argument orientations, optional arguments, degenerate
shapes (single premises, constants), sort mixtures, and n-ary flattening. Each gap that a solver
can produce after the pipeline got a Carcara-validated proof as a regression test
(`carcara check` on the test's `.alethe` before it was added), and the whole suite was rerun.


## Follow-up fixes from the round-four corpus run (2026-09-11)

The round-four cluster run surfaced three checker gaps beyond the audit above; all three are now
fixed (regression tests noted), and the `evaluate` residual is characterized.

| rule | issue | fix | test |
|---|---|---|---|
| `bool_simplify` | Carcara's core pass left it unreduced ("no reconstructor" in lean) when a modus-ponens conjunct's *antecedent* was itself an implication — the `and_mp` recipe guessed the wrong conjunct and failed with "modus-ponens shape mismatch" | Carcara `4bd5e9a9`: the recipe takes the implication's position from the rewrite label, not from the term | `tests/test_rewrite_elaboration.rs` (two antecedent-is-implication cases) |
| `qnt_rm_unused` over `∃` | the shared `QUANT_UNUSED_VARS` reconstruction is universal-only (it *applies* the quantified proposition, valid only for `∀`), so an existential rewrite hit `(kernel) function expected` | new `∃` handler in `Smt/Alethe/Quant.lean` via `Exists.elim`/`Exists.intro`, filling dropped binders with arbitrary inhabitants | `Test/Alethe/UF/qnt_rm_unused_exists` |
| `distinct_elim` | the pairwise conversion (used when the RHS orientation differs from the native `distinct` reconstruction, as `polyeq` causes) embeds the whole conjunct list in each of `n²` `and_elim`s — an O(n⁴) term that exhausts kernel memory on ESC-Java's large distincts | prove the equality by congruence on the `∧`-chain with `ne_symm_eq` at flipped leaves — O(n); the refl fast path already handled matching order | `Test/Alethe/QF_UF/distinct_flip`; see `elaboration-opportunities.md` §7 |
| `evaluate` (cvc5, 2 QF_IDL proofs) | `evaluate: not decidable and no atom to split on` on ~25 steps each of two Averest bounded-model-checking proofs (`BinarySearch_safe_bgmc002`, `Partition_safe_bgmc003`) | fixed — the term is a *ground* Boolean formula containing equalities **between propositions** (`(= (or …) (and …))`, all leaves `true`/`false`); `=` on `Prop` has no computable `DecidableEq`, so the instance is classical and `decide` cannot run, yet there is no opaque atom to split. New `decideGround` rewrites propositional `=` to `↔` (`eq_iff_iff`) and lets `simp` evaluate the ground formula. `BinarySearch_safe_bgmc002` goes from 27 evaluate holes to 0. | `Test/Alethe/QF_UF/evaluate_ground` |
| `ac_simp` (cvc5, QF_IDL) | newly surfaced on the same proofs (15 steps in `BinarySearch_safe_bgmc002`): a **nested mixed `∧`/`∨`** conjunction that also contains the absorbing element `false`, e.g. `(and (not (>= (+ F22 (* -1 F22)) 0)) false (not (or …)))`. lean-smt's `ac_simp` went straight to `Meta.AC.rewriteUnnormalizedTop`, which cannot normalize the mixed nesting (`[ac_rfl_top]`). | fixed two ways. (1) `ac_simp` now shares the reflective `AciNorm` path with `aci_simp`, so simple single-layer Boolean `ac_simp` is reflective (it was AC-rewrite before) — `AciNorm` treats every non-`∧`/`∨` subterm as an opaque atom. (2) These QF_IDL steps still exceed `AciNorm` (it flattens one connective layer only, and models the *neutral* element but not the *absorbing* one, and treats a nested opposite-connective as an atom), so `ac_simp` was also added to the core-rule lists (cvc5's `run-arms.sh`, `check-alethe.sh`, the `alethe`-tactic default) — it was previously only in the veriT-only `LEGACY` set. Carcara then reduces all 45 of `BinarySearch`'s `ac_simp` to Boolean core rules and the proof checks fully valid (trusted 0). A fully reflective solution would need a multi-layer, absorbing-aware normalizer. | — (corpus proof) |

## Algebra of the AC-simplification rules (`ac_simp`/`aci_simp`/`absorb` vs `poly_simp`)

The rewrite rules that normalize an associative operator (`ac_simp`, `aci_simp`, `absorb`,
`poly_simp`) split cleanly by the algebraic structure of the operator. The properties that a
normalizer can exploit — and the structure each combination names — determine which rule should
own which operator (and what a reflective lean-smt checker can do). Carcara already encodes the
key distinction in `simplification.rs` (`is_assoc`, `is_idempotent`, `identity_of_op`).

| operator | assoc | comm | idempotent (`x∘x=x`) | unit (identity) | annihilator (zero) | self-inverse (`x∘x=unit`) | algebraic structure | simp rule |
|---|:---:|:---:|:---:|:---:|:---:|:---:|---|---|
| `and` | ✓ | ✓ | ✓ | `⊤` | `⊥` | ✗ | bounded semilattice | `semilattice_simp` |
| `or` | ✓ | ✓ | ✓ | `⊥` | `⊤` | ✗ | bounded semilattice | `semilattice_simp` |
| `bvand` | ✓ | ✓ | ✓ | `~0` (all ones) | `0` | ✗ | bounded semilattice | `semilattice_simp` |
| `bvor` | ✓ | ✓ | ✓ | `0` | `~0` (all ones) | ✗ | bounded semilattice | `semilattice_simp` |
| `+` | ✓ | ✓ | ✗ | `0` | — | ✗ (inverse `−x`) | abelian group | `poly_simp` |
| `bvadd` | ✓ | ✓ | ✗ | `0` | — | ✗ (inverse, mod `2^w`) | abelian group | `poly_simp` |
| `*` | ✓ | ✓ | ✗ | `1` | `0` | ✗ | commutative monoid with zero (ring ×) | `poly_simp` |
| `bvmul` | ✓ | ✓ | ✗ | `1` | `0` | ✗ | commutative monoid with zero (ring ×) | `poly_simp` |
| `bvxor` | ✓ | ✓ | ✗ | `0` | — | ✓ (`x⊕x=0`) | abelian group of exponent 2 (GF(2)) | own BV/GF(2) rule |
| `concat` (`BvConcat`) | ✓ | ✗ | ✗ | empty (width 0) | — | ✗ | free (non-commutative) monoid | `assoc_simp` |
| `str.concat` | ✓ | ✗ | ✗ | `""` | — | ✗ | free (non-commutative) monoid | `assoc_simp` |

The property-combinations, built up from the shared base, name progressively finer structures —
and each finer structure admits a stronger normal form:

| properties | structure | normal form |
|---|---|---|
| assoc + unit | monoid | flatten + drop unit; compare as a **sequence** (`assoc_simp`) |
| + commutative | commutative monoid | as above, compare as a **multiset** |
| + annihilator | commutative monoid with zero | multiset, collapsing to zero if it occurs |
| + idempotent | **bounded semilattice** | compare as a **set** — a bitset, which lean-smt's reflective `AciNorm` evaluates in the kernel (`semilattice_simp`) |
| commutative monoid + inverse | abelian group | ring/group normal form (`poly_simp`) |
| abelian group, every `x` self-inverse | abelian group of exponent 2 (GF(2)) | GF(2) normal form (own rule) |

Reading the lines:

- **idempotence** separates `semilattice_simp` (dedup, set/bitset normal form — the only case
  lean-smt's `AciNorm` handles reflectively) from everything else. Applying it uniformly across
  `is_assoc` would let the rule prove `(= (+ x x) x)`, which is why Carcara gates it behind
  `is_idempotent`.
- **commutativity** separates `assoc_simp` (the concats — a *sequence* normal form, since order
  matters) from the commutative tiers (a *multiset*/set normal form).
- within the commutative, non-idempotent tier, **which inverse law holds** separates `poly_simp`
  (rings: `+ * bvadd bvmul`) from the lone `bvxor` (GF(2), `x⊕x=0`), which no other rule covers.

Consequences for naming and ownership:

- Restricting `aci_simp` to `{and, or, bvand, bvor}` and calling it `semilattice_simp` is
  algebraically exact and matches what the reflective lean-smt normalizer can do; `poly_simp`
  already subsumes `{+, *, bvadd, bvmul}` (it even reduces mod `2^w` for the bitvector sorts).
- That restriction leaves two residues with no home: the **concats** (`assoc_simp` — free
  monoids) and **`bvxor`** (a GF(2) rule, *not* `assoc_simp`, since it is commutative and its
  simplification reorders and cancels `x⊕x`). Grouping `bvxor` with the concats under `assoc_simp`
  would under-describe it the same way `semilattice_simp` would under-describe `bvmul`.
- The absorbing element is a per-operator constant like the unit: adding it to the semilattice
  normalizer is a `absorbing_of_op` lookup gated exactly like `identity_of_op`, not a new law to
  thread through every operator.
