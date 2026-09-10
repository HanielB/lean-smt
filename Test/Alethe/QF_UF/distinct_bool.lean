import Smt

-- `distinct_elim` over three or more Booleans concludes `false`: no three propositions are
-- pairwise distinct.
#check_alethe "Test/Alethe/QF_UF/distinct_bool.smt2" "Test/Alethe/QF_UF/distinct_bool.alethe"
