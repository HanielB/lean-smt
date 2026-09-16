import Smt

-- a flipped equality is not an assertion of the problem: Carcara's `polyeq` pass rewrites such an
-- `assume` to the assertion before the proof reaches the checker, so the checker does not accept it
#check_alethe "Test/Alethe/M0/assume_flipped.smt2" "Test/Alethe/M0/assume_flipped.alethe"
