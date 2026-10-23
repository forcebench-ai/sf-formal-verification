import Fixtures.Ok.Spec
theorem Fixtures.Ok.Proofs.T : Fixtures.Ok.Spec.T := by
  intro n; simp [Fixtures.Ok.Spec.IsEven]
