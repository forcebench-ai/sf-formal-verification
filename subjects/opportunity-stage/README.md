# Subject: Opportunity stage handler

The first verification subject. It's deliberately small and written in-house so that it stays
under control. It's an ordinary SFDX project.

| File | Role | Verified? |
|---|---|---|
| `classes/OpportunityStage.cls` | `stageProbability(String)` maps a stage name to its default probability; `isClosed(String)` | **Yes**: P0, and used by P1–P5 |
| `classes/OpportunityStageHandler.cls` | `beforeSave(newList, oldMap, today)`: before-insert/update logic, no SOQL or DML | **Yes**: P1–P5 |
| `triggers/OpportunityStageTrigger.trigger` | Calls `beforeSave(Trigger.new, Trigger.oldMap, Date.today())` | No. Order of execution isn't modelled |
| `classes/OpportunityStageHarness.cls` | `check(newList, oldMap, today)` runs the handler and asserts P1–P5. The Apex fuzz entry point. | No. Evidence only |
| `classes/OpportunityStageTest.cls`, `OpportunityStageHandlerTest.cls` | Example tests, two trigger integration tests, and seeded random runs of the harness | No. Evidence only |

The verified classes must stay inside the [modelled Apex subset](../../docs/apex-subset.md). Any
change to them is a *subject patch*, which needs a [`BUGS.md`](../../BUGS.md) entry (README,
rule 3).

## Behaviour

`beforeSave(List<Opportunity> newList, Map<Id, Opportunity> oldMap, Date today)`:

- on insert (`oldMap == null`), or when `StageName` changed, set `Probability` from
  `stageProbability(StageName)`;
- in that same case, if the new stage is closed and `CloseDate` is null, set `CloseDate = today`;
- if `StageName == 'Closed Won'` and `Amount` is null or negative, call `addError` on the record.

The kickoff's signature had two parameters. `today` is the third, so the method has no hidden
global input. The trigger passes `Date.today()`.

Note that `==` and `!=` on Strings **ignore case** in Apex, so `'closed won'` is treated as
Closed Won and `'Prospecting'` → `'PROSPECTING'` is not a stage change. Whether the spec means
that is open question Q1 in [`docs/open-questions.md`](../../docs/open-questions.md).

## Deploy and test

Use an org dedicated to this project ([ADR 0003](../../docs/adr/0003-developer-edition-org.md)):

```sh
sf org login web --alias afv-dev            # once
make apex-deploy ORG=afv-dev                # from the repo root: deploy + RunLocalTests
```

The random tests use a fixed-seed generator, so a failure reproduces exactly. Each failing
assertion message names the property (`P2: Probability of record 3`) and the record index.
