def Fixtures.ProofInSpec.Spec.T : Prop := True
-- The proof is declared in the spec module, not under Proofs/.
theorem Fixtures.ProofInSpec.Proofs.T : Fixtures.ProofInSpec.Spec.T := trivial
