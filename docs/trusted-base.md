# Trusted base

A proof in this repository establishes: **"the Apex code, as modelled, satisfies the statement, as
written."** Whether that tells you anything about real Salesforce depends entirely on the items
below. This list is the whole answer to "what do I have to believe?". If something you must
believe is missing from it, that is a bug; please open an issue.

Paths marked 🔒 are covered by `.github/CODEOWNERS`.

## 1. Theorem statements 🔒

`lean/Spec/`. Each parameterless `def … : Prop` there is a claim we make. Read these, and the
definitions they mention, to find out what is actually proven. The English in the README is a
summary only.

*Risk:* a statement is weaker than intended, for example it quantifies over too few inputs or drops
a conjunct. *Mitigation:* human review, the freeze rule (ADR 0002), and statements written to
mirror the developer's own harness assertions. Mechanically: a statement may only depend on
definitions in `Spec/`, the trusted modules (items 2, 3, 5) and the toolchain, so editing
untrusted code can't change its meaning. Spec files may not contain notation, macros, instances
or meta-code, so the source text is what it means.

## 2. Apex syntax and semantics 🔒

`lean/ApexVerify/Syntax/` and `lean/ApexVerify/Semantics/`. These define what each Apex construct
in [the subset](apex-subset.md) *means*.

*Risk:* the model differs from real Apex, for example on null handling, string comparison or
Decimal equality. A proof about a wrong model can be vacuous. *Mitigation:* every rule is exercised
by `tools/difftest` against a real org, and every deliberate simplification is listed in
[`platform-model.md`](platform-model.md).

## 3. Platform model 🔒

`lean/ApexVerify/Platform/`: sObject records, field access, `addError`, limit counters, and the
trigger-context assumptions (for example, `oldMap` is null on insert).

*Risk and mitigation:* the same as item 2. The trigger-context assumptions appear in the statements
as hypotheses, so they are visible in item 1 as well.

## 4. Axiom allowlist 🔒

`lean/ApexVerify/Semantics/Axioms.lean`. The only axioms any proof may depend on.

| Axiom | Justification |
|---|---|
| `propext` | Lean's standard propositional extensionality. Used by `simp`. |
| `Quot.sound` | Lean's standard quotient soundness. Gives function extensionality. |
| `Classical.choice` | Lean's standard choice axiom. Used by classical reasoning. |

No project-specific axioms exist. Adding one is a `spec-change`-level decision and must update this
table.

## 5. Exporter and parser 🔒

`tools/apex-to-lean/` and the `@apexdevtools/apex-parser` grammar it uses. They turn
`subjects/**/*.cls` into the Lean terms in `lean/Subjects/` that the statements talk about.

*Risk:* the exported term isn't the code that runs in the org. *Mitigation:* the exporter is kept
tiny; round-trip tests check that parse → Lean AST → pretty-print → re-parse gives the same AST;
CI regenerates `lean/Subjects/` from the `.cls` files and fails on any diff. (Milestone 3.)

## 6. The checker, lint and CI 🔒

`lean/AxiomCheck.lean`, `tools/lint/`, `tools/kernels/`, `.github/workflows/ci.yml`, `Makefile`. These decide whether
a statement counts as proven.

*Risk:* the checker misses a statement or accepts an escape hatch. *Mitigation:* the checker
discovers modules from disk, computes axioms itself, kernel-replays every project declaration, and
has self-tests with deliberately bad proofs that it must reject (ADR 0002).

## 7. Lean toolchain

Pinned in `lean/lean-toolchain` (currently `leanprover/lean4:v4.35.0`). We trust:

- the **kernel**, which checks every proof term and replays every declaration. This trust is
  reduced, not removed: CI re-checks every project declaration with
  [nanoda](https://github.com/ammkrn/nanoda_lib), an independent type checker written in Rust
  (`tools/kernels/nanoda.sh`, pinned). A kernel bug would have to exist in both to go unnoticed;
- `Init`, the core library that the replay starts from, which is not itself re-checked;
- the **compiler**, which builds the checker and the reference interpreter that difftest runs.
  Proofs don't depend on the compiler. The difftest evidence that the model matches reality does.

## 8. The reference org 🔒 (by process)

The dedicated Developer Edition org that difftest and the Apex tests run against (ADR 0003). We
trust that it is representative: no extra automation on the modelled objects, and an API version
recorded with each difftest run.

## 9. Process

We trust that `Spec/` and the other 🔒 paths change only through reviewed PRs. See the process gap
recorded in ADR 0002: until agents push under a separate identity, GitHub can't enforce this on its
own.

## Not trusted

You do **not** need to trust any of these:

- `lean/Proofs/`: every proof is re-checked by the kernel, however it was produced;
- `lean/ApexVerify/Lib/`: reusable lemmas, also kernel-checked;
- tactics, `simp` sets, the elaborator, and any LLM output;
- the Apex harness and example tests in `subjects/`: useful evidence, but not part of any proof.

## Changes to the trusted base

| Milestone | Change |
|---|---|
| 1 | Initial trusted base: the standard three axioms, the checker, the lint, the CI workflow. No semantics yet. |
