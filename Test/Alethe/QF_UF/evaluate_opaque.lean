import Smt

-- An `evaluate` term with an uninterpreted Boolean symbol has a classical `Decidable` instance,
-- so it cannot be decided; the equality holds for either truth value of the atom.
#check_alethe "Test/Alethe/QF_UF/evaluate_opaque.smt2" "Test/Alethe/QF_UF/evaluate_opaque.alethe"
