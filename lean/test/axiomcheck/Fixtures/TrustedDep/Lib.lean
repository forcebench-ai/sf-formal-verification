-- An untrusted lemma. Trusted code may use it as a proof: proofs cannot change meaning.
theorem Fixtures.TrustedDep.Lib.oneLtTwo : 1 < 2 := by decide
