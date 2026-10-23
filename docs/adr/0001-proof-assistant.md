# ADR 0001: Lean 4 as the proof assistant

- **Status:** accepted
- **Date:** 2026-10-23

## Context

We need a tool to write a formal semantics for a subset of Apex and a model of the Salesforce
platform, state properties of real Apex classes as theorems, and prove them, with most proofs
expected to be machine-written. What the tool must give us:

| # | Requirement | Why |
|---|---|---|
| R1 | A **small trusted checker** that is independent of how proofs are produced | Proofs will be large and LLM-written. Only the checker, the model and the statements should need human trust. |
| R2 | Comfortable **deep embedding** of another language: inductive ASTs, environments, heaps, outcomes | Apex has no binary to model. We define its syntax and semantics ourselves. |
| R3 | **Executable definitions without a separate translation step** | The semantics must double as a reference interpreter for differential testing against a real org. The closer the executed code is to the code the proofs reason about, the less we trust in between. |
| R4 | Strong **automation** for large, mechanical proofs | Proofs about loops over 200-record lists with nullable fields are long but shallow. |
| R5 | Good **LLM fluency and tooling** | Most proof text will be generated. |
| R6 | A **meta-level in the same language** | We enforce the trust rules (statement/proof matching, axiom allowlist, kernel replay) with code that should be short and auditable. |
| R7 | **Reproducible CI** | Pinned toolchain, fast install, deterministic checking. |

## Decision

Use **Lean 4**. Pin the toolchain exactly (`lean/lean-toolchain`, currently `v4.35.0`) and upgrade
on purpose, never automatically.

Start with **no Mathlib dependency**. Core Lean's `simp`, `omega`, `decide`, `grind` and induction
cover the first subject's arithmetic and list reasoning. Mathlib would multiply build and CI cost.
We'll add Batteries or Mathlib in a later ADR if a concrete proof needs it.

## Alternatives considered

### Rocq (formerly Coq)

The strongest pedigree for programming-language semantics: CompCert, VST, Iris, CakeML-adjacent
work. Small kernel, excellent for deep embeddings (R1, R2 ✓).

Why not:
- **R3:** you execute Rocq definitions by *extraction* to OCaml. Extraction is a separate,
  unverified translation, and the extracted interpreter is a different artifact from the terms the
  proofs reason about. In-kernel evaluation (`vm_compute`, `native_compute`) is faster but widens
  the trusted base, much as `native_decide` does in Lean.
- **R5/R7:** a smaller pool of recent LLM-written proofs, and heavier CI setup (opam, plugin
  versions such as CoqHammer).

Rocq is a close second. Nothing in this project depends on a feature Rocq lacks.

### Dafny

Auto-active verification: specifications and proofs live in the code and go to Z3 through Boogie.
Very productive for verifying *Dafny programs*.

Why not:
- **R1:** the trusted base includes the Dafny front end, the Boogie VC generator and Z3. That is
  hundreds of thousands of lines, compared with Lean's kernel.
- **Proof stability:** SMT proofs are sensitive to solver version, random seed and trigger
  heuristics. A large machine-written proof corpus that has to re-check for years is the worst case
  for that brittleness.
- **R2:** deep-embedding another language's semantics and reasoning by induction over its ASTs and
  executions is where quantifier triggers struggle most. Dafny is good at proving Dafny, less so at
  modelling Apex.
- Escape hatches (`assume`, `{:axiom}`, `{:verify false}`, `{:extern}`) exist and would need the
  same policing as Lean's, but without a single "print the axioms this depends on" primitive.

### Why3

WhyML, with goals discharged by several back ends (Alt-Ergo, CVC5, Z3, and Rocq or Isabelle for
the hard ones).

Why not:
- **R1:** the trusted base includes Why3's VC generation, its goal transformations, and *every*
  prover a session uses.
- Proof sessions are brittle across prover versions. The hardest goals usually end up in an
  interactive prover anyway, which brings back the Rocq trade-offs plus an extra translation.
- **R5:** a small community and little LLM training data.

### Also looked at briefly

- **Isabelle/HOL:** an LCF-style small kernel with superb automation (Sledgehammer), so it would be
  a solid choice. Its code generator to SML or Scala is outside the kernel (R3), and it has less
  momentum in LLM proof tooling (R5).
- **K Framework:** designed for executable language semantics (R3 ✓), but its proof-checking story
  and trusted base are much weaker than an LCF-style kernel's (R1).
- **F\*:** SMT-backed, with the same trusted-base and stability concerns as Dafny.

## Why Lean 4 fits

- **R1:** a small kernel. Proofs are terms that the kernel re-checks, regardless of which tactic or
  model produced them. Independent kernels exist (`lean4lean`, `nanoda`) if we ever want a second
  opinion, and core Lean ships `Lean.Kernel.Environment.replay`, which our checker uses to re-check
  every project declaration.
- **R2:** dependent types, inductive families, structural and well-founded recursion. The
  semantics is ordinary Lean code.
- **R3:** the *same definitions* the kernel reasons about compile to native code, with no
  extraction step. Two caveats, both handled:
  1. `@[implemented_by]` and `@[extern]` let compiled code differ from the kernel's view. The
     checker rejects them on anything a spec depends on.
  2. The compiler itself isn't verified, so compiled execution (which difftest uses) relies on it.
     Mitigation (milestone 2): replay a sample of difftest vectors by kernel evaluation (`decide` or
     `rfl`), so the kernel and the compiled interpreter are shown to agree on them.
- **R4:** `simp`, `omega`, `decide`, `grind` and custom tactics, all producing kernel-checked terms.
- **R5:** a large and growing corpus of LLM-written Lean proofs and good agent tooling (LSP,
  `lake`, structured error messages).
- **R6:** the axiom check, statement/proof matcher and kernel replay are a few hundred lines of
  Lean meta-code (`lean/AxiomCheck.lean`) using `Lean.importModules` and the kernel API.
- **R7:** `elan` plus a pinned `lean-toolchain` gives a one-line, reproducible install.

## Consequences

- `native_decide` and `bv_decide` are banned: they make the kernel trust compiled code. In
  Lean 4.35 each `native_decide` adds its own auxiliary axiom (`…_native.native_decide.ax_…`);
  older versions went through `Lean.ofReduceBool`. The allowlist rejects both. So are `sorry`, `admit`, new `axiom`s outside
  `lean/SfVerify/Axioms.lean`, `implemented_by`/`extern` on spec-reachable definitions,
  and `debug.skipKernelTC`. ADR 0002 says how each ban is enforced.
- Lean releases monthly with breaking changes. We pin and upgrade deliberately, re-running the full
  check and difftest on each upgrade.
- The semantics must be **total**: fuel or well-founded recursion, no `partial def`. The kernel
  can't unfold a `partial` definition, so nothing could be proved about it.

## Revisit if

- A required proof pattern can't be expressed without an axiom we're unwilling to allowlist.
- Kernel checking of the generated proofs becomes a CI bottleneck that `decide`, `rfl` and
  structured proofs can't fix.
- An external kernel disagrees with Lean's on any declaration.

The rule from the kickoff applies: on a hard blocker we raise it in a new ADR. We don't switch tools
silently.
