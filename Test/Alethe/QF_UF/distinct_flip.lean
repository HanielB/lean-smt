import Smt

-- `distinct_elim` whose right-hand conjunction keeps the pair order but flips each disequality's
-- orientation (as Carcara's `polyeq` canonicalization does). Proved by congruence on the `∧`-chain
-- (`ne_symm_eq` at the flipped leaves), which is linear in the number of pairs — the pairwise
-- conversion would be quadratic and runs out of memory on the large `distinct`s of ESC-Java proofs.
#check_alethe "Test/Alethe/QF_UF/distinct_flip.smt2" "Test/Alethe/QF_UF/distinct_flip.alethe"
