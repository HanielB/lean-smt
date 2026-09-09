import Smt

-- veriT proof whose `bfun_elim` expands a quantifier over a Boolean variable: the instantiation
-- carries the instances of the quantified body, which `alignInstances` reconciles
#check_alethe "Test/Alethe/UF/bird_tree_bfun.smt2" "Test/Alethe/UF/bird_tree_bfun.alethe"
