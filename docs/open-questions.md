# Open questions

Ambiguities in the intended spec that must be decided **before** the corresponding statements in
`lean/Spec/` are frozen. Each one changes what is provable, so none of them may be settled quietly
inside a proof. Once a question is decided, record the decision and the date, and link the commit
that wrote it into `Spec/`.

## Q1. Case sensitivity of stage names (affects P0, P2, P3)

Apex `String ==` ignores case. `'closed won' == 'Closed Won'` is `true`, while `Map<String,…>`
keys and `String.equals` are case-sensitive.

- Does "`StageName = 'Closed Won'`" in P3 mean an exact match, or a match ignoring case?
- Is `stageProbability('prospecting')` 10, or null because the stage is "unknown"?
- Is `'Prospecting'` → `'prospecting'` a "stage change" for P2?

Whatever the subject does today, the statement has to say which one we *mean*. If they disagree,
that is a finding.

**Proposed default:** use Apex semantics (ignore case) throughout, since that is what developers
reading `==` expect. Spell the choice out in the statement so it is visible.

## Q2. What counts as "moves to a closed stage" (affects the CloseDate rule)

- A record **inserted** already closed: does it get `CloseDate = today` when `CloseDate` is null?
- **Closed Won → Closed Lost:** the stage changed and the new stage is closed. Does that count?

**Proposed default:** yes to both. "Moves to a closed stage" = (inserted, or `StageName` changed)
and the new stage is closed.

## Q3. CloseDate has no property of its own

P4 *allows* `CloseDate` to change, but no property says *when* it must change or what to. A handler
that never touched `CloseDate` would satisfy P0–P5.

**Proposed:** add **P6 CloseDate**. After the call, every record that moved to a closed stage with
a null `CloseDate` has `CloseDate = today`, and every other record's `CloseDate` is unchanged.

## Q4. Error multiplicity in P5 (idempotence)

If `beforeSave` runs twice, `addError` runs twice on the same record. Whether the platform then
reports one error or two will be settled by difftest.

- If errors accumulate, does "the same errors" in P5 compare **lists** (then P5 fails for the
  current handler) or **sets of messages**?

**Proposed default:** decide after difftest shows what the platform does. If it accumulates, prefer
the list comparison and treat the failure as a real finding. Callers that re-run handlers (for
example recursion guards) do observe duplicate errors.

**Evidence (2026-10-23):** errors don't accumulate on an in-memory record. A record holds at most
one record-level error, and a second `addError` replaces the first, even when the message differs
([`tools/difftest/probes/adderror.apex`](../tools/difftest/probes/adderror.apex), API 68.0). The
harness's P5 check, which compares error lists after one run and after two, passes in the org
(21/21 tests). So P5 as written holds for the platform, with no list-versus-set choice needed. The
platform model follows the observation (`docs/platform-model.md`, Errors). It still has to be
confirmed inside a trigger during DML. **Proposed resolution:** keep P5 comparing errors exactly,
and model errors as last-write-wins per target.

## Q5. The 200-record bound

The kickoff quantifies over lists of *up to 200* records. The semantics has no CPU limit, so the
proofs will probably hold for lists of any length.

**Proposed default:** keep `newList.length ≤ 200` as a hypothesis to match the stated intent, and
note in the README that the proofs don't use it.
