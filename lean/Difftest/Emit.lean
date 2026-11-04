import Difftest.Vector

/-!
# The org side: anonymous Apex for a batch of vectors

Each vector becomes a few methods plus a call. It catches its own exceptions and prints one
`SFVDT <json>` line in the format `Difftest.Vector.resultJson` produces, so a script-level failure
always means the run is invalid. Anonymous Apex can't declare static methods, so `C.m` is flattened
to a method named after the vector.
-/

namespace Difftest

open SfVerify.Apex SfVerify.Platform

/-- Helpers shared by every vector in a script. They print the model's modelled fields only. -/
def prologue : String := "String sfvB(Boolean v) { return v == null ? 'null' : '{\"bool\":' + v + '}'; }
String sfvI(Integer v) { return v == null ? 'null' : '{\"int\":\"' + v + '\"}'; }
String sfvN(Decimal v) { return v == null ? 'null' : '{\"dec\":\"' + v.toPlainString() + '\"}'; }
String sfvS(String v) { return v == null ? 'null' : '{\"str\":' + JSON.serialize(v) + '}'; }
String sfvK(Id v) { return v == null ? 'null' : '{\"id\":\"' + String.valueOf(v) + '\"}'; }
String sfvP(Integer v, Integer w) { return String.valueOf(v).leftPad(w, '0'); }
String sfvT(Date v) { return v == null ? 'null' : '{\"date\":\"' + sfvP(v.year(), 4) + '-' + sfvP(v.month(), 2) + '-' + sfvP(v.day(), 2) + '\"}'; }
String sfvF(Map<String, Object> m, String f, String j) { return m.containsKey(f) ? JSON.serialize(f) + ':' + j : null; }
String sfvR(Opportunity r) {
  Map<String, Object> m = r.getPopulatedFieldsAsMap();
  List<String> fs = new List<String>();
  for (String s : new List<String>{
      sfvF(m, 'Id', sfvK(r.Id)), sfvF(m, 'Name', sfvS(r.Name)), sfvF(m, 'StageName', sfvS(r.StageName)),
      sfvF(m, 'Description', sfvS(r.Description)), sfvF(m, 'Amount', sfvN(r.Amount)),
      sfvF(m, 'Probability', sfvN(r.Probability)), sfvF(m, 'CloseDate', sfvT(r.CloseDate)) }) {
    if (s != null) { fs.add(s); }
  }
  List<Database.Error> es = r.getErrors();
  String err = es.isEmpty() ? 'null' : (es.size() == 1 ? JSON.serialize(es[0].getMessage()) : '\"MORE THAN ONE ERROR\"');
  return '{\"fields\":{' + String.join(fs, ',') + '},\"error\":' + err + '}';
}
Organization sfvO = [SELECT OrganizationType, InstanceName FROM Organization LIMIT 1];
System.debug('SFVMETA ' + JSON.serialize(new Map<String, String>{ 'orgType' => sfvO.OrganizationType, 'instance' => sfvO.InstanceName }));
"

def valueApex : Value → String
  | .null => "null"
  | .bool b => if b then "true" else "false"
  | .int i => if i < 0 then s!"({i})" else toString i
  | .dec d => if d.unscaled < 0 then s!"({d.plain})" else d.plain
  | .str s => stringLiteral s
  | .date d => s!"Date.newInstance({d.year}, {d.month}, {d.day})"
  | .id s => s!"(Id) {stringLiteral s}"
  | .ref r => s!"h{r}"

/-- Declares the input heap as locals `h0`, `h1`, … Records first: lists and maps refer to them. -/
def heapSetup (h : Heap) : String :=
  let indexed := h.zipIdx
  let records := indexed.filterMap fun
    | (.record r, i) =>
      let fields := r.fields.map fun (f, v) => s!"  h{i}.{f} = {valueApex v};\n"
      let err := match r.error with
        | some m => s!"  h{i}.addError({stringLiteral m});\n"
        | none => ""
      some (s!"  {r.sobject} h{i} = new {r.sobject}();\n" ++ String.join fields ++ err)
    | _ => none
  let others := indexed.filterMap fun
    | (.list items, i) =>
      let body := ", ".intercalate (items.map valueApex)
      some s!"  List<Opportunity> h{i} = new List<Opportunity>\{{body}};\n"
    | (.map entries, i) =>
      let keyTy := match entries.head? with
        | some (.str _, _) => "String"
        | _ => "Id"
      let body := ", ".intercalate (entries.map fun (k, v) => s!"{valueApex k} => {valueApex v}")
      some s!"  Map<{keyTy}, Opportunity> h{i} = new Map<{keyTy}, Opportunity>\{{body}};\n"
    | _ => none
  String.join records ++ String.join others

/-- An Apex expression producing the JSON of the entry's return value held in local `r`. -/
def retJson (h : Heap) : Option Ty → String
  | none => "'null'"
  | some (.prim .boolean) => "sfvB(r)"
  | some (.prim .integer) => "sfvI(r)"
  | some (.prim .decimal) => "sfvN(r)"
  | some (.prim .string) => "sfvS(r)"
  | some (.prim .date) => "sfvT(r)"
  | some (.prim .id) => "sfvK(r)"
  | some _ =>
    -- A reference: report which heap object it is, by identity.
    let tests := h.zipIdx.filterMap fun
      | (.record _, i) => some s!"r === h{i} ? '\{\"ref\":{i}}' : "
      | _ => none
    "(r == null ? 'null' : " ++ String.join tests ++ "'\"UNKNOWN REFERENCE\"')"

def Vector.script (v : Vector) (n : Nat) : String :=
  let q : CallName := fun c m => s!"v{n}_{c}_{m}"
  let methods := v.prog.flatMap fun c => c.methods.map fun m =>
    s!"{m.signature (q c.name m.name)} \{\n{Stmt.apexList q "  " m.body}}\n"
  let args := ", ".intercalate (v.args.map valueApex)
  let call := s!"{q v.cls v.method}({args})"
  let retTy := v.entry.bind (·.ret)
  let invoke := match retTy with
    | some t => s!"{t.apex} r = {call};"
    | none => s!"{call};"
  let records := v.heap.zipIdx.filterMap fun
    | (.record _, i) => some s!"sfvR(h{i})"
    | _ => none
  let heapExpr := if records.isEmpty then "''" else " + ',' + ".intercalate records
  s!"// {v.id}\n" ++ String.join methods ++ s!"void v{n}() \{\n" ++ heapSetup v.heap ++
    s!"  String o;\n  try \{\n    {invoke}\n    o = '\{\"kind\":\"normal\",\"ret\":' + {retJson v.heap retTy} + '}';\n" ++
    "  } catch (Exception e) {\n    o = '{\"kind\":\"exception\",\"type\":\"' + e.getTypeName() + '\"}';\n  }\n" ++
    s!"  System.debug('SFVDT \{\"id\":' + JSON.serialize({stringLiteral v.id}) + ',\"outcome\":' + o + ',\"heap\":[' + {heapExpr} + ']}');\n}\nv{n}();\n"

/-- Anonymous Apex is limited to 32,000 characters; stay well under it. -/
def batchLimit : Nat := 25000

/-- Split vectors into scripts, each with the shared prologue. -/
def batches (vs : List Vector) : List String :=
  let step (acc : List String × String) (item : Vector × Nat) :=
    let (done, cur) := acc
    let s := item.1.script item.2
    if cur.length + s.length > batchLimit && !cur.isEmpty then
      (cur :: done, s)
    else (done, cur ++ s)
  let (done, cur) := (vs.zipIdx.foldl step ([], ""))
  ((if cur.isEmpty then done else cur :: done).reverse).map (prologue ++ ·)

end Difftest
