import SfVerify.Platform.Text

/-!
# Values, records and the heap

**Trusted base** (`docs/trusted-base.md` §3). The platform's data, shared by every language model.
`docs/platform-model.md` lists what this captures and what it simplifies.
-/

namespace SfVerify.Platform

/-- An arbitrary-precision decimal: `unscaled / 10 ^ scale`. Equality and ordering compare the
numeric value, so `1.0` equals `1.00`; the scale is kept because the platform keeps it. -/
structure Decimal where
  unscaled : Int
  scale : Nat
  deriving DecidableEq, Repr

namespace Decimal

def ofInt (i : Int) : Decimal := ⟨i, 0⟩

/-- Both operands scaled to a common denominator, so they compare as integers. -/
def aligned (a b : Decimal) : Int × Int :=
  (a.unscaled * (10 : Int) ^ b.scale, b.unscaled * (10 : Int) ^ a.scale)

def valueEq (a b : Decimal) : Bool := let (x, y) := aligned a b; x == y
def lt (a b : Decimal) : Bool := let (x, y) := aligned a b; decide (x < y)
def le (a b : Decimal) : Bool := let (x, y) := aligned a b; decide (x ≤ y)

end Decimal

/-- A calendar date, with no time zone. -/
structure Date where
  year : Nat
  month : Nat
  day : Nat
  deriving DecidableEq, Repr

/-- A runtime value. `ref` points at a heap object: every sObject, `List` and `Map` is a reference,
so a write through one alias is visible through every other. -/
inductive Value where
  | null
  | bool (b : Bool)
  | int (i : Int)
  | dec (d : Decimal)
  | str (s : String)
  | date (d : Date)
  | id (s : String)
  | ref (r : Nat)
  deriving DecidableEq, Repr

/-- The primitive types a value or a field can have. -/
inductive PrimTy where
  | boolean | integer | decimal | string | date | id
  deriving DecidableEq, Repr

/-- `v` converted for storage in a slot of type `t`, or `none` when it doesn't belong there. Null
fits everywhere. The one implicit conversion is `Integer` to `Decimal`, which is exact. -/
def PrimTy.coerce : PrimTy → Value → Option Value
  | _, .null => some .null
  | .boolean, .bool b => some (.bool b)
  | .integer, .int i => some (.int i)
  | .decimal, .int i => some (.dec (Decimal.ofInt i))
  | .decimal, .dec d => some (.dec d)
  | .string, .str s => some (.str s)
  | .date, .date d => some (.date d)
  | .id, .id s => some (.id s)
  | _, _ => none

/-- The modelled fields of an sObject type, under their canonical API names. Reading or writing any
other field is `unsupported`, so a derived field such as `IsClosed` can't silently read as null. -/
def fieldType : String → String → Option PrimTy
  | "Opportunity", "Id" => some .id
  | "Opportunity", "Name" => some .string
  | "Opportunity", "StageName" => some .string
  | "Opportunity", "Description" => some .string
  | "Opportunity", "Amount" => some .decimal
  | "Opportunity", "Probability" => some .decimal
  | "Opportunity", "CloseDate" => some .date
  | _, _ => none

/-- An in-memory sObject. `fields` holds what has been set; an unset field reads as null. At most
one record-level error is held, because a later `addError` replaces an earlier one. -/
structure Record where
  sobject : String
  fields : List (String × Value)
  error : Option String
  deriving DecidableEq, Repr

namespace Record

def read (r : Record) (field : String) : Value :=
  (r.fields.lookup field).getD .null

/-- Replace the field in place, or append it if it was never set. -/
def write (r : Record) (field : String) (v : Value) : Record :=
  if (r.fields.lookup field).isSome then
    { r with fields := r.fields.map fun kv => if kv.1 == field then (field, v) else kv }
  else
    { r with fields := r.fields ++ [(field, v)] }

def addError (r : Record) (msg : String) : Record :=
  { r with error := some msg }

end Record

/-- What a reference can point at. -/
inductive Obj where
  | record (r : Record)
  | list (items : List Value)
  | map (entries : List (Value × Value))
  deriving DecidableEq, Repr

abbrev Heap := List Obj

/-- `Map.get`: keys match exactly, with no case folding. A missing key gives null. -/
def mapLookup (entries : List (Value × Value)) (key : Value) : Value :=
  (entries.lookup key).getD .null

/-- `==` on two values, or `none` where the model doesn't define it: two non-null references (Apex
compares sObjects, lists and maps by content) and mixed types (which don't compile). -/
def Value.apexEq : Value → Value → Option Bool
  | .null, .null => some true
  | .null, _ => some false
  | _, .null => some false
  | .bool a, .bool b => some (a == b)
  | .int a, .int b => some (a == b)
  | .int a, .dec b => some ((Decimal.ofInt a).valueEq b)
  | .dec a, .int b => some (a.valueEq (Decimal.ofInt b))
  | .dec a, .dec b => some (a.valueEq b)
  | .str a, .str b => some (stringEq a b)
  | .date a, .date b => some (a == b)
  | .id a, .id b => some (a == b)
  | _, _ => none

/-- The numeric reading of a value, for `<` and friends. -/
def Value.asDecimal : Value → Option Decimal
  | .int i => some (Decimal.ofInt i)
  | .dec d => some d
  | _ => none

end SfVerify.Platform
