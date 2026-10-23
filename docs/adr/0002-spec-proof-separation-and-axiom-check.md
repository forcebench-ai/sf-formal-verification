# ADR 0002: Spec/proof separation and the axiom check

- **Status:** accepted
- **Date:** 2026-10-23

## Context

The kickoff's anti-gaming rules require:

1. `lean/Spec/` holds *statements only*. It is human-owned and frozen.
2. No `sorry`, `admit`, `native_decide` or new `axiom` outside an allowlist in
   `lean/ApexVerify/Semantics/Axioms.lean`.
3. CI runs the equivalent of `#print axioms` on every top-level theorem and fails on anything
   outside the allowlist.

Lean has no "theorem without a proof" other than `sorry`, which is exactly what we ban. So we need
a way to keep a statement in one file and its proof in another, and a mechanical check that the
two match.

Proofs are untrusted and possibly adversarial. Not malicious, but an optimiser under pressure to
make CI green will find any loophole. The check has to hold up against:

| Gaming move | Example |
|---|---|
| Prove a weaker statement | prove `P1'` that drops a conjunct, then report it as `P1` |
| Hide a statement from the check | add a Spec file that no root module imports |
| Use an escape hatch | `sorry` (→ `sorryAx`), `native_decide` (→ an auxiliary axiom per use in Lean 4.35, `Lean.ofReduceBool` before), a new `axiom` |
| Skip the kernel | `set_option debug.skipKernelTC true` or meta-code that adds declarations unchecked |
| Forge the metadata | tamper with the per-module axiom data that `collectAxioms` reads from `.olean` files |
| Make compiled code differ from kernel code | `@[implemented_by]` / `@[extern]` on a semantics function, so difftest tests code the proofs never saw |

## Decision

### Statements and proofs

- A **statement** is a parameterless `def <Name> : Prop := …` declared in a module under
  `lean/Spec/`, in namespace `Spec`.
  - **Every** such definition is a proof obligation. There's no opt-in marker that someone could
    forget to add, so the convention fails safe. Helper predicates in `Spec/` must take at least
    one parameter, which automatically keeps them off the obligation list.
  - Statements must not be universe-polymorphic.
- The **proof** of `Spec.X.Y` is a `theorem` named `Proofs.X.Y`, declared in a module under
  `lean/Proofs/`, whose type is *syntactically* the constant `Spec.X.Y`. Being merely
  definitionally equal is not enough: the type must literally be `Spec.X.Y`.

We considered putting `theorem`s directly in `Spec/` with proof terms imported from `Proofs/`.
That is equally strong, but it forces `Spec/` to import `Proofs/`, so a spec-only PR could not
build without its proofs. The convention above keeps `Spec/` independent.

### The checker: `lake exe axiomcheck`

`lean/AxiomCheck.lean`, a few hundred lines that are part of the trusted base:

1. **Discovers modules from disk.** It walks every `.lean` file under `Spec/` and `Proofs/` (and
   imports `ApexVerify` and `Subjects` too). It doesn't rely on root modules' import lists, so a
   statement in an un-imported file is still found. The `lakefile.toml` globs build the same files.
2. **Collects obligations** from each `Spec` module's own declaration list, so it works by file
   rather than by namespace. A `Prop` definition in a Spec file but outside namespace `Spec` is an
   error.
3. **Matches each obligation to its proof** using the rules above. A missing proof, a proof in the
   wrong place, or a proof of a different type is a failure. `--allow-unproven` downgrades a
   missing proof to a warning for local work; CI never passes it.
4. **Computes axioms itself** by walking the constants reachable from each proof's type and value,
   without using Lean's cached per-module axiom data. Anything not in
   `ApexVerify.Semantics.Axioms.allowed` is a failure. This is the `#print axioms` check, done
   programmatically and independently of `.olean` metadata.
5. **Checks execution fidelity.** No constant from this project that a statement or proof reaches
   may carry `@[implemented_by]` or `@[extern]`, or be `opaque`/`partial`.
6. **Kernel replay.** Every constant not in the toolchain's `Init` is re-sent to the Lean kernel
   with `Lean.Kernel.Environment.replay`, starting from a fresh environment that has imported only
   `Init`. A declaration that was added with kernel checking disabled, or forged by meta-code, is
   rejected here.

The exit status is non-zero on any failure, and the report lists every obligation with its axioms.

### Defence in depth: the lint

`tools/lint/escape_hatches.py` scans the source, with comments and strings stripped, for `sorry`,
`admit`, `native_decide`, `bv_decide`, `ofReduceBool`, `axiom` (outside `Axioms.lean`),
`implemented_by`, `extern`, `debug.skipKernelTC`, and `partial`/`unsafe`/`opaque` in the trusted
semantics. It catches escape hatches that no theorem depends on *yet*, which the checker can't see.

### Self-tests

`lean/test/axiomcheck/` holds small fixture packages: one that must pass and one per gaming move
in the table above, each of which must fail with a specific message. CI runs them, so a regression
in the checker shows up as a red build rather than as silently accepted bad proofs.

## Consequences

- Spec authors write `def P : Prop`, not `theorem`. Reviewers read only `Spec/` and the
  definitions it mentions.
- The checker trusts the Lean toolchain (`Init`, the kernel, `importModules`) and the compiler that
  builds the checker itself. Both are listed in `docs/trusted-base.md`.
- **Process gap:** CODEOWNERS can route `Spec/` changes to the maintainer. But when an AI agent
  pushes using the maintainer's own GitHub credentials, GitHub can't tell the two apart, and
  branch protection can't require "someone else's" approval. Until agents use a separate bot
  identity, the frozen-spec rule is enforced by review discipline and by `git log -- lean/Spec`,
  not by GitHub.
