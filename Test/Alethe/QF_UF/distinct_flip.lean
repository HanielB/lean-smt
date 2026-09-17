import Smt

-- A `distinct_elim` whose producer flipped every disequality's orientation. The rule admits
-- either orientation, so this is a polyequality, and Carcara's `polyeq` pass eliminates it: the
-- step concludes the canonical elimination and a bridge of `eq_symmetric`/`cong` steps restores
-- the stated conclusion. This fixture is the elaborated form, so what the checker sees is a
-- canonical `distinct_elim` -- closed by one ascribed `rfl` -- plus that bridge. The checker
-- refuses a non-canonical `distinct_elim` rather than reconciling the two conjunctions, which
-- is quadratic in the pair count.
#check_alethe "Test/Alethe/QF_UF/distinct_flip.smt2" "Test/Alethe/QF_UF/distinct_flip.alethe"
