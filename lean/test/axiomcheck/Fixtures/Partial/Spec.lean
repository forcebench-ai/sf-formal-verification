namespace Fixtures.Partial.Spec
partial def loop (n : Nat) : Nat := if n = 0 then 0 else loop (n - 1)
def T : Prop := loop 3 = loop 3
end Fixtures.Partial.Spec
