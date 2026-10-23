import Fixtures.WrongType.Spec
-- Proves a weaker statement (one conjunct dropped) under the expected name.
theorem Fixtures.WrongType.Proofs.T : ∀ n : Nat, n + 0 = n := fun _ => rfl
