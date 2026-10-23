# Platform model

What the Lean model of the Salesforce platform captures, what it simplifies, and what it leaves
out. **An undocumented simplification is a bug.** If you find behaviour the model gets wrong or
doesn't mention, open an issue, and if possible add a difftest vector that shows it.

Status key: ✅ difftested against the reference org · 🚧 modelled, not yet difftested · ⏳ planned ·
❌ not modelled. Milestone 1 contains no model yet, so everything below is a design commitment for
milestone 2, to be confirmed or corrected by difftest.

Reference org: the dedicated Developer Edition org `sfv-dev` (ADR 0003), API 68.0, instance USA840.
Its `OpportunityStage` rows (the standard sales process) match `stageProbability`'s table exactly
(checked 2026-10-23). Difftest records the API version with every run.

Behaviour marked *observed* below was seen in the reference org by a probe in
[`tools/difftest/probes/`](../tools/difftest/probes), not yet by difftest.

## sObject records

| Aspect | Model | Status |
|---|---|---|
| Representation | A record is a finite map from field name to value, held on a heap. Variables, lists and maps hold *references*, so a write through one alias is visible through every other. | ⏳ |
| Field names | Apex field names are case-insensitive (`opp.stagename` is `opp.StageName`). The exporter normalises to the canonical API name. | ⏳ |
| Unset fields | Reading a field that was never set gives `null`, as for an in-memory sObject. | ⏳ |
| Field types | Fields are dynamically typed values in the model. Static typing comes from the Apex declaration. `Probability` is Percent(3,0), `Amount` Currency(16,2), `CloseDate` Date, `StageName` Picklist. | ⏳ |
| Precision and scale on assignment | **Simplification:** values assigned to `Probability`/`Amount` aren't rounded to the field's scale in memory. The platform rounds or rejects them at save time, which happens after the before trigger. | ⏳ |
| Picklist values | **Simplification:** `StageName` is any `String` or null. Picklist validation happens at save time, outside the handler. The statements quantify over *every* string, which is stronger than quantifying over valid picklist values. | ⏳ |
| Derived fields | `IsClosed`, `IsWon` and `ForecastCategory` are **not modelled**. The subject must not read them. (In a before trigger they aren't recomputed for the new stage yet.) | ❌ |

## Values

| Aspect | Model | Status |
|---|---|---|
| `String ==` / `!=` | **Ignores case**, as Apex does. `'closed won' == 'Closed Won'` is `true`. Null equals only null. | ⏳ |
| `Decimal` | Arbitrary-precision value with a scale. Equality and ordering compare numeric value, so `1.0 == 1.00` (to be confirmed by difftest). No arithmetic in the subset yet, so rounding modes aren't modelled. | ⏳ |
| `Integer` → `Decimal` | Implicit widening, exact. | ⏳ |
| `Date` | Year, month and day. Only equality and null checks are needed. No time zones; `Date.today()` isn't in the subset and is injected instead. | ⏳ |
| Null in comparisons | `null < x` and `x < null` throw `NullPointerException` (to be confirmed by difftest). | ⏳ |
| Null in Boolean operators | Exact behaviour of `null && x`, `!null` and `if (null)` to be fixed by difftest. Expected: `NullPointerException`. | ⏳ |

## Errors and exceptions

| Aspect | Model | Status |
|---|---|---|
| `addError(String)` | Errors are a finite map from **target** (the record, or one field) to a message. `record.addError(m)` sets the record's entry to `m`, replacing any earlier one; `record.Field.addError(m)` does the same for that field. Execution continues: `addError` doesn't throw. *Observed* on an in-memory record ([`probes/adderror.apex`](../tools/difftest/probes/adderror.apex)): two calls leave one error and the last message wins, whether the messages are equal or not. Errors on different targets are kept separately, and `getErrors()` isn't in call order, so the model has no order. **To confirm:** the same behaviour inside a trigger during DML (affects P5; see `open-questions.md` Q4). | ⏳ |
| Uncaught exceptions | The outcome carries the exception type: `NullPointerException`, `ListException`, … The message is not modelled. | ⏳ |
| Termination | Evaluation uses fuel. Running out of fuel is a distinct outcome, never success. | ⏳ |
| Unmodelled construct | A distinct `unsupported` outcome, never success. | ⏳ |

## Trigger context

The handler receives the trigger context as plain parameters. The model doesn't simulate the
trigger framework. Instead, the statements assume (as hypotheses) what the platform guarantees:

| Assumption | Status |
|---|---|
| Before insert: `oldMap` is `null`. | ⏳ |
| Before update: `oldMap` has exactly the `Id`s of `newList`, each mapping to a separate record with the same `Id`. | ⏳ |
| The records in `newList` are distinct objects (no aliasing) and distinct from the `oldMap` values. | ⏳ |
| A chunk has at most 200 records. | ⏳ |

## Limits

| Aspect | Model | Status |
|---|---|---|
| SOQL query counter, DML statement counter | Modelled as counters in the state. The subset has no SOQL or DML, so for now they stay at 0 by construction. That part of P1 is a syntactic fact until SOQL/DML are modelled. | ⏳ |
| CPU time, heap size, other governor limits | ❌ Not modelled. A proof of "no exception" does **not** rule out `LimitException` from CPU or heap. | ❌ |

## Not modelled (out of scope for now)

Each of these becomes its own milestone with its own section here:

- **Order of execution.** System validation, before-save flows, other triggers, duplicate rules,
  after triggers, assignment rules, workflow, processes, roll-ups, and the platform's own
  default-probability assignment when `StageName` changes. A proof about `beforeSave` says nothing
  about what happens to the record before or after it.
- SOQL, SOSL, DML, and the database.
- Sharing, CRUD and FLS (`with sharing` is accepted syntactically and has no effect in the model).
- Validation rules, flows, managed packages.
- Async Apex, callouts, platform events.
- API-version-dependent behaviour beyond the recorded reference version.
