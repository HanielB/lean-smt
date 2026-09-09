import Smt

-- congruence over `distinct` where the rewritten argument is a compound term: the motive must
-- be built with `kabstract`, since `Expr.abstract` only abstracts free variables
#check_alethe "Test/Alethe/QF_UF/cong_distinct.smt2" "Test/Alethe/QF_UF/cong_distinct.alethe"
