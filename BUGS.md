# Bugs found

Every bug that an attempted proof (or difftest) exposed in a subject or in the model goes here.
Subject patches are a cost, not a shortcut (README, rule 3). An entry needs everything below. "The
proof didn't go through, so we changed the code" is not an entry.

## Entry template

```
### B<n>: <one-line summary>

- **Subject / file:** subjects/<subject>/force-app/.../<File>.cls
- **Property that failed:** P<k> (link to the statement in lean/Spec/)
- **Found by:** proof attempt | difftest | Apex harness
- **Counterexample input:** the smallest concrete input, written so it can be pasted into anonymous Apex
- **Observed vs expected:** what happened, and what the property requires
- **Confirmed in a real org:** yes (date, org API version, anonymous Apex output) | not yet
- **Patch:** commit link and a minimal diff
- **Why the patch is minimal:** one or two sentences
```

## Model bugs

Mismatches between the Lean semantics and real Apex found by difftest. These are fixes to the
trusted base, so they also go in `docs/trusted-base.md` under "Changes to the trusted base".

## Entries

None yet.
