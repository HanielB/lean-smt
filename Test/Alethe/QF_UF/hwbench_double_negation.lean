import Smt

-- cvc5 proof (QF_UF/2018-Goel-hwbench/QF_UF_h_Vlunc_ab_cti_max) whose resolution steps let one
-- `(not p)` eliminate both `p` and `(not (not p))`, as its SAT solver sees them. Carcara's
-- elaborator (69c92a64) reduces the stacked negation with a `not_not` step and writes the chain;
-- before that it kept the step without pivots and the checker trusted it.
#check_alethe "Test/Alethe/QF_UF/hwbench_double_negation.smt2" "Test/Alethe/QF_UF/hwbench_double_negation.alethe"
