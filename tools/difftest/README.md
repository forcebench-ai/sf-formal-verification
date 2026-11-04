# difftest: the semantics against a real org

The Lean semantics is executable. Difftest runs the same inputs through the **Lean interpreter**
and through **anonymous Apex in the reference org** (ADR 0003), then diffs the results. Any
mismatch is a semantics bug and blocks merging (README, rule 4).

**Status:** level 1 is implemented, with 261 vectors in
[`lean/Difftest/Catalog.lean`](../../lean/Difftest/Catalog.lean). **They haven't been run in the
reference org yet.** Level 2 needs the exporter (milestone 3).

```sh
make difftest-kernel    # no org: generate the vectors, and check the kernel agrees with compiled code
make difftest ORG=sfv-dev    # runs anonymous Apex in the reference org and compares
```

## Two levels

1. **Per construct.** Every rule in the semantics gets small generated Apex programs, inside the
   subset, that exercise it, including its null and exception cases: `null < 1`, `if (null)`,
   `'a' == 'A'`, `1.0 == 1.00`, iterating a null list, `Map.get` on a missing key, `addError`
   twice, and so on. A rule without difftest coverage doesn't count as modelled
   (`docs/apex-subset.md` stays ⏳ for it).
2. **Per subject.** Random inputs for the subject's entry points (for `beforeSave`: record lists,
   nulls, case variants, consistent `oldMap`s) run through the Lean interpreter on the *generated*
   `lean/Subjects` term and through the deployed classes in the org.

## Comparison

Both sides serialise the outcome to the same canonical JSON. The Apex side prints it with a marker
line in the debug log. Vectors are Lean terms: the org runs the text the trusted pretty-printer
(`SfVerify.Apex.Syntax.Pretty`) produces for them, flattened into methods because anonymous Apex
has no static methods. The outcome contains:

- normal / exception type / unsupported (unsupported must never appear on the Lean side for a
  vector the org ran);
- every record's populated fields, with Decimals compared by value and scale recorded separately;
- every record's record-level error. More than one fails the comparison, because the model holds at
  most one ([`probes/adderror.apex`](probes/adderror.apex)).

SOQL and DML counters aren't compared yet: the subset can't change them, and the emitted script runs
one SOQL query of its own to record the org's type and instance.

## Keeping the interpreter and the kernel in step

Difftest runs *compiled* Lean code, but the proofs are about what the *kernel* sees. The axiom
checker already forbids `implemented_by`/`extern` on spec-reachable definitions. In addition, *every*
vector is replayed as `example : vectorResult i = <compiled result> := by decide +kernel`, so the
kernel and the compiled interpreter are shown to agree on them (ADR 0001). CI runs this
(`make difftest-kernel`).

## Records

Each run records the org's API version and instance in `run-meta.json`. Every mismatch found is kept
as a regression vector, even after it is fixed.

## Other runtimes

[`aer`](https://aertest.com) runs anonymous Apex locally, so it's useful for catching emitter bugs,
such as a script that won't compile, without using the org. It isn't the reference: only a run in the
reference org can confirm or correct the model.
