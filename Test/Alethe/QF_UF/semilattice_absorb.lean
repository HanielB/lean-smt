import Smt

-- `semilattice_simp` with the annihilator: `(and … false …)` collapses to `false` and
-- `(or … true …)` to `true` (what `absorb` used to state), alongside the set normal form with
-- the neutral element; all closed by the reflective `AciNorm` normalizer.
#check_alethe "Test/Alethe/QF_UF/semilattice_absorb.smt2" "Test/Alethe/QF_UF/semilattice_absorb.alethe"
