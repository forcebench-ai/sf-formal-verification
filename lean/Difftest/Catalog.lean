import Difftest.Vector

/-!
# Per-construct vectors

Level 1 of `tools/difftest/README.md`: every rule of the semantics, with its null and exception
cases. A rule without a vector here doesn't count as modelled (`docs/apex-subset.md`).
-/

namespace Difftest

open SfVerify.Apex SfVerify.Platform

abbrev tBool : Ty := .prim .boolean
abbrev tInt : Ty := .prim .integer
abbrev tDec : Ty := .prim .decimal
abbrev tStr : Ty := .prim .string
abbrev tDate : Ty := .prim .date
abbrev tId : Ty := .prim .id
abbrev tOpp : Ty := .sobject "Opportunity"
abbrev tOpps : Ty := .list tOpp
abbrev tOppMap : Ty := .map tId tOpp

def d (u : Int) (s : Nat) : Value := .dec ⟨u, s⟩
def x : Expr := .var "x"
def y : Expr := .var "y"
def r : Expr := .var "r"

def opp (fields : List (String × Value) := []) (error : Option String := none) : Obj :=
  .record { sobject := "Opportunity", fields := fields, error := error }

/-- `mark(r, m)` writes `m` to `r.Description` and returns 1, which reveals whether and in what order
an expression was evaluated. -/
def markMethod : Method :=
  { name := "mark", params := [(tOpp, "t"), (tStr, "m")], ret := some tDec,
    body := [.setField (.var "t") "Description" (.var "m"), .ret (some (.lit (.int 1)))] }

def markE (m : String) : Expr := .call "T" "mark" [r, .lit (.str m)]

/-- Same, as the message of an `addError`. -/
def markMsgMethod : Method :=
  { name := "markMsg", params := [(tOpp, "t")], ret := some tStr,
    body := [.setField (.var "t") "Description" (.lit (.str "evaluated")),
             .ret (some (.lit (.str "message")))] }

def prog (params : List (Ty × String)) (ret : Option Ty) (body : List Stmt)
    (helpers : List Method := []) : Program :=
  [{ name := "T", methods := { name := "main", params, ret, body } :: helpers }]

/-- A vector whose whole body is `return e`. -/
def expr (id : String) (params : List (Ty × String × Value)) (ret : Ty) (e : Expr)
    (heap : Heap := []) (helpers : List Method := []) : Vector :=
  { id, heap,
    prog := prog (params.map fun (t, n, _) => (t, n)) (some ret) [.ret (some e)] helpers,
    args := params.map fun (_, _, v) => v }

/-- A vector with statements, observed through its return value and the heap. -/
def stmts (id : String) (params : List (Ty × String × Value)) (ret : Option Ty) (body : List Stmt)
    (heap : Heap := []) (helpers : List Method := []) : Vector :=
  { id, heap,
    prog := prog (params.map fun (t, n, _) => (t, n)) ret body helpers,
    args := params.map fun (_, _, v) => v }

def ops : List (String × CmpOp) :=
  [("eq", .eq), ("ne", .ne), ("lt", .lt), ("le", .le), ("gt", .gt), ("ge", .ge)]

/-- Decimal against Decimal, every operator. -/
def decimalPairs : List (String × Value × Value) :=
  [("null_null", .null, .null), ("null_1", .null, d 1 0), ("1_null", d 1 0, .null),
   ("1_2", d 1 0, d 2 0), ("2_1", d 2 0, d 1 0), ("1_1", d 1 0, d 1 0),
   ("1.0_1.00", d 10 1, d 100 2), ("neg_0", d (-1) 2, d 0 0), ("0.00_0", d 0 2, d 0 0),
   ("big", d 123456789012345678 2, d 123456789012345679 2)]

def cmpVectors : List Vector :=
  ops.flatMap fun (name, op) =>
    (decimalPairs.map fun (pid, a, b) =>
      expr s!"cmp.{name}.dec.{pid}" [(tDec, "x", a), (tDec, "y", b)] tBool (.cmp op x y)) ++
    [expr s!"cmp.{name}.int.null" [(tInt, "x", .null)] tBool (.cmp op x (.lit (.int 1))),
     expr s!"cmp.{name}.int.1_2" [(tInt, "x", .int 1)] tBool (.cmp op x (.lit (.int 2))),
     expr s!"cmp.{name}.mixed.1_1.0" [(tInt, "x", .int 1), (tDec, "y", d 10 1)] tBool (.cmp op x y)]

def boolVals : List (String × Value) := [("t", .bool true), ("f", .bool false), ("n", .null)]

def boolVectors : List Vector :=
  let pairs := boolVals.flatMap fun (a, av) => boolVals.map fun (b, bv) => (a, av, b, bv)
  (pairs.flatMap fun (a, av, b, bv) =>
    let ps := [(tBool, "x", av), (tBool, "y", bv)]
    [expr s!"bool.and.{a}{b}" ps tBool (.and x y),
     expr s!"bool.or.{a}{b}" ps tBool (.or x y),
     expr s!"bool.eq.{a}{b}" ps tBool (.cmp .eq x y),
     expr s!"bool.ne.{a}{b}" ps tBool (.cmp .ne x y)]) ++
  (boolVals.map fun (a, av) => expr s!"bool.not.{a}" [(tBool, "x", av)] tBool (.not x)) ++
  (boolVals.map fun (a, av) =>
    stmts s!"if.then_else.{a}" [(tBool, "x", av)] (some tStr)
      [.ite x (.ret (some (.lit (.str "then")))) (some (.ret (some (.lit (.str "else")))))]) ++
  (boolVals.map fun (a, av) =>
    stmts s!"if.no_else.{a}" [(tBool, "x", av)] (some tStr)
      [.ite x (.ret (some (.lit (.str "then")))) none, .ret (some (.lit (.str "after")))]) ++
  -- Short-circuit: the right operand runs exactly when it must.
  (boolVals.flatMap fun (a, av) =>
    let right : Expr := .cmp .eq (markE "right") (.lit (.int 1))
    let ps := [(tBool, "x", av), (tOpp, "r", .ref 0)]
    [expr s!"bool.and.shortcircuit.{a}" ps tBool (.and x right) [opp] [markMethod],
     expr s!"bool.or.shortcircuit.{a}" ps tBool (.or x right) [opp] [markMethod]])

/-- Pairs compared with `==`. Includes the characters whose case mapping lands on ASCII. -/
def stringPairs : List (String × String × String) :=
  [("same", "abc", "abc"), ("case", "a", "A"), ("stage", "closed won", "Closed Won"),
   ("trailing_space", "a ", "a"), ("empty", "", ""), ("empty_a", "", "a"),
   ("e_acute", "\u00C9", "\u00E9"), ("sharp_ss", "\u00DF", "SS"), ("sharp_cap", "\u00DF", "\u1E9E"),
   ("long_s_s", "\u017F", "s"), ("long_s_S", "\u017F", "S"),
   ("kelvin_k", "\u212A", "k"), ("kelvin_K", "\u212A", "K"),
   ("dotless_I", "\u0131", "I"), ("dotless_i", "\u0131", "i"),
   ("dotted_i", "\u0130", "i"), ("dotted_I", "\u0130", "I"),
   ("sigma", "\u03C3", "\u03C2"), ("sigma_cap", "\u03A3", "\u03C2"),
   ("digraph", "\u01C5", "\u01C6"), ("ligature", "\uFB01", "FI"),
   ("deseret", "𐐀", "𐐨"), ("closed_long_s", "Clo\u017Fed Won", "Closed Won"),
   ("cyrillic_i", "\u0406d. Decision Makers", "Id. Decision Makers")]

def stringVectors : List Vector :=
  (stringPairs.flatMap fun (pid, a, b) =>
    let ps := [(tStr, "x", .str a), (tStr, "y", .str b)]
    [expr s!"str.eq.{pid}" ps tBool (.cmp .eq x y), expr s!"str.ne.{pid}" ps tBool (.cmp .ne x y)]) ++
  [expr "str.eq.null_a" [(tStr, "x", .null), (tStr, "y", .str "a")] tBool (.cmp .eq x y),
   expr "str.eq.a_null" [(tStr, "x", .str "a"), (tStr, "y", .null)] tBool (.cmp .eq x y),
   expr "str.ne.null_a" [(tStr, "x", .null), (tStr, "y", .str "a")] tBool (.cmp .ne x y),
   expr "str.eq.null_null" [(tStr, "x", .null), (tStr, "y", .null)] tBool (.cmp .eq x y),
   expr "str.eq.empty_null" [(tStr, "x", .str ""), (tStr, "y", .null)] tBool (.cmp .eq x y),
   expr "str.literal.quote" [] tStr (.lit (.str "it's \\ a\nline")),
   expr "str.literal.nonascii" [] tStr (.lit (.str "\u00C9𐐀"))]

def date1 : Value := .date ⟨2026, 1, 2⟩
def date2 : Value := .date ⟨2026, 1, 3⟩
def id1 : Value := .id "006000000000001AAA"
def id2 : Value := .id "006000000000002AAA"

def scalarVectors : List Vector :=
  [expr "date.eq.same" [(tDate, "x", date1), (tDate, "y", date1)] tBool (.cmp .eq x y),
   expr "date.eq.diff" [(tDate, "x", date1), (tDate, "y", date2)] tBool (.cmp .eq x y),
   expr "date.eq.null" [(tDate, "x", date1), (tDate, "y", .null)] tBool (.cmp .eq x y),
   expr "date.eq.null_null" [(tDate, "x", .null), (tDate, "y", .null)] tBool (.cmp .eq x y),
   expr "date.ret" [(tDate, "x", date1)] tDate x,
   expr "id.eq.same" [(tId, "x", id1), (tId, "y", id1)] tBool (.cmp .eq x y),
   expr "id.eq.diff" [(tId, "x", id1), (tId, "y", id2)] tBool (.cmp .eq x y),
   expr "id.eq.null" [(tId, "x", id1), (tId, "y", .null)] tBool (.cmp .eq x y),
   expr "lit.int" [] tInt (.lit (.int 10)),
   expr "lit.dec.scale" [] tDec (.lit (.dec ⟨110, 2⟩)),
   expr "lit.dec.small" [] tDec (.lit (.dec ⟨5, 3⟩)),
   expr "lit.dec.neg" [] tDec (.lit (.dec ⟨-125, 2⟩)),
   expr "lit.bool" [] tBool (.lit (.bool true)),
   expr "lit.null.dec" [] tDec (.lit .null),
   -- Widening: at a declaration, an assignment, a return, an argument.
   stmts "widen.decl" [] (some tDec) [.decl tDec "v" (some (.lit (.int 10))), .ret (some (.var "v"))],
   stmts "widen.assign" [] (some tDec)
     [.decl tDec "v" none, .assign "v" (.lit (.int 10)), .ret (some (.var "v"))],
   expr "widen.return" [] tDec (.lit (.int 10)),
   expr "widen.param" [(tDec, "x", .int 5)] tDec x,
   -- Locals.
   stmts "local.decl_no_init" [] (some tDec) [.decl tDec "v" none, .ret (some (.var "v"))],
   stmts "local.assign_null" [] (some tDec)
     [.decl tDec "v" (some (.lit (.int 1))), .assign "v" (.lit .null), .ret (some (.var "v"))],
   -- Blocks and returns.
   -- Behind a condition: Apex rejects a statement that follows an unconditional return.
   stmts "ret.void_early" [(tOpp, "r", .ref 0), (tBool, "x", .bool true)] none
     [.ite x (.ret none) none, .setField r "Name" (.lit (.str "unreached"))] [opp],
   stmts "ret.void_falls_off" [(tOpp, "r", .ref 0)] none
     [.setField r "Name" (.lit (.str "reached"))] [opp],
   stmts "ret.from_block" [(tBool, "x", .bool true)] (some tInt)
     [.block [.block [.ite x (.ret (some (.lit (.int 1)))) none], .ite x (.ret (some (.lit (.int 2)))) none],
      .ret (some (.lit (.int 3)))]]

def fieldVectors : List Vector :=
  [expr "field.read.unset" [(tOpp, "r", .ref 0)] tStr (.field r "StageName") [opp],
   expr "field.read.set" [(tOpp, "r", .ref 0)] tStr (.field r "StageName")
     [opp [("StageName", .str "x")]],
   expr "field.read.explicit_null" [(tOpp, "r", .ref 0)] tStr (.field r "StageName")
     [opp [("StageName", .null)]],
   expr "field.read.null_record" [(tOpp, "r", .null)] tStr (.field r "StageName"),
   expr "field.read.id" [(tOpp, "r", .ref 0)] tId (.field r "Id") [opp [("Id", id1)]],
   expr "field.read.closedate" [(tOpp, "r", .ref 0)] tDate (.field r "CloseDate")
     [opp [("CloseDate", date1)]],
   stmts "field.write.string" [(tOpp, "r", .ref 0)] none
     [.setField r "StageName" (.lit (.str "  spaced  "))] [opp],
   stmts "field.write.empty_string" [(tOpp, "r", .ref 0)] none
     [.setField r "StageName" (.lit (.str ""))] [opp],
   stmts "field.write.null_over_value" [(tOpp, "r", .ref 0)] none
     [.setField r "StageName" (.lit .null)] [opp [("StageName", .str "x")]],
   stmts "field.write.null_on_unset" [(tOpp, "r", .ref 0)] none
     [.setField r "StageName" (.lit .null)] [opp],
   stmts "field.write.widen_probability" [(tOpp, "r", .ref 0)] none
     [.setField r "Probability" (.lit (.int 10))] [opp],
   stmts "field.write.scale_kept_probability" [(tOpp, "r", .ref 0)] none
     [.setField r "Probability" (.lit (.dec ⟨33333, 3⟩))] [opp],
   stmts "field.write.scale_kept_amount" [(tOpp, "r", .ref 0)] none
     [.setField r "Amount" (.lit (.dec ⟨123456, 5⟩))] [opp],
   stmts "field.write.date" [(tOpp, "r", .ref 0), (tDate, "x", date1)] none
     [.setField r "CloseDate" x] [opp],
   stmts "field.write.null_record" [(tOpp, "r", .null)] none
     [.setField r "StageName" (.lit (.str "x"))],
   stmts "field.alias" [(tOpp, "r", .ref 0)] (some tStr)
     [.decl tOpp "other" (some r), .setField (.var "other") "Name" (.lit (.str "through alias")),
      .ret (some (.field r "Name"))] [opp],
   expr "sobject.eq.null" [(tOpp, "r", .ref 0)] tBool (.cmp .eq r (.lit .null)) [opp],
   expr "sobject.eq.null_null" [(tOpp, "r", .null)] tBool (.cmp .eq r (.lit .null)),
   expr "sobject.ne.null" [(tOpp, "r", .ref 0)] tBool (.cmp .ne r (.lit .null)) [opp],
   expr "sobject.ret.ref" [(tOpp, "r", .ref 1)] tOpp r [opp [("Name", .str "a")], opp]]

def mapVectors : List Vector :=
  let oppAt (fields : List (String × Value)) := opp fields
  [expr "map.get.hit" [(tOppMap, "x", .ref 1), (tId, "y", id1)] tOpp (.mapGet x y)
     [oppAt [("Name", .str "a")], .map [(id1, .ref 0)]],
   expr "map.get.missing" [(tOppMap, "x", .ref 1), (tId, "y", id2)] tOpp (.mapGet x y)
     [oppAt [], .map [(id1, .ref 0)]],
   expr "map.get.null_key" [(tOppMap, "x", .ref 1), (tId, "y", .null)] tOpp (.mapGet x y)
     [oppAt [], .map [(id1, .ref 0)]],
   expr "map.get.empty" [(tOppMap, "x", .ref 0), (tId, "y", id1)] tOpp (.mapGet x y) [.map []],
   expr "map.get.null_map" [(tOppMap, "x", .null), (tId, "y", id1)] tOpp (.mapGet x y),
   expr "map.get.string_key_case" [(.map tStr tOpp, "x", .ref 1), (tStr, "y", .str "A")] tOpp
     (.mapGet x y) [oppAt [], .map [(.str "a", .ref 0)]],
   expr "map.get.string_key_hit" [(.map tStr tOpp, "x", .ref 1), (tStr, "y", .str "a")] tOpp
     (.mapGet x y) [oppAt [], .map [(.str "a", .ref 0)]]]

/-- A loop writing `Name` on every element. -/
def writeNames : Stmt :=
  .forEach tOpp "o" x (.setField (.var "o") "Name" (.lit (.str "seen")))

def loopVectors : List Vector :=
  [stmts "for.null_list" [(tOpps, "x", .null)] none [writeNames],
   stmts "for.empty" [(tOpps, "x", .ref 0)] none [writeNames] [.list []],
   stmts "for.writes_each" [(tOpps, "x", .ref 2)] none [writeNames]
     [opp, opp, .list [.ref 0, .ref 1]],
   stmts "for.same_record_twice" [(tOpps, "x", .ref 1)] none [writeNames]
     [opp, .list [.ref 0, .ref 0]],
   -- A null element is bound without complaint and only raises when dereferenced, part way
   -- through: the earlier element's write remains.
   stmts "for.null_element_deref" [(tOpps, "x", .ref 1)] none [writeNames]
     [opp, .list [.ref 0, .null]],
   stmts "for.null_element_no_deref" [(tOpps, "x", .ref 0)] (some tStr)
     [.forEach tOpp "o" x (.block []), .ret (some (.lit (.str "done")))]
     [.list [.null, .null]],
   stmts "for.return_inside" [(tOpps, "x", .ref 2)] (some tStr)
     [.forEach tOpp "o" x (.block [.setField (.var "o") "Name" (.lit (.str "seen")),
        .ret (some (.lit (.str "early")))]),
      .ret (some (.lit (.str "late")))]
     [opp, opp, .list [.ref 0, .ref 1]],
   -- `T v;` inside a loop body resets to null on each iteration.
   stmts "for.redeclared_local" [(tOpps, "x", .ref 2)] none
     [.forEach tOpp "o" x (.block [
        .decl tStr "v" none,
        .ite (.cmp .eq (.var "v") (.lit .null)) (.setField (.var "o") "Name" (.lit (.str "fresh")))
          (some (.setField (.var "o") "Name" (.lit (.str "stale")))),
        .assign "v" (.lit (.str "set"))])]
     [opp, opp, .list [.ref 0, .ref 1]]]

def callVectors : List Vector :=
  let inner (name : String) (body : List Stmt) (ret : Option Ty) (ps : List (Ty × String)) : Method :=
    { name, params := ps, ret, body }
  [expr "call.args_left_to_right" [(tOpp, "r", .ref 0)] tBool
     (.call "T" "two" [markE "first", markE "second"]) [opp]
     [markMethod, inner "two" [.ret (some (.lit (.bool true)))] (some tBool)
        [(tDec, "a"), (tDec, "b")]],
   expr "call.static_frame_is_separate" [(tDec, "x", d 1 0)] tDec
     (.call "T" "other" [.lit (.int 2)])
     [] [inner "other" [.ret (some x)] (some tDec) [(tDec, "x")]],
   stmts "call.caller_locals_survive" [] (some tDec)
     [.decl tDec "v" (some (.lit (.int 1))),
      .decl tDec "w" (some (.call "T" "other" [])),
      .ret (some (.var "v"))]
     [] [inner "other" [.decl tDec "v" (some (.lit (.int 2))), .ret (some (.var "v"))] (some tDec) []],
   stmts "call.exception_propagates" [(tOpp, "r", .ref 0)] (some tStr)
     [.decl tStr "v" (some (.call "T" "boom" [])),
      .setField r "Name" (.lit (.str "unreached")),
      .ret (some (.var "v"))] [opp]
     [inner "boom" [.decl tOpp "n" none, .ret (some (.field (.var "n") "Name"))] (some tStr) []],
   stmts "call.write_before_exception_kept" [(tOpp, "r", .ref 0)] none
     [.decl tDec "v" (some (.call "T" "writeThenBoom" [r]))] [opp]
     [inner "writeThenBoom"
        [.setField (.var "t") "Name" (.lit (.str "kept")), .decl tOpp "n" none,
         .ret (some (.field (.var "n") "Amount"))] (some tDec) [(tOpp, "t")]]]

/-- When is an operand evaluated relative to the null check it might fail? -/
def orderVectors : List Vector :=
  let nullR := (tOpp, "n", Value.null)
  let n : Expr := .var "n"
  let logR := (tOpp, "r", Value.ref 0)
  [stmts "order.null_setfield_rhs" [nullR, logR] none [.setField n "Amount" (markE "rhs")] [opp]
     [markMethod],
   stmts "order.null_adderror_msg" [nullR, logR] none
     [.addError n (.call "T" "markMsg" [r])] [opp] [markMsgMethod],
   expr "order.cmp_left_then_null" [(tDec, "x", .null), logR] tBool (.cmp .lt (markE "l") x) [opp]
     [markMethod],
   expr "order.cmp_null_then_right" [(tDec, "x", .null), logR] tBool (.cmp .lt x (markE "r")) [opp]
     [markMethod],
   expr "order.cmp_left_to_right" [logR] tBool (.cmp .lt (markE "a") (markE "b")) [opp] [markMethod],
   stmts "order.mapget_null_map_key" [(tOppMap, "x", .null), logR] (some tOpp)
     [.ret (some (.mapGet x (.call "T" "markId" [r])))] [opp]
     [{ name := "markId", params := [(tOpp, "t")], ret := some tId,
        body := [.setField (.var "t") "Description" (.lit (.str "evaluated")),
                 .ret (some (.lit .null))] }]]

def errorVectors : List Vector :=
  let e1 (s : String) : Expr := .lit (.str s)
  let rp := (tOpp, "r", Value.ref 0)
  [stmts "adderror.once" [rp] none [.addError r (e1 "one")] [opp],
   stmts "adderror.twice_same" [rp] none [.addError r (e1 "same"), .addError r (e1 "same")] [opp],
   stmts "adderror.twice_case" [rp] none [.addError r (e1 "Same"), .addError r (e1 "same")] [opp],
   stmts "adderror.last_wins" [rp] none
     [.addError r (e1 "one"), .addError r (e1 "two"), .addError r (e1 "three")] [opp],
   stmts "adderror.continues" [rp] none [.addError r (e1 "m"), .setField r "Name" (e1 "after")] [opp],
   stmts "adderror.over_existing" [rp] none [.addError r (e1 "new")] [opp [] (some "old")],
   stmts "adderror.null_record" [(tOpp, "r", .null)] none [.addError r (e1 "m")],
   stmts "adderror.two_records" [rp, (tOpp, "t", .ref 1)] none
     [.addError r (e1 "a"), .addError (.var "t") (e1 "b")] [opp, opp]]

def catalog : List Vector :=
  cmpVectors ++ boolVectors ++ stringVectors ++ scalarVectors ++ fieldVectors ++ mapVectors ++
    loopVectors ++ callVectors ++ orderVectors ++ errorVectors

end Difftest
