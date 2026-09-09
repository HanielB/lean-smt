import Smt

-- veriT proof (core pipeline): the `bfun_elim` and `ite_intro` reductions of the core pass,
-- whose ite selection axioms and Boolean instantiations the checker takes directly
#check_alethe "Test/Alethe/QF_UF/goel_h_b04.smt2" "Test/Alethe/QF_UF/goel_h_b04.alethe"
