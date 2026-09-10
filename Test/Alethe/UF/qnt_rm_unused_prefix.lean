import Smt

-- `qnt_rm_unused` dropping a whole quantifier prefix whose body is itself a quantifier: the
-- binders of the result are the body's own, not the ones the rewrite kept
#check_alethe "Test/Alethe/UF/qnt_rm_unused_prefix.smt2" "Test/Alethe/UF/qnt_rm_unused_prefix.alethe"
