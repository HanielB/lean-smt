import Smt

set_option smt.alethe.reflect true

-- 230 unit premises against one 230-literal clause, the shape of the profiled benchmark's largest step
#check_alethe "Test/Alethe/QF_UF/res_chain230.smt2" "Test/Alethe/QF_UF/res_chain230.alethe"
