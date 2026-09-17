import Smt

-- The same proof *before* Carcara's `polyeq` pass canonicalizes it: the `distinct_elim` states
-- its pairs flipped. The checker refuses that step rather than reconciling two conjunctions of
-- n(n-1)/2 conjuncts, so it becomes a trusted step and the rest of the proof still checks. This
-- is the guard on the contract with the elaborator.
#check_alethe "Test/Alethe/QF_UF/distinct_noncanonical.smt2" "Test/Alethe/QF_UF/distinct_noncanonical.alethe"
