import Smt

-- `bounded_farkas` leaves out the multipliers of the bounds: each is a unit row, and its
-- multiplier is the one that cancels its variable against the rows before it
#check_alethe "Test/Alethe/QF_LIA/bounded_farkas.smt2" "Test/Alethe/QF_LIA/bounded_farkas.alethe"
