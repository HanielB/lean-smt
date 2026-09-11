import Smt

-- `boolean_group_simp`: `xor` layers equal modulo associativity, commutativity, the neutral
-- element `false` and the cancellation `x ⊕ x = false` — the parity normal form, checked by the
-- reflective normalizer (the bitset folded with `Nat.xor`).
#check_alethe "Test/Alethe/QF_UF/boolean_group.smt2" "Test/Alethe/QF_UF/boolean_group.alethe"
