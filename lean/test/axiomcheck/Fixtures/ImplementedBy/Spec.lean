namespace Fixtures.ImplementedBy.Spec
def fastId (n : Nat) : Nat := n + 1
@[implemented_by fastId] def slowId (n : Nat) : Nat := n
def T : Prop := slowId 1 = 1
end Fixtures.ImplementedBy.Spec
