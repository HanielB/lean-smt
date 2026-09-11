import Smt

-- the assumptions are the assertions as cvc5 prints them: rationals as `n/d`, an equality
-- flipped, a bound variable renamed (accepted like Carcara's `polyeq` does)
#check_alethe "Test/Alethe/M0/assume_polyeq.smt2" "Test/Alethe/M0/assume_polyeq.alethe"
