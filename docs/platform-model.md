# Platform model

What the Lean model of the Salesforce platform captures, what it simplifies, and what it leaves
out. **An undocumented simplification is a bug.** If you find behaviour the model gets wrong or
doesn't mention, open an issue, and if possible add a difftest vector that shows it.

Status key: ✅ difftested against the reference org · 🚧 modelled, not yet difftested · ⏳ planned ·
❌ not modelled. The model is in `lean/SfVerify/Platform/` and `lean/SfVerify/Apex/`. **Nothing here
has been difftested against the reference org yet**, so every 🚧 row, including its stated
behaviour, is still subject to correction by [`tools/difftest`](../tools/difftest).

Reference org: the dedicated Developer Edition org `sfv-dev` (ADR 0003), API 68.0, instance USA840.
Its `OpportunityStage` rows (the standard sales process) match `stageProbability`'s table exactly
(checked 2026-10-23). Difftest records the API version with every run.

Behaviour marked *observed* below was seen in the reference org by a probe in
[`tools/difftest/probes/`](../tools/difftest/probes), not yet by difftest.

## sObject records

| Aspect | Model | Status |
|---|---|---|
| Representation | A record is an association list from field name to value, held on a heap. Variables, lists and maps hold *references*, so a write through one alias is visible through every other. | 🚧 |
| Field names | Apex field names are case-insensitive (`opp.stagename` is `opp.StageName`). The exporter normalises to the canonical API name. | ⏳ |
| Modelled fields | `Opportunity`'s `Id`, `Name`, `StageName`, `Description`, `Amount`, `Probability` and `CloseDate`. Reading or writing any other field is `unsupported`, never null. | 🚧 |
| Unset fields | Reading a field that was never set gives `null`, as for an in-memory sObject. | 🚧 |
| Field types | Each modelled field has a type, and a write that doesn't fit is `unsupported`. The model assumes the program compiled in the org, so it doesn't type-check further. `Probability` is Percent(3,0), `Amount` Currency(16,2), `CloseDate` Date, `StageName` Picklist. | 🚧 |
| Precision and scale on assignment | **Simplification:** values assigned to `Probability`/`Amount` aren't rounded to the field's scale in memory. The platform rounds or rejects them at save time, which happens after the before trigger. | 🚧 |
| Picklist values | **Simplification:** `StageName` is any `String` or null. Picklist validation happens at save time, outside the handler. The statements quantify over *every* string, which is stronger than quantifying over valid picklist values. | 🚧 |
| Derived fields | `IsClosed`, `IsWon` and `ForecastCategory` are **not modelled**. The subject must not read them. (In a before trigger they aren't recomputed for the new stage yet.) | ❌ |

## Values

| Aspect | Model | Status |
|---|---|---|
| `String ==` / `!=` | **Ignores case**, as Apex does. `'closed won' == 'Closed Won'` is `true`. Null equals only null. **Simplification:** only ASCII letters and four non-ASCII characters that fold onto ASCII letters (`ſ`, `K`, `ı`, `İ`) are folded; every other character compares exactly. Vectors `str.*` test how this compares with the org. | 🚧 |
| `Map` keys | Exact match with no case folding. Null is an ordinary key, absent unless inserted. | 🚧 |
| `==` on two non-null sObjects, lists or maps | `unsupported`. Apex compares them by content; the model doesn't. | ❌ |
| `Decimal` | Arbitrary-precision value with a scale. Equality and ordering compare numeric value, so `1.0 == 1.00` (to be confirmed by difftest). No arithmetic in the subset yet, so rounding modes aren't modelled. | 🚧 |
| `Integer` → `Decimal` | Implicit widening, exact. | 🚧 |
| `Id` | An opaque string compared exactly. **Simplification:** Ids are assumed to be in their canonical 18-character form; the platform also accepts 15-character Ids. | 🚧 |
| `Date` | Year, month and day. Only equality and null checks are needed. No time zones; `Date.today()` isn't in the subset and is injected instead. | 🚧 |
| Null in comparisons | **Provisional:** `null < x` and `x < null` throw `NullPointerException`, after both operands have been evaluated. Salesforce's documentation says these are false, so the org must settle it (vectors `cmp.*`, `order.cmp_*`). | 🚧 |
| Null in Boolean operators | **Provisional:** `null` as an evaluated operand of `&&`, `\|\|` or `!`, or as an `if` condition, throws `NullPointerException`. A short-circuited operand isn't evaluated. Vectors `bool.*`, `if.*`. | 🚧 |

## Errors and exceptions

| Aspect | Model | Status |
|---|---|---|
| `addError(String)` | A record holds at most one record-level error. `record.addError(m)` replaces any earlier one, and execution continues: `addError` doesn't throw. A null message is `unsupported`. Field-level `record.Field.addError(m)` isn't in the subset; the observations below show the platform keeps one error per target, so adding it would make the error a map from target to message. *Observed* on an in-memory record ([`probes/adderror.apex`](../tools/difftest/probes/adderror.apex)): two calls leave one error and the last message wins, whether the messages are equal or not. Errors on different targets are kept separately, and `getErrors()` isn't in call order, so the model has no order. **To confirm:** the same behaviour inside a trigger during DML (affects P5; see `open-questions.md` Q4). | 🚧 |
| Uncaught exceptions | The outcome carries the exception type: `NullPointerException`, `ListException`, … The message is not modelled. | 🚧 |
| Termination | Evaluation uses fuel. Running out of fuel is a distinct outcome, never success. Apex's call-stack limit isn't modelled, so a very deep finite call chain could succeed in the model and throw in the org. | 🚧 |
| Unmodelled construct | A distinct `unsupported` outcome, never success. | 🚧 |

## Trigger context

The handler receives the trigger context as plain parameters. The model doesn't simulate the
trigger framework. Instead, the statements assume (as hypotheses) what the platform guarantees:

| Assumption | Status |
|---|---|
| Before insert: `oldMap` is `null`. | 🚧 |
| Before update: `oldMap` has exactly the `Id`s of `newList`, each mapping to a separate record with the same `Id`. | 🚧 |
| The records in `newList` are distinct objects (no aliasing) and distinct from the `oldMap` values. | 🚧 |
| A chunk has at most 200 records. | 🚧 |

## Limits

| Aspect | Model | Status |
|---|---|---|
| SOQL query counter, DML statement counter | Modelled as counters in the state. The subset has no SOQL or DML, so for now they stay at 0 by construction. That part of P1 is a syntactic fact until SOQL/DML are modelled. | 🚧 |
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
