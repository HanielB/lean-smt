import Smt

-- `evaluate` on a ground Boolean formula containing an equality *between propositions*
-- `(= (or true false) (and true true))`. `=` on `Prop` has no computable `DecidableEq`, so the
-- instance is classical and `decide` cannot run, yet there is no opaque atom to split on; the
-- handler rewrites the propositional `=` to `↔` and evaluates. (This is the QF_IDL cvc5 shape.)
#check_alethe "Test/Alethe/QF_UF/evaluate_ground.smt2" "Test/Alethe/QF_UF/evaluate_ground.alethe"
