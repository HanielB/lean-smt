import Smt

set_option smt.alethe.reflect true

-- the `not_not` clause `(cl (not (not (not p))) p)` carries a literal under three negations, which
-- the reflective checker declines; those steps take the term-by-term path
#check_alethe "Test/Alethe/M0/res_stacked_negation.smt2" "Test/Alethe/M0/res_stacked_negation.alethe"
