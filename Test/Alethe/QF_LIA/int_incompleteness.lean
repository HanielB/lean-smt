import Smt

-- veriT proof of an integer-incompleteness benchmark: the Farkas combination is contradictory
-- only after the integer bounds are rounded to a multiple of their coefficients' gcd
#check_alethe "Test/Alethe/QF_LIA/int_incompleteness.smt2" "Test/Alethe/QF_LIA/int_incompleteness.alethe"
