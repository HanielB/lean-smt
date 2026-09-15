import Smt

set_option smt.alethe.reflect true

-- a tautological premise (cl (not p) p) resolved on p keeps its p
#check_alethe "Test/Alethe/M0/res_tautology.smt2" "Test/Alethe/M0/res_tautology.alethe"
