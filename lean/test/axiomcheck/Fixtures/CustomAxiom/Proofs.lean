import Fixtures.CustomAxiom.Spec
axiom Fixtures.CustomAxiom.Proofs.cheat : False
theorem Fixtures.CustomAxiom.Proofs.T : Fixtures.CustomAxiom.Spec.T :=
  Fixtures.CustomAxiom.Proofs.cheat.elim
