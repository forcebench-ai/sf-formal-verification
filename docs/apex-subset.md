# The Apex subset

This file lists **exactly** which Apex constructs the Lean semantics models. A subject may only use
constructs listed here as *modelled*. If the exporter meets anything else, it fails loudly rather
than approximating.

In the semantics, any construct that is not modelled evaluates to an explicit `unsupported`
outcome. Every statement requires the outcome not to be `unsupported`, so unmodelled behaviour can
never be mistaken for success.

Status key: ✅ modelled and difftested · 🚧 modelled, difftest pending · ⏳ planned for milestone 2 ·
❌ not in the subset

## Values and types

| Construct | Status | Notes |
|---|---|---|
| `null` | ⏳ | Every reference type is nullable. |
| `Boolean` literals | ⏳ | Apex `Boolean` is three-valued: `true`, `false`, `null`. |
| `Integer` literals | ⏳ | Needed for literals like `10` and widening to `Decimal`. 32-bit two's complement. |
| `Decimal` literals and values | ⏳ | Arbitrary precision with a scale. See platform model on equality and scale. |
| `String` literals and values | ⏳ | |
| `Date` values | ⏳ | Calendar date, no time zone. Only passed in and compared with null; no `Date` methods. |
| `Id` | ⏳ | Opaque, compared by value. Used as `Map` keys. |
| `List<T>` (read, iterate) | ⏳ | Reference type. |
| `Map<K,V>.get` | ⏳ | Reference type. Only `get` is modelled. |
| sObject (`Opportunity`) | ⏳ | Reference type, a record of field values. See the platform model. |

## Expressions

| Construct | Status | Notes |
|---|---|---|
| Local variable read | ⏳ | |
| sObject field read `r.F` | ⏳ | Null `r` → `NullPointerException`. |
| `==`, `!=` | ⏳ | **String comparison ignores case.** Decimal compares by value. |
| `<`, `<=`, `>`, `>=` | ⏳ | A null operand throws `NullPointerException` (to be confirmed by difftest). |
| `&&`, `\|\|` (short-circuit), `!` | ⏳ | Null operand behaviour to be confirmed by difftest. |
| Static method call `C.m(args)` | ⏳ | Only to classes in the same subject. |
| `Map.get(k)` | ⏳ | Missing key → `null`. Null map → `NullPointerException`. |
| Implicit `Integer` → `Decimal` widening | ⏳ | At assignment, return and comparison. |

## Statements

| Construct | Status | Notes |
|---|---|---|
| Local declaration `T x = e;` / `T x;` | ⏳ | |
| Assignment to a local, `x = e;` | ⏳ | |
| Field assignment, `r.F = e;` | ⏳ | Mutates the shared record (reference semantics). |
| `if (c) s` / `if (c) s else s` | ⏳ | Null condition behaviour to be confirmed by difftest. |
| `for (T x : list) s` | ⏳ | Iterating over a null list throws `NullPointerException`. |
| Block `{ … }` | ⏳ | |
| `return e;` / `return;` | ⏳ | |
| `r.addError(String)` | ⏳ | Records an error on the record; see the platform model. |
| Uncaught exceptions | ⏳ | Modelled as an outcome that carries the exception type. |

## Explicitly not in the subset (yet)

❌ SOQL, SOSL, DML, `Database.*` · `try`/`catch`/`finally`, `throw` · `while`, `do`, classic `for` ·
`switch` · instance methods, constructors, inheritance, interfaces · static and instance fields ·
generics beyond `List`/`Map` of the types above · string, date and math library methods ·
`Trigger.*` context variables (the handler receives them as parameters) · `Limits.*` · async Apex ·
callouts.
