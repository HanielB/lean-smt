import Smt

-- In term mode a step's premises are proof terms, not hypotheses of the stated clause: a
-- reconstructor that reads a premise's type must still see the type the proof states for it.
#check_alethe "Test/Alethe/QF_LRA/metitarski_sin49_term.smt2" "Test/Alethe/QF_LRA/metitarski_sin49_term.alethe" term
