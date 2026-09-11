# Lean-SMT

This project provides Lean tactics to discharge goals into SMT solvers.
It is under active development and is currently in a beta phase. While it is
usable, it is important to note that there are still some rough edges and
ongoing improvements being made.

## Supported Theories
`lean-smt` currently supports the theories of Uninterpreted Functions and Linear
Integer/Real Arithmetic with quantifiers. Mathlib is required for Real
Arithmetic. Support for the theory of Bitvectors is at an experimental stage.
Support for additional theories is in progress.

## Setup
To use `lean-smt` in your project, add the following lines to your list of
dependencies in `lakefile.toml`:
```toml
[[require]]
name = "smt"
scope = "ufmg-smite"
rev = "main"
```
If your build configuration is in `lakefile.lean`, add the following line to
your dependencies:
```lean
require smt from git "https://github.com/ufmg-smite/lean-smt.git" @ "main"
```

Alternatively, `lean-smt` has an experimental `no_mathlib` branch which can
be accessed by replacing `main` with `no_mathlib` in your `lakefile.toml`
or `lakefile.lean` file.

## Usage
`lean-smt` comes with one main tactic, `smt`, that translates the current goal
into an SMT query, sends the query to cvc5, and (if the solver returns `unsat`)
replays cvc5's proof in Lean. cvc5's proofs may contain holes, returned as Lean
goals. You can fill these holes manually or with other tactics. To use the `smt`
tactic, you just need to import the `Smt` library:
```lean
import Smt

example [Nonempty U] {f : U → U → U} {a b c d : U}
  (h0 : a = b) (h1 : c = d) (h2 : p1 ∧ True) (h3 : (¬ p1) ∨ (p2 ∧ p3))
  (h4 : (¬ p3) ∨ (¬ (f a c = f b d))) : False := by
  smt [h0, h1, h2, h3, h4]
```
To use the `smt` tactic on Real arithmetic goals, import `Smt.Real`:
```lean
import Smt
import Smt.Real

example (ε : Real) (h1 : ε > 0) : ε / 2 + ε / 3 + ε / 7 < ε := by
  smt [h1]
```
`lean-smt` utilizes
[`lean-auto`](https://github.com/leanprover-community/lean-auto) to monomorphize
goals in dependent type theory and higher-order logic into first-order logic.
Enable auto's monomorphization procedure via `smt +mono`:
```lean
import Smt

variable [Group G]

theorem inverse : ∀ (a : G), a * a⁻¹ = 1 := by
  smt +mono [mul_assoc, one_mul, inv_mul_cancel]

theorem identity : ∀ (a : G), a * 1 = a := by
  smt +mono [mul_assoc, one_mul, inv_mul_cancel, inverse]

theorem unique_identity : ∀ (e : G), (∀ a, e * a = a) ↔ e = 1 := by
  smt +mono [mul_assoc, one_mul, inv_mul_cancel]
```
## Alethe proofs

`lean-smt` can also check proofs in the
[Alethe](https://verit.gitlabpages.uliege.be/alethe/specification.pdf) format,
as produced by cvc5 or veriT and elaborated by
[Carcara](https://github.com/ufmg-smite/carcara). Every step of the proof is
reconstructed with the same machinery as the `smt` tactic and checked by Lean's
kernel; steps that cannot be reconstructed are reported (and returned as goals
by the tactic), never silently trusted.

The command `#check_alethe` checks a proof file against an SMT-LIB problem:
```lean
import Smt

#check_alethe "problem.smt2" "problem.alethe"
-- valid: checked 481 steps, trusted 0, holes 0
```
`scripts/setup-alethe.sh` installs everything that needs: the Lean toolchain, the
lean-smt build (and with it the cvc5 parser plugin), and a Carcara binary.
```
scripts/setup-alethe.sh                 # no-Mathlib build (what the Alethe work uses),
                                        # Carcara cloned and built
scripts/setup-alethe.sh --mathlib       # build with Mathlib (needed only for Real and its tests)
scripts/setup-alethe.sh --carcara-src ~/carcara   # build Carcara from a checkout you have
```
It ends by printing the `CARCARA` line to add to your profile, and by checking a
proof in both of the modes below.

To check a proof from the command line, use `scripts/check-alethe.sh`:
```
scripts/check-alethe.sh problem.smt2 problem.alethe
-- valid: checked 481 steps, trusted 0, holes 0
```
It accepts the same trailing options as `#check_alethe` (`native`, `lax`,
`term`, `timings`) and requires `lake build` to have been run once beforehand.
`problem.alethe` is expected to already be elaborated by Carcara (see below);
to check a raw solver proof directly, pass `--elaborate` and the script runs
it through Carcara first:
```
scripts/check-alethe.sh --elaborate problem.smt2 problem.alethe
```
The proof is expected to be elaborated by Carcara with
```
carcara elaborate --expand-let-bindings --allow-int-real-subtyping \
  --rare-file Smt/Alethe/Rare/rewrites.eo \
  --pipeline polyeq local core-simp-rare budget --core-rules <the *_simplify rules> \
  -- problem.alethe problem.smt2
```
(`polyeq` and `local` make implicit reasoning explicit and give resolution steps
their pivots; the `core-simp-rare` pass turns the `*_simplify` rules into chains of
`rare_rewrite` steps, and relabels the legacy AC rules `aci_simp`/`absorb` to the
structural rules the checker reconstructs — `semilattice_simp` for `and`/`or`,
`boolean_group_simp` for `xor`, `assoc_simp` for concatenation, `poly_simp` for the
ring operators — so list `aci_simp absorb` with the `*_simplify` rules). For veriT
proofs, add the legacy rules `qnt_cnf ite_intro bfun_elim ac_simp` to `--core-rules`.

Checking a large proof is dominated by the kernel replaying the certificates of
the arithmetic steps: `poly_simp` and `la_generic` normalize polynomials, and by
default the kernel evaluates that normalization by reduction. Two options trade
this cost off. `native` runs those normalizations — and the `evaluate` steps —
as compiled code instead, which is several times faster but
puts the Lean compiler in the trusted base. `smt.alethe.jobs` runs that many
kernel calls concurrently, with `smt.alethe.batch` steps to a call.

The `alethe` tactic runs this pipeline on a goal: it translates the goal like
`smt`, asks cvc5 for an Alethe proof, elaborates it with Carcara (an external
process, found through the option `smt.alethe.carcara`, the environment
variable `CARCARA`, or the `PATH`), and checks the result:
```lean
example (p q : Prop) (hp : p) (hpq : p → q) : q := by
  alethe [hp, hpq]
```
It accepts the same configuration and hints as `smt`; the options
`smt.alethe.pipeline`, `smt.alethe.coreRules` and `smt.alethe.rareFile` control
the Carcara run.

`rare_rewrite` steps are checked against Lean theorems generated from the RARE
rule file: `Smt/Alethe/Rare/gen.py` translates every rule of
`Smt/Alethe/Rare/rewrites.eo` into a theorem statement in
`Smt/Alethe/Rare/Rules.lean` (proofs are written in that file and preserved
when the rules are regenerated; a rule whose proof is still `sorry` is reported
as trusted).
