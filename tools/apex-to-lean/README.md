# apex-to-lean: Apex → Lean exporter

**Trusted base** (`docs/trusted-base.md` §5). This tool decides which Lean term the theorems are
*about*, so it is kept as small as possible and tested by round trip. **Status:** design only.
Implementation is milestone 3.

## What it does

```
subjects/<subject>/force-app/**/<Class>.cls  ──parse──▶  ANTLR parse tree  ──export──▶  lean/Subjects/<Subject>/<Class>.lean
```

- Parses with [`@apexdevtools/apex-parser`](https://github.com/apex-dev-tools/apex-parser), pinned
  to an exact version, running on Node.
- Walks the parse tree and emits one Lean `def` per class whose value is a term of the AST type
  in `lean/ApexVerify/Syntax/`.
- Rejects **anything outside the [modelled subset](../../docs/apex-subset.md)** with an error
  naming the construct, file and line. It never approximates and never drops a construct.
- Normalises only what Apex itself treats as equivalent: identifier and field-name case, which
  the platform model documents.

## How it is kept honest

1. **Round trip.** parse `.cls` → Lean AST term → pretty-print back to Apex → parse again → Lean
   AST term. The two terms must be identical. The pretty-printer lives **in Lean**
   (`ApexVerify.Syntax`), so the round trip covers the exact term the proofs use, not an
   intermediate representation of the exporter's own.
2. **Regeneration in CI.** CI re-runs the exporter on every subject and fails on any diff in
   `lean/Subjects/`, so the generated files can't be edited by hand into something easier to
   prove.
3. **Size.** Exporter logic should stay a few hundred lines. Anything clever belongs in the
   (difftested) semantics, not here.
