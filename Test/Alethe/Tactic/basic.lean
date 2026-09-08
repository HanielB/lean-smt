import Smt

-- The `alethe` tactic needs Carcara: `smt.alethe.carcara`, `$CARCARA`, or `carcara` in the PATH.

example (p q : Prop) (hp : p) (hpq : p → q) : q := by
  alethe [hp, hpq]

example [Nonempty U] {f : U → U → U} {a b c d : U}
  (h0 : a = b) (h1 : c = d) (h2 : p1 ∧ True) (h3 : (¬ p1) ∨ (p2 ∧ p3))
  (h4 : (¬ p3) ∨ (¬ (f a c = f b d))) : False := by
  alethe [h0, h1, h2, h3, h4]

example (x y : Int) (h : x < y) : x + 1 ≤ y := by
  alethe [h]

example (x y z : Int) (h₁ : 2 * x + 3 * y ≤ 7) (h₂ : x - y = 1) (h₃ : z = x + y) : 5 * z ≤ 19 := by
  alethe [h₁, h₂, h₃]

example [Nonempty U] (f : U → U) (a : U) (h : ∀ x, f x = x) : f (f a) = a := by
  alethe [h]

example (p : Int → Prop) (h : ∀ x, p x → p (x + 1)) (h0 : p 0) : p 2 := by
  alethe [h, h0]

-- corner cases: names that look like the checker's internal symbols, repeated binder names,
-- skolemization, `ite`, `Nat`, large literals, disequality
example («s!2» : Int) (h : «s!2» > 0) : «s!2» ≥ 1 := by alethe [h]
example («s~0» «@p_1» : Int) (h : «s~0» < «@p_1») : «s~0» + 1 ≤ «@p_1» := by alethe [h]
example : ∀ _x : Int, ∀ x : Int, x = x := by alethe
example (y : Int) (h : y > 0) : ∀ x : Int, x > 0 → x ≥ 1 := by alethe [h]
example (f : Int → Int) (h : ∃ x, f x > 0) : ∃ y, f y ≥ 1 := by alethe [h]
example (f : Int → Int) (h : ∀ x, ∃ y, f y > x) : ∃ y, f y > 10 := by alethe [h]
example (x : Int) : (if x > 0 then x else -x) ≥ 0 := by alethe
example (n m : Nat) (h : n - m = 0) (h2 : m < n) : False := by alethe [h, h2]
example (x : Int) (h : x > 123456789012345678901234567890) : x > 0 := by alethe [h]
example (a b : Int) (h1 : a ≠ b) (h2 : a = b) : False := by alethe [h1, h2]
example (f : Int → Int → Int → Int) (a b : Int) (h : a = b) : f a b a = f b a b := by alethe [h]
