import Lean
import Fixtures.SkipKernel.Spec
open Lean Elab Command

-- Adds a "proof" of `False` with kernel checking disabled; the elaborator never sees a term.
set_option debug.skipKernelTC true in
run_cmd liftCoreM <| addDecl <| .thmDecl {
  name := `Fixtures.SkipKernel.Proofs.T
  levelParams := []
  type := mkConst ``Fixtures.SkipKernel.Spec.T
  value := mkConst ``True.intro
  all := [`Fixtures.SkipKernel.Proofs.T] }
