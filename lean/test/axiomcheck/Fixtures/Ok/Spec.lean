namespace Fixtures.Ok.Spec
/-- A helper predicate: it takes a parameter, so it is not an obligation. -/
def IsEven (n : Nat) : Prop := n % 2 = 0
def T : Prop := ∀ n : Nat, IsEven (2 * n)
end Fixtures.Ok.Spec
