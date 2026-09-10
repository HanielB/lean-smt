import Smt

-- `lia_generic` (veriT's unspecified linear integer reasoning) is decided by `omega`; here the
-- rounding `2x ≤ 5 ⟹ x ≤ 2` is what makes the clause a tautology.
#check_alethe "Test/Alethe/QF_LIA/lia_generic.smt2" "Test/Alethe/QF_LIA/lia_generic.alethe"
