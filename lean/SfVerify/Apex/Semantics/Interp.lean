import SfVerify.Apex.Syntax.Ast

/-!
# Executable semantics of the Apex subset

**Trusted base** (`docs/trusted-base.md` §2). A total, fuel-bounded interpreter. The same definition
is what the kernel reasons about and what difftest runs against the reference org.

Three things are never success, so a proof can't mistake them for it: an uncaught exception, running
out of fuel, and a construct or value the model doesn't define (`unsupported`).
-/

namespace SfVerify.Apex

open SfVerify.Platform

/-- Exceptions the subset can raise. -/
inductive ExcType where
  | nullPointer
  deriving DecidableEq, Repr

/-- A method frame's locals with their declared types. Apex rejects shadowing at compile time and
scoping errors can't compile, so one flat frame per call is faithful for programs the org accepts. -/
abbrev Env := List (String × Ty × Value)

structure State where
  heap : Heap
  env : Env
  soql : Nat := 0
  dml : Nat := 0
  deriving DecidableEq, Repr

inductive Outcome (α : Type) where
  | ok (a : α) (st : State)
  /-- An uncaught exception. Heap writes made before it remain visible in `st`. -/
  | exc (e : ExcType) (st : State)
  | outOfFuel
  | unsupported (why : String)
  deriving DecidableEq, Repr

def Outcome.bind {α β : Type} : Outcome α → (α → State → Outcome β) → Outcome β
  | .ok a st, f => f a st
  | .exc e st, _ => .exc e st
  | .outOfFuel, _ => .outOfFuel
  | .unsupported why, _ => .unsupported why

/-- How a statement finished: fell through, or `return`ed. -/
inductive Flow where
  | next
  | ret (v : Option Value)
  deriving DecidableEq, Repr

/-- `v` converted for storage in a slot of type `t`. References aren't checked against their static
type: the org only runs programs that compile. -/
def Ty.coerce : Ty → Value → Option Value
  | .prim p, v => p.coerce v
  | _, .null => some .null
  | _, .ref r => some (.ref r)
  | _, _ => none

def Lit.toValue : Lit → Value
  | .null => .null
  | .bool b => .bool b
  | .int i => .int i
  | .dec d => .dec d
  | .str s => .str s

namespace State

def lookup (st : State) (x : String) : Option (Ty × Value) :=
  st.env.lookup x

/-- Set a local, replacing an earlier entry so a loop body re-declaring it starts afresh. -/
def bind (st : State) (x : String) (t : Ty) (v : Value) : State :=
  { st with env := (x, t, v) :: st.env.filter (·.1 != x) }

def readField (st : State) (target : Value) (field : String) : Outcome Value :=
  match target with
  | .null => .exc .nullPointer st
  | .ref r =>
    match st.heap[r]? with
    | some (.record rec) =>
      match fieldType rec.sobject field with
      | some _ => .ok (rec.read field) st
      | none => .unsupported s!"field {rec.sobject}.{field}"
    | _ => .unsupported "field read on a non-record"
  | _ => .unsupported "field read on a non-reference"

def writeField (st : State) (target : Value) (field : String) (v : Value) : Outcome Flow :=
  match target with
  | .null => .exc .nullPointer st
  | .ref r =>
    match st.heap[r]? with
    | some (.record rec) =>
      match fieldType rec.sobject field with
      | none => .unsupported s!"field {rec.sobject}.{field}"
      | some t =>
        match t.coerce v with
        | none => .unsupported s!"ill-typed write to {field}"
        | some v' =>
          .ok .next { st with heap := st.heap.set r (.record (rec.write field v')) }
    | _ => .unsupported "field write on a non-record"
  | _ => .unsupported "field write on a non-reference"

def addError (st : State) (target msg : Value) : Outcome Flow :=
  match target, msg with
  | .null, _ => .exc .nullPointer st
  | .ref r, .str m =>
    match st.heap[r]? with
    | some (.record rec) => .ok .next { st with heap := st.heap.set r (.record (rec.addError m)) }
    | _ => .unsupported "addError on a non-record"
  | _, _ => .unsupported "addError with a null or non-String message"

def mapGet (st : State) (m k : Value) : Outcome Value :=
  match m with
  | .null => .exc .nullPointer st
  | .ref r =>
    match st.heap[r]? with
    | some (.map entries) => .ok (mapLookup entries k) st
    | _ => .unsupported "get on a non-map"
  | _ => .unsupported "get on a non-reference"

end State

/-- `l op r` once both operands are evaluated. -/
def evalCmp (op : CmpOp) (l r : Value) (st : State) : Outcome Value :=
  let equal (k : Bool → Bool) : Outcome Value :=
    match l.apexEq r with
    | some b => .ok (.bool (k b)) st
    | none => .unsupported "== on these operand types"
  let order (k : Decimal → Decimal → Bool) : Outcome Value :=
    match l, r with
    | .null, _ | _, .null => .exc .nullPointer st
    | _, _ =>
      match l.asDecimal, r.asDecimal with
      | some a, some b => .ok (.bool (k a b)) st
      | _, _ => .unsupported "ordering on non-numeric operands"
  match op with
  | .eq => equal id
  | .ne => equal (!·)
  | .lt => order Decimal.lt
  | .le => order Decimal.le
  | .gt => order fun a b => Decimal.lt b a
  | .ge => order fun a b => Decimal.le b a

/-- Continue with a Boolean condition: null raises, a non-Boolean isn't modelled. -/
def withBool {α : Type} (v : Value) (st : State) (k : Bool → State → Outcome α) : Outcome α :=
  match v with
  | .bool b => k b st
  | .null => .exc .nullPointer st
  | _ => .unsupported "condition is not a Boolean"

/-- Bind parameters for a call, widening each argument to its declared type. -/
def bindParams (ps : List (Ty × String)) (args : List Value) : Option Env :=
  match ps, args with
  | [], [] => some []
  | (t, x) :: ps, v :: vs =>
    match t.coerce v, bindParams ps vs with
    | some v', some rest => some ((x, t, v') :: rest)
    | _, _ => none
  | _, _ => none

mutual

def eval (p : Program) : Nat → Expr → State → Outcome Value
  | 0, _, _ => .outOfFuel
  | _ + 1, .lit l, st => .ok l.toValue st
  | _ + 1, .var x, st =>
    match st.lookup x with
    | some (_, v) => .ok v st
    | none => .unsupported s!"unbound variable {x}"
  | n + 1, .field e f, st => (eval p n e st).bind fun v st => st.readField v f
  | n + 1, .cmp op l r, st =>
    (eval p n l st).bind fun a st => (eval p n r st).bind fun b st => evalCmp op a b st
  | n + 1, .and l r, st =>
    (eval p n l st).bind fun a st => withBool a st fun a st =>
      if a then
        (eval p n r st).bind fun b st => withBool b st fun b st => .ok (.bool b) st
      else .ok (.bool false) st
  | n + 1, .or l r, st =>
    (eval p n l st).bind fun a st => withBool a st fun a st =>
      if a then .ok (.bool true) st
      else (eval p n r st).bind fun b st => withBool b st fun b st => .ok (.bool b) st
  | n + 1, .not e, st =>
    (eval p n e st).bind fun v st => withBool v st fun b st => .ok (.bool (!b)) st
  | n + 1, .call c m args, st =>
    (evalArgs p n args st).bind fun vs st =>
      (invoke p n c m vs st).bind fun r st =>
        .ok (r.getD .null) st
  | n + 1, .mapGet m k, st =>
    (eval p n m st).bind fun mv st => (eval p n k st).bind fun kv st => st.mapGet mv kv

def evalArgs (p : Program) : Nat → List Expr → State → Outcome (List Value)
  | 0, _, _ => .outOfFuel
  | _ + 1, [], st => .ok [] st
  | n + 1, e :: es, st =>
    (eval p n e st).bind fun v st => (evalArgs p n es st).bind fun vs st => .ok (v :: vs) st

/-- Call `c.m(vs)` in a fresh frame, restoring the caller's frame afterwards. -/
def invoke (p : Program) : Nat → String → String → List Value → State → Outcome (Option Value)
  | 0, _, _, _, _ => .outOfFuel
  | n + 1, c, m, vs, st =>
    match p.findMethod c m with
    | none => .unsupported s!"unknown method {c}.{m}"
    | some meth =>
      match bindParams meth.params vs with
      | none => .unsupported s!"bad arguments to {c}.{m}"
      | some frame =>
        match execBlock p n meth.body { st with env := frame } with
        | .ok flow st' =>
          let back := { st' with env := st.env }
          match flow, meth.ret with
          | .next, none => .ok none back
          | .ret none, none => .ok none back
          | .ret (some v), some t =>
            match t.coerce v with
            | some v' => .ok (some v') back
            | none => .unsupported s!"ill-typed return from {c}.{m}"
          | _, _ => .unsupported s!"return does not match the signature of {c}.{m}"
        | .exc e st' => .exc e { st' with env := st.env }
        | .outOfFuel => .outOfFuel
        | .unsupported why => .unsupported why

def exec (p : Program) : Nat → Stmt → State → Outcome Flow
  | 0, _, _ => .outOfFuel
  | n + 1, .decl t x init, st =>
    match init with
    | none => .ok .next (st.bind x t .null)
    | some e =>
      (eval p n e st).bind fun v st =>
        match t.coerce v with
        | some v' => .ok .next (st.bind x t v')
        | none => .unsupported s!"ill-typed initialiser for {x}"
  | n + 1, .assign x e, st =>
    (eval p n e st).bind fun v st =>
      match st.lookup x with
      | none => .unsupported s!"assignment to unbound {x}"
      | some (t, _) =>
        match t.coerce v with
        | some v' => .ok .next (st.bind x t v')
        | none => .unsupported s!"ill-typed assignment to {x}"
  | n + 1, .setField target f e, st =>
    (eval p n target st).bind fun tv st =>
      (eval p n e st).bind fun v st => st.writeField tv f v
  | n + 1, .ite c t e, st =>
    (eval p n c st).bind fun v st => withBool v st fun b st =>
      if b then exec p n t st
      else
        match e with
        | some s => exec p n s st
        | none => .ok .next st
  | n + 1, .forEach t x coll body, st =>
    (eval p n coll st).bind fun cv st =>
      match cv with
      | .null => .exc .nullPointer st
      | .ref r =>
        match st.heap[r]? with
        | some (.list items) => execLoop p n t x items body st
        | _ => .unsupported "for over a non-list"
      | _ => .unsupported "for over a non-reference"
  | n + 1, .block body, st => execBlock p n body st
  | n + 1, .ret e, st =>
    match e with
    | none => .ok (.ret none) st
    | some e => (eval p n e st).bind fun v st => .ok (.ret (some v)) st
  | n + 1, .addError target msg, st =>
    (eval p n target st).bind fun tv st =>
      (eval p n msg st).bind fun mv st => st.addError tv mv

def execBlock (p : Program) : Nat → List Stmt → State → Outcome Flow
  | 0, _, _ => .outOfFuel
  | _ + 1, [], st => .ok .next st
  | n + 1, s :: ss, st =>
    (exec p n s st).bind fun flow st =>
      match flow with
      | .next => execBlock p n ss st
      | .ret v => .ok (.ret v) st

def execLoop (p : Program) : Nat → Ty → String → List Value → Stmt → State → Outcome Flow
  | 0, _, _, _, _, _ => .outOfFuel
  | _ + 1, _, _, [], _, st => .ok .next st
  | n + 1, t, x, v :: vs, body, st =>
    match t.coerce v with
    | none => .unsupported s!"ill-typed loop element for {x}"
    | some v' =>
      (exec p n body (st.bind x t v')).bind fun flow st =>
        match flow with
        | .next => execLoop p n t x vs body st
        | .ret r => .ok (.ret r) st

end

/-- Call a method from outside, as the platform or a test would. -/
def run (p : Program) (fuel : Nat) (cls method : String) (args : List Value) (heap : Heap) :
    Outcome (Option Value) :=
  invoke p fuel cls method args { heap := heap, env := [] }

end SfVerify.Apex
