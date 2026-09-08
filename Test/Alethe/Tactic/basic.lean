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
