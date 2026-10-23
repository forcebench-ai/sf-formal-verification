import ApexVerify.Semantics.Axioms

/-!
# ApexVerify

The Apex subset's syntax and executable semantics, the Salesforce platform model, and reusable
lemmas.

* `ApexVerify.Syntax`    — AST for the Apex subset (`docs/apex-subset.md`). **Trusted.**
* `ApexVerify.Semantics` — executable semantics; `Axioms` holds the axiom allowlist. **Trusted.**
* `ApexVerify.Platform`  — sObject records, field access, `addError`, limit counters
                           (`docs/platform-model.md`). **Trusted.**
* `ApexVerify.Lib`       — reusable lemmas about lists, maps, nulls and loops. Untrusted; keep it
                           general so later subjects can reuse it.
-/
