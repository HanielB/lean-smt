import Smt

-- `la_tautology` in both of its forms: one literal whose sides differ by a constant, and a
-- disjunction of two bounds on the same term (the five cases of Carcara's checker).
#check_alethe "Test/Alethe/QF_LIA/la_tautology.smt2" "Test/Alethe/QF_LIA/la_tautology.alethe"
