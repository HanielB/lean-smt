import Smt

-- the assumptions are the assertions up to the spelling of numerals, the one difference Carcara's
-- `polyeq` pass leaves (it identifies numerals by value): `0.0` as `0/1`, `(/ 1 3)` as
-- `(/ 1.0 3.0)`, under a binder too
#check_alethe "Test/Alethe/M0/assume_polyeq.smt2" "Test/Alethe/M0/assume_polyeq.alethe"
