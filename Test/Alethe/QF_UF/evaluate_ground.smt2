(set-logic QF_UF)
(assert (not (= (or true false) (and true true))))
(check-sat)
