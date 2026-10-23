import Lean
import ApexVerify.Semantics.Axioms

/-!
# `lake exe axiomcheck`

**Trusted base** (`docs/trusted-base.md` §6, ADR 0002). Decides whether every statement in
`Spec/` is proven using only allowlisted axioms. Run it from `lean/` after `lake build`:

    lake exe axiomcheck [--root DIR] [--spec PREFIX] [--proofs PREFIX] [--also PREFIX]...
                        [--allow-unproven]

1. **Discovery.** Every module under the spec, proofs and `--also` prefixes is found *on disk*,
   so a file that no root module imports is still checked.
2. **Obligations.** Every parameterless `def _ : Prop` declared in a spec module is a statement.
3. **Matching.** The proof of `<spec>.X` is the `theorem <proofs>.X`, declared in a proofs module,
   whose type is *syntactically* the constant `<spec>.X`.
4. **Axioms.** Collected by our own traversal of types and values, not from `.olean` caches, and
   checked against `ApexVerify.Semantics.Axioms.allowed`. This is `#print axioms`, done
   programmatically.
5. **Execution fidelity.** No project constant a statement depends on may be `opaque`/`partial`,
   `@[implemented_by]` or `@[extern]`. Otherwise the compiled interpreter (what difftest runs)
   would differ from what the kernel reasons about.
6. **Kernel replay.** Every project declaration is re-checked by the kernel, starting from an
   environment containing only the toolchain's modules.

Exit status: 0 if every check passed, 1 if any check failed, 2 on a usage or setup error.
-/

open Lean

namespace AxiomCheck

structure Config where
  root : System.FilePath := "."
  spec : Name := `Spec
  proofs : Name := `Proofs
  also : Array Name := #[`ApexVerify, `Subjects]
  allowUnproven : Bool := false

def usage : String :=
  "usage: lake exe axiomcheck [--root DIR] [--spec PREFIX] [--proofs PREFIX] " ++
  "[--also PREFIX]... [--allow-unproven]"

def parseArgs (args : List String) : Except String Config :=
  go {} false args
where
  go (cfg : Config) (alsoGiven : Bool) : List String → Except String Config
    | [] => .ok cfg
    | "--root" :: d :: rest => go { cfg with root := d } alsoGiven rest
    | "--spec" :: p :: rest => go { cfg with spec := p.toName } alsoGiven rest
    | "--proofs" :: p :: rest => go { cfg with proofs := p.toName } alsoGiven rest
    | "--also" :: p :: rest =>
      go { cfg with also := (if alsoGiven then cfg.also else #[]).push p.toName } true rest
    | "--allow-unproven" :: rest => go { cfg with allowUnproven := true } alsoGiven rest
    | arg :: _ => .error s!"unknown or incomplete argument '{arg}'\n{usage}"

/-! ## Module discovery -/

/-- Modules that belong to the Lean toolchain, which is trusted (`docs/trusted-base.md` §7). -/
def isToolchainModule (m : Name) : Bool :=
  [`Init, `Std, `Lean, `Lake].contains m.getRoot

def modulePath (root : System.FilePath) (m : Name) : System.FilePath :=
  m.components.foldl (fun p c => p / c.toString (escape := false)) root

/-- All modules for `.lean` files under `dir`, recursively, named below `pfx`. -/
partial def walk (dir : System.FilePath) (pfx : Name) : IO (Array Name) := do
  let entries := (← dir.readDir).qsort (·.fileName < ·.fileName)
  let mut mods := #[]
  for e in entries do
    if ← e.path.isDir then
      mods := mods ++ (← walk e.path (.str pfx e.fileName))
    else if e.path.extension == some "lean" then
      if let some stem := e.path.fileStem then
        mods := mods.push (.str pfx stem)
  return mods

/-- The module `pfx` itself (if `pfx.lean` exists) and every module under the directory `pfx/`. -/
def discover (root : System.FilePath) (pfx : Name) : IO (Array Name) := do
  let base := modulePath root pfx
  let mut mods := #[]
  if ← (base.addExtension "lean").pathExists then
    mods := mods.push pfx
  if ← base.isDir then
    mods := mods ++ (← walk base pfx)
  return mods

/-! ## Dependency traversal

The same traversal as `Lean.CollectAxioms.collect`, but over the loaded constants only. It never
consults the per-module axiom data that `.olean` files carry.
-/

def usedConstants : ConstantInfo → Array Name
  | .axiomInfo v  => v.type.getUsedConstants
  | .defnInfo v   => v.type.getUsedConstants ++ v.value.getUsedConstants
  | .thmInfo v    => v.type.getUsedConstants ++ v.value.getUsedConstants
  | .opaqueInfo v => v.type.getUsedConstants ++ v.value.getUsedConstants
  | .quotInfo _   => #[]
  | .ctorInfo v   => v.type.getUsedConstants
  | .recInfo v    => v.type.getUsedConstants
  | .inductInfo v => v.type.getUsedConstants ++ v.ctors.toArray

/-- Every constant reachable from `roots` through types and values, in discovery order. -/
def reachable (env : Environment) (roots : Array Name) : Array Name := Id.run do
  let mut seen : NameSet := {}
  let mut order := #[]
  let mut stack := roots
  while !stack.isEmpty do
    let c := stack.back!
    stack := stack.pop
    if seen.contains c then continue
    seen := seen.insert c
    order := order.push c
    if let some ci := env.find? c then
      stack := stack ++ usedConstants ci
  return order

def axiomsOf (env : Environment) (c : Name) : Array Name :=
  (reachable env #[c]).filter (fun n => env.find? n matches some (.axiomInfo _))
    |>.qsort Name.lt

/-! ## Checking -/

structure Report where
  failures : Array String := #[]
  warnings : Array String := #[]
  proven : Nat := 0
  unproven : Nat := 0

abbrev CheckM := StateT Report IO

def fail (msg : String) : CheckM Unit := do
  IO.println s!"  FAIL {msg}"
  modify fun r => { r with failures := r.failures.push msg }

def warn (msg : String) : CheckM Unit := do
  IO.println s!"  WARN {msg}"
  modify fun r => { r with warnings := r.warnings.push msg }

def moduleOf (env : Environment) (c : Name) : Option Name :=
  env.getModuleIdxFor? c |>.map fun idx => env.header.moduleNames[idx.toNat]!

def constantsOfModule (env : Environment) (m : Name) : Array Name :=
  match env.getModuleIdx? m with
  | some idx => env.header.moduleData[idx.toNat]!.constNames
  | none => #[]

def isPropDef (env : Environment) (c : Name) : Bool :=
  match env.find? c with
  | some (.defnInfo d) => d.type == .sort .zero
  | _ => false

/-- Statements: parameterless `Prop` definitions declared in spec modules. -/
def collectObligations (cfg : Config) (env : Environment) (specMods : Array Name) :
    CheckM (Array Name) := do
  let mut obligations := #[]
  for m in specMods do
    for c in constantsOfModule env m do
      let some (.defnInfo d) := env.find? c | continue
      unless d.type == .sort .zero do continue
      if c.isInternal then
        fail s!"{c} (in {m}): private or internal Prop definitions are not allowed in spec modules"
      else if !(cfg.spec.isPrefixOf c) || c == cfg.spec then
        fail s!"{c} (in {m}): spec statements must live in namespace {cfg.spec}"
      else if !d.levelParams.isEmpty then
        fail s!"{c}: spec statements must not be universe-polymorphic"
      else
        obligations := obligations.push c
  return obligations.qsort Name.lt

/-- Only spec modules may declare `Prop` definitions in the spec namespace. -/
def checkNoForgedStatements (cfg : Config) (env : Environment) (otherMods : Array Name) :
    CheckM Unit := do
  for m in otherMods do
    for c in constantsOfModule env m do
      if cfg.spec.isPrefixOf c && isPropDef env c then
        fail s!"{c} is declared in {m}, outside the spec modules; \
          only spec modules may declare statements in namespace {cfg.spec}"

def checkObligation (cfg : Config) (env : Environment) (proofMods : Array Name) (c : Name) :
    CheckM Unit := do
  let p := c.replacePrefix cfg.spec cfg.proofs
  match env.find? p with
  | none =>
    let msg := s!"{c}: no proof (expected `theorem {p} : {c}` in a module under {cfg.proofs})"
    if cfg.allowUnproven then warn msg else fail msg
    modify fun r => { r with unproven := r.unproven + 1 }
  | some (.thmInfo t) =>
    if !(moduleOf env p |>.any proofMods.contains) then
      fail s!"{c}: {p} must be declared in a module under {cfg.proofs}, \
        not in {(moduleOf env p).getD `unknown}"
    else if !(t.levelParams.isEmpty && t.type == .const c []) then
      fail s!"{c}: {p} does not prove it; its type is `{t.type}`, expected exactly `{c}`"
    else
      let axs := axiomsOf env p
      let bad := axs.filter (!ApexVerify.Semantics.Axioms.allowed.contains ·)
      if bad.isEmpty then
        IO.println s!"  ok   {c}\n         proved by {p}\n         axioms: {axs.toList}"
        modify fun r => { r with proven := r.proven + 1 }
      else
        fail s!"{c}: {p} depends on axioms outside the allowlist: {bad.toList} \
          (all axioms: {axs.toList})"
  | some _ =>
    fail s!"{c}: {p} exists but is not a theorem"

/-- Project constants a statement depends on must execute exactly as the kernel sees them. -/
def checkFidelity (env : Environment) (projectMods : Array Name) (obligations : Array Name) :
    CheckM Unit := do
  for c in reachable env obligations do
    unless moduleOf env c |>.any projectMods.contains do continue
    if env.find? c matches some (.opaqueInfo _) then
      fail s!"{c} is opaque (declared `opaque` or `partial`): the kernel cannot see its body, \
        so no statement may depend on it"
    if (Compiler.getImplementedBy? env c).isSome then
      fail s!"{c} has @[implemented_by]: compiled code differs from what the kernel checks"
    if isExtern env c then
      fail s!"{c} has @[extern]: compiled code differs from what the kernel checks"

/-- Re-check every project declaration with the kernel, from a toolchain-only environment. -/
def replayProject (env : Environment) (projectMods : Array Name) : CheckM Unit := do
  let toolchainMods := env.header.moduleNames.filter (!projectMods.contains ·)
  let base ← importModules (toolchainMods.map ({ module := · })) {}
  let mut constants : Std.HashMap Name ConstantInfo := {}
  for m in projectMods do
    if let some idx := env.getModuleIdx? m then
      for ci in env.header.moduleData[idx.toNat]!.constants do
        constants := constants.insert ci.name ci
  try
    discard <| base.toKernelEnv.replay constants
    IO.println s!"  ok   kernel replay: {constants.size} project declarations re-checked"
  catch e =>
    fail s!"kernel replay rejected a project declaration: {e}"

def run (cfg : Config) : IO UInt32 := do
  initSearchPath (← findSysroot)
  let specMods ← discover cfg.root cfg.spec
  let proofMods ← discover cfg.root cfg.proofs
  if specMods.isEmpty || proofMods.isEmpty then
    IO.eprintln s!"axiomcheck: no modules found for {cfg.spec} or {cfg.proofs} under {cfg.root}"
    return 2
  let mut alsoMods := #[]
  for pfx in cfg.also do
    alsoMods := alsoMods ++ (← discover cfg.root pfx)
  let projectMods := specMods ++ proofMods ++ alsoMods
  IO.println s!"axiomcheck: {specMods.size} spec, {proofMods.size} proof and \
    {alsoMods.size} other module(s); allowed axioms {ApexVerify.Semantics.Axioms.allowed}"
  let env ← importModules (projectMods.map ({ module := · })) {}
  let check : CheckM Unit := do
    for m in env.header.moduleNames do
      unless projectMods.contains m || isToolchainModule m do
        fail s!"module {m} is imported but is neither under a checked prefix nor part of \
          the toolchain, so it would escape the kernel replay"
    let obligations ← collectObligations cfg env specMods
    checkNoForgedStatements cfg env (proofMods ++ alsoMods)
    IO.println s!"statements ({obligations.size}):"
    for c in obligations do
      checkObligation cfg env proofMods c
    IO.println "execution fidelity and kernel replay:"
    checkFidelity env projectMods obligations
    replayProject env projectMods
  let ((), report) ← check.run {}
  let summary := s!"{report.proven} proven, {report.unproven} unproven, \
    {report.failures.size} failure(s), {report.warnings.size} warning(s)"
  if report.failures.isEmpty then
    IO.println s!"PASS: {summary}"
    return 0
  else
    IO.println s!"FAIL: {summary}"
    return 1

end AxiomCheck

def main (args : List String) : IO UInt32 := do
  match AxiomCheck.parseArgs args with
  | .error e => IO.eprintln e; return 2
  | .ok cfg => AxiomCheck.run cfg
