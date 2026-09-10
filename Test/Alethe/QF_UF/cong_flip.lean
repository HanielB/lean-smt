import Smt

-- `cong` between two binary equalities whose arguments are flipped on either side (veriT orders
-- the arguments of an equality as it likes; Carcara tries all four orientations).
#check_alethe "Test/Alethe/QF_UF/cong_flip.smt2" "Test/Alethe/QF_UF/cong_flip.alethe"
