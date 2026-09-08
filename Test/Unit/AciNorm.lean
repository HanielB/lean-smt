import Smt

-- The verified normalizer behind `aci_simp` (Alethe) and `ACI_NORM` (cvc5): one `∧`/`∨` layer
-- modulo associativity, commutativity, idempotence and the neutral element.


open Lean Elab Tactic Smt.Reconstruct.Prop.AciNorm

elab "aci_norm" : tactic => do
  let mv ← getMainGoal
  aciNorm mv
  replaceMainGoal []

-- reorder
example (a b c : Prop) : (a ∨ b ∨ c) = (c ∨ a ∨ b) := by aci_norm
-- nested, duplicates, neutral element
example (a b c : Prop) : ((a ∨ b) ∨ (c ∨ a) ∨ False) = (b ∨ c ∨ a) := by aci_norm
-- collapse to a single literal, other side not a connective
example (a : Prop) : (a ∨ a ∨ False) = a := by aci_norm
-- conjunction with True
example (a b : Prop) : (True ∧ (b ∧ a) ∧ a) = (a ∧ b) := by aci_norm
-- everything neutral
example : (False ∨ False) = False := by aci_norm
example : (True ∧ True) = True := by aci_norm
-- atoms are compared syntactically: nested connective of the other kind is an atom
example (a b c : Prop) : ((a ∧ b) ∨ c) = (c ∨ (a ∧ b)) := by aci_norm
-- negations are atoms
example (a b : Prop) : (¬a ∨ b ∨ ¬a) = (b ∨ ¬a) := by aci_norm
-- large-ish
example (p : Nat → Prop) :
  (p 9 ∨ p 8 ∨ p 7 ∨ p 6 ∨ p 5 ∨ p 4 ∨ p 3 ∨ p 2 ∨ p 1 ∨ p 0 ∨ p 5) =
  (p 0 ∨ p 1 ∨ p 2 ∨ p 3 ∨ p 4 ∨ p 5 ∨ p 6 ∨ p 7 ∨ p 8 ∨ p 9) := by aci_norm
-- must fail: different leaves
/-- error: [aci_norm] the two sides have different normal forms:
  a ∨ b
=
  a ∨ c -/
#guard_msgs in
example (a b c : Prop) : (a ∨ b) = (a ∨ c) := by aci_norm
-- must fail: the nested connective of the other kind is an atom, not normalized
/-- error: [aci_norm] the two sides have different normal forms:
  a ∧ b ∨ c
=
  b ∧ a ∨ c -/
#guard_msgs in
example (a b c : Prop) : ((a ∧ b) ∨ c) = ((b ∧ a) ∨ c) := by aci_norm
-- must fail: unsound direction (idempotence does not apply to different atoms)
/-- error: [aci_norm] the two sides have different normal forms:
  a ∨ b
=
  a -/
#guard_msgs in
example (a b : Prop) : (a ∨ b) = a := by aci_norm
