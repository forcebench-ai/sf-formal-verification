# difftest: the semantics against a real org

The Lean semantics is executable. Difftest runs the same inputs through the **Lean interpreter**
and through **anonymous Apex in the reference org** (ADR 0003), then diffs the results. Any
mismatch is a semantics bug and blocks merging (README, rule 4). **Status:** design only.
Implementation is milestone 2.

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
line in the debug log. The outcome contains:

- normal / exception type / unsupported (unsupported must never appear on the Lean side for a
  vector the org ran);
- every record's populated fields, with Decimals compared by value and scale recorded separately;
- every record's errors, as a map from target (the record, or a field) to message. `getErrors()`
  isn't in call order, so order isn't compared ([`probes/adderror.apex`](probes/adderror.apex));
- SOQL and DML counters.

## Keeping the interpreter and the kernel in step

Difftest runs *compiled* Lean code, but the proofs are about what the *kernel* sees. The axiom
checker already forbids `implemented_by`/`extern` on spec-reachable definitions. In addition, a
sample of vectors from every run is replayed as `example : interp input = expected := by decide`,
so the kernel and the compiled interpreter are shown to agree on them (ADR 0001).

## Records

Each run records the org's API version and instance. Every mismatch found is kept as a regression
vector, even after it is fixed.
