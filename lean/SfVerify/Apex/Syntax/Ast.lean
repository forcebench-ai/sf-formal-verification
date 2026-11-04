import SfVerify.Platform.Value

/-!
# Abstract syntax of the Apex subset

**Trusted base** (`docs/trusted-base.md` §2). Exactly the constructs in `docs/apex-subset.md`.
Identifiers and field names are in canonical case: Apex ignores their case, and the exporter
normalises it.
-/

namespace SfVerify.Apex

open SfVerify.Platform

inductive Ty where
  | prim (t : PrimTy)
  | sobject (name : String)
  | list (elem : Ty)
  | map (key val : Ty)
  deriving DecidableEq, Repr

inductive Lit where
  | null
  | bool (b : Bool)
  | int (i : Int)
  | dec (d : Decimal)
  | str (s : String)
  deriving DecidableEq, Repr

inductive CmpOp where
  | eq | ne | lt | le | gt | ge
  deriving DecidableEq, Repr

inductive Expr where
  | lit (l : Lit)
  | var (x : String)
  | field (target : Expr) (name : String)
  | cmp (op : CmpOp) (l r : Expr)
  | and (l r : Expr)
  | or (l r : Expr)
  | not (e : Expr)
  /-- Static call `C.m(args)`, within the same subject. -/
  | call (cls method : String) (args : List Expr)
  /-- `m.get(k)` -/
  | mapGet (m k : Expr)
  deriving Repr, BEq

inductive Stmt where
  | decl (ty : Ty) (x : String) (init : Option Expr)
  | assign (x : String) (e : Expr)
  | setField (target : Expr) (name : String) (e : Expr)
  | ite (c : Expr) (t : Stmt) (e : Option Stmt)
  | forEach (ty : Ty) (x : String) (coll : Expr) (body : Stmt)
  | block (body : List Stmt)
  | ret (e : Option Expr)
  /-- `r.addError(msg)` -/
  | addError (target : Expr) (msg : Expr)
  deriving Repr, BEq

structure Method where
  name : String
  params : List (Ty × String)
  /-- `none` for `void`. -/
  ret : Option Ty
  body : List Stmt
  deriving Repr, BEq

structure Class where
  name : String
  methods : List Method
  deriving Repr, BEq

abbrev Program := List Class

/-- Look up a static method by class and name. -/
def Program.findMethod (p : Program) (cls method : String) : Option Method :=
  (p.find? (·.name == cls)).bind fun c => c.methods.find? (·.name == method)

end SfVerify.Apex
