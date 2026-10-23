/-!
# Spec

Theorem **statements** only: human-owned and frozen (README, rule 1; ADR 0002).

Every parameterless `def _ : Prop` declared in a module under `Spec/` is a proof obligation. Its
proof is the `theorem` of the same name with `Spec` replaced by `Proofs`, in a module under
`Proofs/`. `lake exe axiomcheck` enforces this.

Changing anything here needs a PR tagged `spec-change` that explains why.
-/
