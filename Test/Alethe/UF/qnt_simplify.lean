import Smt

-- `qnt_simplify`: a quantifier whose body is a Boolean constant. `(∀ x, False)` and
-- `(∃ x, True)` need a witness, which the sort's `Nonempty` instance supplies.
#check_alethe "Test/Alethe/UF/qnt_simplify.smt2" "Test/Alethe/UF/qnt_simplify.alethe"
