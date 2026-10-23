import SfVerify.Axioms

/-!
# SfVerify

Models of the Salesforce languages we verify, the platform they run on, and reusable lemmas. Apex
is the first language; others (for example the formula language) get their own `SfVerify.<Lang>`.

* `SfVerify.Axioms`         — the axiom allowlist. **Trusted.**
* `SfVerify.Apex.Syntax`    — AST for the Apex subset (`docs/apex-subset.md`). **Trusted.**
* `SfVerify.Apex.Semantics` — executable semantics of the Apex subset. **Trusted.**
* `SfVerify.Platform`       — sObject records, field access, `addError`, limit counters
                              (`docs/platform-model.md`). Shared by every language. **Trusted.**
* `SfVerify.Lib`            — reusable lemmas about lists, maps, nulls and loops. Untrusted; keep
                              it general so later subjects can reuse it.
-/
