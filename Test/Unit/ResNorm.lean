import Smt

-- The reflective clause checker behind the clausal Alethe rules (`smt.alethe.reflect`): the
-- premises reified as clauses over a context of atoms, the chain folded on bitsets by the kernel,
-- and `check_sound` applied as a term.

open Lean Elab Tactic Smt.Reconstruct.Prop.ResNorm

/-- `res_norm h₁ … hₙ` closes the goal by the reflective chain from the hypotheses, in order,
with no pivot hints. -/
elab "res_norm" hs:(colGt term:max)* : tactic => do
  let mv ← getMainGoal
  let mut premises := #[]
  for h in hs do
    let e ← elabTerm h none
    premises := premises.push (e, ← Meta.inferType e)
  let hints := Array.replicate (premises.size - 1) none
  let some p ← proveClause premises hints (← mv.getType)
    | throwError "[res_norm] the chain does not reach the goal"
  mv.assign p
  replaceMainGoal []

-- binary resolution
example (a b c : Prop) (h₁ : a ∨ b) (h₂ : ¬a ∨ c) : b ∨ c := by res_norm h₁ h₂
-- the pivot negated in the running clause
example (a b c : Prop) (h₁ : ¬a ∨ b) (h₂ : a ∨ c) : b ∨ c := by res_norm h₁ h₂
-- unit propagation to the empty clause
example (a b c : Prop) (h₀ : a ∨ b ∨ c) (h₁ : ¬a) (h₂ : ¬b) (h₃ : ¬c) : False := by
  res_norm h₀ h₁ h₂ h₃
-- a chain whose intermediate clauses are wide
example (a b c d e : Prop) (h₀ : a ∨ b ∨ c ∨ d) (h₁ : ¬a ∨ e) (h₂ : ¬b ∨ e) (h₃ : ¬c ∨ e) (h₄ : ¬d ∨ e) :
    e := by res_norm h₀ h₁ h₂ h₃ h₄
-- the conclusion may reorder, duplicate and weaken (containment, not equality)
example (a b c d : Prop) (h₁ : a ∨ b) (h₂ : ¬a ∨ c) : d ∨ c ∨ b ∨ c := by res_norm h₁ h₂
-- a single premise: contraction, reordering, weakening
example (a b : Prop) (h : a ∨ b ∨ a) : b ∨ a := by res_norm h
example (a b : Prop) (h : a) : b ∨ a := by res_norm h
-- a tautological premise `l ∨ ¬l` resolved on `l` keeps its `l`
example (a b : Prop) (h₁ : a) (h₂ : ¬a ∨ a) (h₃ : ¬a ∨ b) (h₄ : ¬b) : False := by
  res_norm h₁ h₂ h₃ h₄
-- every occurrence of the pivot leaves the running clause, and the pivot's negation the premise
example (a b : Prop) (h₁ : a ∨ b ∨ a) (h₂ : ¬a ∨ ¬a ∨ b) : b := by res_norm h₁ h₂
-- a premise with no pivot is merged
example (a b c : Prop) (h₁ : a ∨ b) (h₂ : c) : a ∨ b ∨ c := by res_norm h₁ h₂
-- atoms are compared syntactically, so a nested connective is one literal
example (a b c : Prop) (h₁ : (a ∧ b) ∨ c) (h₂ : ¬(a ∧ b)) : c := by res_norm h₁ h₂
-- `False` as a bare premise is the empty clause; `True` is an atom
example (a : Prop) (h : False) : a := by res_norm h
example (a : Prop) (h₁ : a ∨ True) (h₂ : ¬a) : True := by res_norm h₁ h₂
-- must fail: the chain does not reach the goal
/-- error: [res_norm] the chain does not reach the goal -/
#guard_msgs in
example (a b c : Prop) (h₁ : a ∨ b) (h₂ : ¬a ∨ c) : b := by res_norm h₁ h₂
-- must fail: a stacked negation is declined (the caller falls back)
/-- error: [res_norm] the chain does not reach the goal -/
#guard_msgs in
example (a b : Prop) (h₁ : ¬¬a ∨ b) (h₂ : ¬a) : b := by res_norm h₁ h₂

-- the 230-premise shape of the profiled benchmark: one wide clause against unit clauses
example (p : Nat → Prop)
    (h : p 0 ∨ p 1 ∨ p 2 ∨ p 3 ∨ p 4 ∨ p 5 ∨ p 6 ∨ p 7 ∨ p 8 ∨ p 9 ∨ p 10 ∨ p 11 ∨ p 12 ∨ p 13 ∨
      p 14 ∨ p 15 ∨ p 16 ∨ p 17 ∨ p 18 ∨ p 19 ∨ p 20 ∨ p 21 ∨ p 22 ∨ p 23 ∨ p 24 ∨ p 25 ∨ p 26 ∨
      p 27 ∨ p 28 ∨ p 29 ∨ p 30 ∨ p 31)
    (n0 : ¬p 0) (n1 : ¬p 1) (n2 : ¬p 2) (n3 : ¬p 3) (n4 : ¬p 4) (n5 : ¬p 5) (n6 : ¬p 6)
    (n7 : ¬p 7) (n8 : ¬p 8) (n9 : ¬p 9) (n10 : ¬p 10) (n11 : ¬p 11) (n12 : ¬p 12) (n13 : ¬p 13)
    (n14 : ¬p 14) (n15 : ¬p 15) (n16 : ¬p 16) (n17 : ¬p 17) (n18 : ¬p 18) (n19 : ¬p 19)
    (n20 : ¬p 20) (n21 : ¬p 21) (n22 : ¬p 22) (n23 : ¬p 23) (n24 : ¬p 24) (n25 : ¬p 25)
    (n26 : ¬p 26) (n27 : ¬p 27) (n28 : ¬p 28) (n29 : ¬p 29) (n30 : ¬p 30) (n31 : ¬p 31) :
    False := by
  res_norm h n0 n1 n2 n3 n4 n5 n6 n7 n8 n9 n10 n11 n12 n13 n14 n15 n16 n17 n18 n19 n20 n21 n22
    n23 n24 n25 n26 n27 n28 n29 n30 n31

#print axioms check_sound
