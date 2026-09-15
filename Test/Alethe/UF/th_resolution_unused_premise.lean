import Smt

-- veriT proof (UF/sledgehammer/Fundamental_Theorem_Algebra/uf.560771) with a `th_resolution` of
-- `(cl p)` against the `not_simplify` equality `(= (not (not p)) p)` concluding `(cl p)` again: the
-- equality is never resolved against. Carcara's elaborator (69c92a64) drops the step; before that
-- it kept it without pivots and the checker trusted it.
#check_alethe "Test/Alethe/UF/th_resolution_unused_premise.smt2" "Test/Alethe/UF/th_resolution_unused_premise.alethe"
