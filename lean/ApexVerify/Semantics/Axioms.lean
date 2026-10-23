/-!
# Axiom allowlist

**Trusted base** (`docs/trusted-base.md` §4). These are the only axioms a proof of a `Spec`
statement may depend on. `lake exe axiomcheck` rejects every other axiom, including `sorryAx`
(from `sorry`/`admit`) and the compiler-trusting axioms behind `native_decide`/`bv_decide`.

Adding an entry is a trusted-base change. Update the table in `docs/trusted-base.md` in the same
PR and justify it there. A project-specific axiom, if one is ever needed, must be declared in
this file next to the list. The escape-hatch lint rejects the `axiom` keyword everywhere else.
-/

namespace ApexVerify.Semantics.Axioms

/-- Lean's three standard axioms; nothing project-specific. -/
def allowed : List Lean.Name :=
  [``propext, ``Quot.sound, ``Classical.choice]

end ApexVerify.Semantics.Axioms
