import Fixtures.UntrustedDep.Lib
-- Reads like a real property, but its meaning lives in untrusted code.
def Fixtures.UntrustedDep.Spec.T : Prop := Fixtures.UntrustedDep.Lib.easy
