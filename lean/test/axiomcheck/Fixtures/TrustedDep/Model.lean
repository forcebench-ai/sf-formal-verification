import Fixtures.TrustedDep.Lib
-- Trusted model code (think SfVerify/Apex/Semantics) whose definition contains an untrusted proof.
def Fixtures.TrustedDep.Model.one : Fin 2 := ⟨1, Fixtures.TrustedDep.Lib.oneLtTwo⟩
