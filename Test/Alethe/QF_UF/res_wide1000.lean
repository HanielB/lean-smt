import Smt

set_option smt.alethe.reflect true

-- a 1000-literal clause, resolved with one unit and stated at 999 literals, then closed
#check_alethe "Test/Alethe/QF_UF/res_wide1000.smt2" "Test/Alethe/QF_UF/res_wide1000.alethe"
