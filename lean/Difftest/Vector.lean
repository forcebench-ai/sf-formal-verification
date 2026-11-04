import SfVerify.Apex.Semantics
import SfVerify.Apex.Syntax.Pretty
import Lean.Data.Json

/-!
# Difftest vectors

Not part of the trusted base: this only produces evidence. A vector is a small program with its
input. The Lean side evaluates it with the interpreter the proofs reason about; the org side runs
the text the trusted pretty-printer produces for the same term.
-/

namespace Difftest

open SfVerify.Apex SfVerify.Platform Lean

structure Vector where
  id : String
  prog : Program
  cls : String := "T"
  method : String := "main"
  args : List Value := []
  heap : Heap := []

/-- Enough for every program in the catalog; running out is reported as a failure, not a pass. -/
def fuel : Nat := 200

def Vector.result (v : Vector) : Outcome (Option Value) :=
  run v.prog fuel v.cls v.method v.args v.heap

def Vector.entry (v : Vector) : Option Method :=
  v.prog.findMethod v.cls v.method

/-! ## The Lean side's JSON -/

def dateText (d : Date) : String :=
  let pad (w n : Nat) := let s := toString n; String.ofList (List.replicate (w - s.length) '0') ++ s
  s!"{pad 4 d.year}-{pad 2 d.month}-{pad 2 d.day}"

def valueJson : Value → Json
  | .null => .null
  | .bool b => Json.mkObj [("bool", .bool b)]
  | .int i => Json.mkObj [("int", .str (toString i))]
  | .dec d => Json.mkObj [("dec", .str d.plain)]
  | .str s => Json.mkObj [("str", .str s)]
  | .date d => Json.mkObj [("date", .str (dateText d))]
  | .id s => Json.mkObj [("id", .str s)]
  | .ref r => Json.mkObj [("ref", .num r)]

def recordJson (r : Record) : Json :=
  Json.mkObj [
    ("fields", Json.mkObj (r.fields.map fun (k, v) => (k, valueJson v))),
    ("error", match r.error with
      | some m => .str m
      | none => .null)]

def heapJson (h : Heap) : Json :=
  Json.arr (h.filterMap (fun
    | .record r => some (recordJson r)
    | _ => none)).toArray

def Vector.resultJson (v : Vector) : Json :=
  let base (outcome : Json) (h : Heap) :=
    Json.mkObj [("id", .str v.id), ("outcome", outcome), ("heap", heapJson h)]
  match v.result with
  | .ok r st =>
    base (Json.mkObj [("kind", .str "normal"), ("ret", valueJson (r.getD .null))]) st.heap
  | .exc .nullPointer st =>
    base (Json.mkObj [("kind", .str "exception"), ("type", .str "System.NullPointerException")])
      st.heap
  | .outOfFuel => base (Json.mkObj [("kind", .str "outOfFuel")]) v.heap
  | .unsupported why =>
    base (Json.mkObj [("kind", .str "unsupported"), ("why", .str why)]) v.heap

end Difftest
