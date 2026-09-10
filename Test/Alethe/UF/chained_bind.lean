import Smt

-- veriT's chained renaming: an anchor `((y S) (z S) (:= x y) (:= y z))` where a kept variable is
-- also substituted. A `bind` whose sides are the same formula up to bound-variable names closes by
-- reflexivity (t33 here). The one that remains trusted, t21, also flips an equality by
-- `eq_symmetric` inside the block, and its inner `symm` steps relate the two roles of the same
-- name; Carcara accepts them name-syntactically, and no reading of the block as terms supports
-- them. Regenerating such blocks is Carcara's job; when it does, this expectation drops to valid.
#check_alethe "Test/Alethe/UF/chained_bind.smt2" "Test/Alethe/UF/chained_bind.alethe"
