import Difftest.Catalog
import Difftest.Emit

/-!
`lake exe difftest <dir>` writes `batch-NNNN.apex` for the org side and `expected.jsonl` from the
Lean interpreter. `tools/difftest/run.py` runs the batches and compares.

It also writes `kernel-replay.lean`, which restates each compiled result as a claim the kernel must
check by evaluation. That shows the kernel and the compiled interpreter agree (ADR 0001): difftest
runs compiled code, while the proofs are about what the kernel sees.
-/

open Difftest

def pad4 (n : Nat) : String :=
  let s := toString n
  String.ofList (List.replicate (4 - s.length) '0') ++ s

/-- One `example` per vector, stating what the compiled interpreter just computed. -/
def kernelReplay : String :=
  let header := "import Difftest.Catalog\nopen Difftest SfVerify.Apex SfVerify.Platform\n\n" ++
    "def vectorResult (i : Nat) : Outcome (Option Value) :=\n" ++
    "  match catalog[i]? with\n  | some v => v.result\n  | none => .outOfFuel\n\n"
  let claims := catalog.zipIdx.map fun (v, i) =>
    s!"-- {v.id}\nexample : vectorResult {i} = {Std.Format.pretty (repr v.result) 100000} := by decide +kernel\n"
  header ++ String.join claims

def main (args : List String) : IO UInt32 := do
  let some dir := args.head? | do
    IO.eprintln "usage: difftest <output dir>"
    return 2
  IO.FS.createDirAll dir
  let lines := catalog.map fun v => v.resultJson.compress
  IO.FS.writeFile (dir ++ "/expected.jsonl") ("\n".intercalate lines ++ "\n")
  let scripts := batches catalog
  for (s, i) in scripts.zipIdx do
    IO.FS.writeFile (dir ++ s!"/batch-{pad4 (i + 1)}.apex") s
  IO.FS.writeFile (dir ++ "/kernel-replay.lean") kernelReplay
  let bad := catalog.filter fun v =>
    match v.result with
    | .outOfFuel | .unsupported _ => true
    | _ => false
  for v in bad do
    IO.eprintln s!"not modelled: {v.id}: {v.resultJson.compress}"
  IO.println s!"difftest: {catalog.length} vectors, {scripts.length} batches, {bad.length} not modelled"
  return if bad.isEmpty then 0 else 1
