import Smt

-- `qnt_rm_unused` over an existential: `(∃ x y, p x) = (∃ x, p x)` drops the unused `y`. The
-- shared universal reconstruction cannot do this (it applies the quantified prop as a function);
-- the existential case is proved by Exists.elim/Exists.intro.
#check_alethe "Test/Alethe/UF/qnt_rm_unused_exists.smt2" "Test/Alethe/UF/qnt_rm_unused_exists.alethe"
