# SF Formal Verification

[![CI](https://github.com/forcebench-ai/sf-formal-verification/actions/workflows/ci.yml/badge.svg)](https://github.com/forcebench-ai/sf-formal-verification/actions/workflows/ci.yml)

Machine-checked proofs about Salesforce automation, starting with Apex code that operates on core
CRM objects.

Apex runs only on Salesforce servers and compiles to proprietary bytecode, so there is no binary to
model. Instead this project works at the **source level**: a formal semantics for a subset of Apex,
plus a model of the platform features the code touches, both written in [Lean 4](https://lean-lang.org).
Apex classes are parsed by an open-source Apex grammar and exported to Lean terms. Properties of
those classes are stated as Lean theorems and proved, and Lean's kernel checks every proof.

Apex is the first language, not the only one. The platform model (records, errors, limits, and later
the database and order of execution) is meant to be shared with future front ends for other
Salesforce automation, such as Flows, validation-rule formulas and order-of-execution interactions.

The semantics is *executable*, so it doubles as a reference interpreter. A differential tester runs
random inputs through the Lean interpreter **and** through real Apex in a Salesforce org and diffs
the results, which keeps the model honest about how the platform actually behaves.

> **Status: milestone 1 (scaffold) in progress. Nothing about Apex is proven yet.**
> The [status table](#status) is the single source of truth for what has been proven.
> If a claim isn't in that table, it hasn't been proven.

---

## Contents

- [Why this exists](#why-this-exists)
- [What "proven" means here: the trusted base](#what-proven-means-here-the-trusted-base)
- [Status](#status)
- [First subject: the Opportunity stage handler](#first-subject-the-opportunity-stage-handler)
- [Repository layout](#repository-layout)
- [Getting started](#getting-started)
- [How the project stays honest](#how-the-project-stays-honest)
- [Known gaps and limitations](#known-gaps-and-limitations)
- [Roadmap](#roadmap)
- [Contributing (humans and AI agents)](#contributing-humans-and-ai-agents)
- [Background](#background)

---

## Why this exists

Salesforce teams lean heavily on example-based Apex tests. Those tests show that code works for the
handful of inputs someone thought of. Trigger code then runs on every record any user, integration
or data load ever saves, in batches of up to 200, with any combination of null fields.

This project adapts an approach from Anthropic's research on LLM-assisted formal verification at
scale:

1. **Turn tests into specs.** A developer's test already encodes what "correct" means. Generalise
   "passes for these inputs" to "passes for *every* input", then prove it.
2. **Small trusted base, large untrusted proofs.** Proofs can be huge and machine-written, because a
   proof checker verifies them. Humans only need to trust the model of the platform, the exact
   theorem statements, and the checker.
3. **Attempting the proof finds bugs.** A proof obligation that cannot be discharged points at a
   concrete input that breaks the property. Those inputs are recorded in [`BUGS.md`](BUGS.md).
4. **Broad-spectrum properties first.** "Never throws, never breaches a limit" applies to almost
   all code and pays off before any functional spec exists. Functional properties come next:
   exact outputs, frame conditions, idempotence.
5. **Reuse proofs.** Lemmas about lists, maps, nulls and field updates live in a shared library, so
   the next subject (Account, Contact, Lead, Case) starts from more than zero.
6. **Guard against spec gaming.** Any theorem can be made provable by weakening the spec or by
   rewriting the code into something trivial. The rules below make that visible and reviewable.

## What "proven" means here: the trusted base

A green checkmark in this repo means: *Lean's kernel accepted a proof of the exact statement in
`lean/Spec/`, the proof uses no axioms beyond the allowlist, and every declaration it depends on
was re-checked by the kernel.*

That claim is only as good as the things you have to take on trust. The full list, with the
reasoning, is in [`docs/trusted-base.md`](docs/trusted-base.md). In short:

| You must trust | Where it lives | How it's kept honest |
|---|---|---|
| The **theorem statements** say what we mean | `lean/Spec/` | Human-owned, frozen, changes need CODEOWNERS review and a `spec-change` PR |
| The **Apex semantics and platform model** match real Salesforce | `lean/ApexVerify/{Syntax,Semantics,Platform}` | Differential testing against a real org; every simplification named in [`docs/platform-model.md`](docs/platform-model.md) |
| The **exporter** turns the `.cls` file into the right Lean term | `tools/apex-to-lean/` | Kept tiny; round-trip tests; CI regenerates `lean/Subjects/` and diffs it |
| The **checker** finds every statement and rejects escape hatches | `lean/AxiomCheck.lean`, `tools/lint/`, `tools/kernels/` | Self-tests with deliberately bad proofs that must be rejected |
| **Lean's kernel** and toolchain | pinned in `lean/lean-toolchain` | Every project declaration is re-checked in CI three ways: our own kernel replay, upstream `leanchecker`, and [nanoda](https://github.com/ammkrn/nanoda_lib), an independent type checker written in Rust |

You do **not** need to trust the proofs in `lean/Proofs/` or the reusable lemmas in
`lean/ApexVerify/Lib/`. They may be large and machine-written, and the kernel checks them.

## Status

| Milestone | What it delivers | Status |
|---|---|---|
| 1. Scaffold | Layout, ADRs, Lean project + CI, axiom checker, subject deploys and its Apex tests pass | 🚧 Done: layout, ADRs, Lean build, axiom checker + self-tests, lint, independent kernels, CI, subject code. Waiting on: first deploy to the reference org |
| 2. Subset + semantics | Apex subset AST, executable semantics, difftest coverage of every construct | ⏳ |
| 3. P0 | Exporter for `OpportunityStage.cls`; proof of P0 | ⏳ |
| 4. P1–P5 | Proofs of the handler properties; bugs found logged in `BUGS.md` | ⏳ |
| 5. Write-up | Final statement of what is proven, assumptions, gaps, one-command re-check | ⏳ |

**Proven theorems:** none yet. `lake exe axiomcheck` prints the authoritative list.

## First subject: the Opportunity stage handler

The first subject is deliberately small, and we wrote it ourselves so it stays under control. It
lives in [`subjects/opportunity-stage/`](subjects/opportunity-stage) as an ordinary SFDX project.

- **`OpportunityStage.stageProbability(String stageName) : Decimal`** maps a stage name to the
  default probability of the standard Salesforce sales process. A null or unknown stage returns
  null.
- **`OpportunityStageHandler.beforeSave(List<Opportunity> newList, Map<Id, Opportunity> oldMap, Date today)`**
  is before-insert/before-update logic with **no SOQL and no DML**:
  - on insert, or when `StageName` changed, it sets `Probability` from `stageProbability`;
  - when `StageName = 'Closed Won'` and `Amount` is null or negative, it calls `addError`;
  - when the stage moves to a closed stage and `CloseDate` is null, it sets `CloseDate = today`.
    The date is injected as a parameter, so the method has no hidden global input.
- **`OpportunityStageHarness.check(...)`** runs the handler on arbitrary inputs and asserts the
  properties below. It is the Apex counterpart of a fuzz entry point: any input that makes it throw
  is a bug.

### The properties (the spec)

These are quantified over **every** input list of up to 200 records (one trigger chunk), every
combination of field values including nulls, and every `oldMap` consistent with `newList`. The
English below is a summary. The Lean statements in `lean/Spec/` are authoritative once they are
written and frozen.

| | Property |
|---|---|
| **P0** | `stageProbability` is total and matches the stage table, with values in [0, 100] or null. |
| **P1** | *No-crash:* `beforeSave` terminates, throws no uncaught exception, and uses 0 SOQL and 0 DML. |
| **P2** | *Probability:* every inserted or stage-changed record ends with `Probability = stageProbability(StageName)`; every other record's `Probability` is unchanged. |
| **P3** | *Exact errors:* a record receives `addError` **if and only if** it is Closed Won with a null or negative `Amount`. The "only if" half rules out the trivial fix of erroring everything. |
| **P4** | *Frame:* no field other than `Probability` and `CloseDate` changes; list length and order are preserved. |
| **P5** | *Idempotence:* running `beforeSave` twice gives the same records and errors as running it once. |

Open questions that must be settled before these are frozen (string case-sensitivity, what "moves
to a closed stage" means, whether CloseDate needs its own property, and error multiplicity) are
tracked in [`docs/open-questions.md`](docs/open-questions.md).

## Repository layout

```
sf-formal-verification/
  README.md                  this file
  BUGS.md                    every bug found via a failed proof, with a counterexample
  Makefile                   one-command checks (make check)
  docs/
    adr/                     architecture decision records
    apex-subset.md           exactly which Apex constructs are modelled
    platform-model.md        sObjects, nulls, addError, limits, and what is NOT modelled
    trusted-base.md          everything a reader must trust, and why
    open-questions.md        spec ambiguities awaiting a decision
  lean/                      Lean 4 project (lake)
    ApexVerify/
      Syntax/                AST for the Apex subset                         [trusted]
      Semantics/             executable semantics; Axioms.lean = allowlist   [trusted]
      Platform/              sObject records, field access, addError, limits [trusted]
      Lib/                   reusable lemmas: lists, maps, nulls, loops      [untrusted]
    Spec/                    theorem STATEMENTS only: human-reviewed, frozen [trusted]
    Proofs/                  proofs: may be large and machine-written        [untrusted]
    Subjects/                Lean ASTs generated from subject .cls files     [generated]
    AxiomCheck.lean          statement/proof matcher, axiom allowlist, kernel replay [trusted]
    test/axiomcheck/         fixtures the checker must accept or reject
  tools/
    apex-to-lean/            Apex parser -> Lean AST exporter + round-trip tests [trusted]
    difftest/                random inputs -> Lean interpreter vs real org -> diff
    lint/                    escape-hatch lint (sorry, native_decide, axiom, ...)
    kernels/                 re-check with nanoda, an independent kernel (pinned)
  subjects/
    opportunity-stage/       SFDX project: subject classes, trigger, tests, harness
  .github/
    CODEOWNERS               trusted-base paths need maintainer review
    workflows/ci.yml         build, axiom check, lint, checker self-tests, Apex tests
```

## Getting started

### Prerequisites

| Tool | Why | Install |
|---|---|---|
| [elan](https://github.com/leanprover/elan) | Lean toolchain manager; picks up the version pinned in `lean/lean-toolchain` | `brew install elan-init` or the elan install script |
| Python 3 | escape-hatch lint | preinstalled on macOS and Ubuntu |
| [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli) (`sf`) | deploy the subject, run Apex tests, difftest | `npm install --global @salesforce/cli` |
| Node.js 20+ | exporter and difftest (milestones 2–3) | `brew install node` |

### Check everything

```sh
make check        # lake build + axiom check + checker self-tests + escape-hatch lint
```

Or run the pieces one at a time:

```sh
cd lean
lake build                  # build semantics, specs, proofs
lake exe axiomcheck         # match every Spec statement to its proof, enforce the axiom allowlist, kernel-replay
./test/axiomcheck/run.sh    # the checker must reject sorry, native_decide, new axioms, wrong statements, ...
cd ..
python3 tools/lint/escape_hatches.py   # no sorry/admit/native_decide/axiom/implemented_by/... in trusted or proof code
make leanchecker                       # second opinion: upstream kernel replay
tools/kernels/nanoda.sh                # third opinion: independent kernel (needs cargo)
```

### Deploy the subject and run its Apex tests

Use a Developer Edition org (or a scratch org) **dedicated to this project**. The subject deploys an
Opportunity trigger, so don't point it at an org whose data you care about.

```sh
sf org login web --alias afv-dev          # once
make apex-deploy ORG=afv-dev              # deploy + run the subject's Apex tests
```

## How the project stays honest

1. **Spec files are frozen.** `lean/Spec/` holds human-owned statements of intent. Nobody edits a
   spec to make a proof go through. A spec believed to be wrong gets a PR tagged `spec-change`
   explaining why, and CODEOWNERS routes it to the maintainer.
2. **No escape hatches.** `sorry`, `admit`, `native_decide` and new `axiom`s are rejected unless
   they appear on the allowlist in `lean/ApexVerify/Semantics/Axioms.lean`. The checker enforces
   this three ways:
   - **Axiom allowlist.** `lake exe axiomcheck` requires a `theorem` in `Proofs/` for every
     statement in `Spec/`, whose type is *exactly* that statement, and collects every axiom the
     proof transitively depends on. Anything outside the allowlist fails CI. This is the
     `#print axioms` check, done programmatically.
   - **Kernel replay.** Every declaration from this project is re-checked by the Lean kernel, so a
     proof slipped in with kernel checking disabled is still caught.
   - **Execution check.** Definitions the specs depend on may not use `implemented_by`/`extern`,
     because those make compiled code (what difftest runs) differ from what the kernel reasons
     about.
   - **Lint.** A source lint catches escape hatches even in code no theorem depends on yet.
3. **Subject patches are a cost, not a shortcut.** When a proof fails because the Apex is genuinely
   buggy, the Apex gets a *minimal* fix. The failed property, a concrete counterexample, the patch
   and (when possible) confirmation from a real org all go into [`BUGS.md`](BUGS.md). Rewriting the
   subject into something that trivially satisfies the spec is not allowed.
4. **Semantics is tested against reality.** Every semantic rule is exercised by `tools/difftest`,
   which compares the Lean interpreter with anonymous Apex run in a real org. Any mismatch is a
   semantics bug and blocks merging.
5. **Every gap is named.** Each simplification (Decimal scale, case-insensitive String `==`,
   picklists, order of execution, …) is written down in
   [`docs/platform-model.md`](docs/platform-model.md). An undocumented simplification is a bug.
6. **Lemmas are reusable.** Facts about list iteration, null handling, map lookup and field update
   go into `lean/ApexVerify/Lib/` in general form, so the next subject can reuse them.

## Known gaps and limitations

Out of scope for now. Each will become its own milestone with its own platform-model section:
SOQL and DML, sharing and FLS, async Apex, callouts, multiple triggers and the full order of
execution, flows, validation rules, managed packages, and governor limits beyond the SOQL/DML
counters.

Even inside that scope, a proof here is a statement about **the model**. A theorem about
`beforeSave` says nothing about what the platform does before or after the trigger runs: default
probability assignment, validation rules, workflow, other triggers. The full list of what the model
does and doesn't capture is in [`docs/platform-model.md`](docs/platform-model.md).

## Roadmap

After the Opportunity stage handler (not started yet):

1. Account hierarchy rollups
2. Contact/Account relationship invariants
3. Lead conversion field mapping
4. The first milestone that models SOQL/DML against an in-memory database

## Contributing (humans and AI agents)

Much of the proof work here is expected to be written by AI agents. The rules above apply to
everyone, and CI enforces the mechanical parts. For anyone, human or agent, working on a proof:

- Treat `lean/Spec/`, `lean/ApexVerify/{Syntax,Semantics,Platform}`, the checker, the lint and the
  exporter as **read-only** unless the change is the point of the PR and is labelled as such.
- When a proof gets stuck, first check whether the failure is a real counterexample. Run it through
  the executable semantics and, if possible, the org, before assuming the proof just needs more
  effort.
- Commit in small steps. Keep `lean/Spec/` changes in their own commits.

Architecture decisions are recorded in [`docs/adr/`](docs/adr).

## Background

- Anthropic, *LLMs are making formal software verification feasible at a much larger scale*
  (anthropic.com/research/formal-verification, Oct 2026), the approach this project adapts.
- [Lean 4](https://lean-lang.org) and its [theorem proving guide](https://lean-lang.org/theorem_proving_in_lean4/).
- [`@apexdevtools/apex-parser`](https://github.com/apex-dev-tools/apex-parser), the ANTLR-based
  Apex grammar the exporter builds on.
