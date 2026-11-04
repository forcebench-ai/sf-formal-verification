import SfVerify.Apex.Syntax.Ast

/-!
# Pretty-printing the subset back to Apex

**Trusted base** (`docs/trusted-base.md` §2). Difftest runs what this prints, so a term's meaning in
the org is the meaning of this text; the exporter's round trip (milestone 3) checks the same text.
It lives here so that both cover the exact term the proofs use.

The output is fully parenthesised rather than minimal, so the printer doesn't have to know Apex's
precedence table: a parenthesis in the output is never a change of meaning.
-/

namespace SfVerify.Apex

open SfVerify.Platform

def _root_.SfVerify.Platform.PrimTy.apexName : PrimTy → String
  | .boolean => "Boolean"
  | .integer => "Integer"
  | .decimal => "Decimal"
  | .string => "String"
  | .date => "Date"
  | .id => "Id"

def Ty.apex : Ty → String
  | .prim p => p.apexName
  | .sobject n => n
  | .list t => s!"List<{t.apex}>"
  | .map k v => s!"Map<{k.apex}, {v.apex}>"

/-- A four-digit hexadecimal escape. -/
def unicodeEscape (unit : Nat) : String :=
  let digit (d : Nat) : Char := if d < 10 then Char.ofNat (48 + d) else Char.ofNat (87 + d)
  String.ofList ['\\', 'u', digit (unit / 4096 % 16), digit (unit / 256 % 16),
    digit (unit / 16 % 16), digit (unit % 16)]

/-- One character inside an Apex string literal. Everything outside printable ASCII is escaped, so
the file's encoding can't change a test's meaning. -/
def escapeChar (c : Char) : String :=
  let n := c.toNat
  if c == '\'' then "\\'"
  else if c == '\\' then "\\\\"
  else if c == '\n' then "\\n"
  else if 32 ≤ n ∧ n < 127 then String.singleton c
  else if n < 0x10000 then unicodeEscape n
  else
    let v := n - 0x10000
    unicodeEscape (0xD800 + v / 1024) ++ unicodeEscape (0xDC00 + v % 1024)

def stringLiteral (s : String) : String :=
  "'" ++ String.join (s.toList.map escapeChar) ++ "'"

/-- `unscaled / 10 ^ scale` in plain notation, keeping the scale: `⟨110, 2⟩` prints as `1.10`. -/
def _root_.SfVerify.Platform.Decimal.plain (d : Decimal) : String :=
  let digits := toString d.unscaled.natAbs
  let sign := if d.unscaled < 0 then "-" else ""
  if d.scale = 0 then sign ++ digits
  else
    let padded := String.ofList (List.replicate (d.scale + 1 - digits.length) '0') ++ digits
    let whole := padded.toList.take (padded.length - d.scale)
    let frac := padded.toList.drop (padded.length - d.scale)
    sign ++ String.ofList whole ++ "." ++ String.ofList frac

def Lit.apex : Lit → String
  | .null => "null"
  | .bool b => if b then "true" else "false"
  | .int i => if i < 0 then s!"({i})" else toString i
  | .dec d => if d.unscaled < 0 then s!"({d.plain})" else d.plain
  | .str s => stringLiteral s

def CmpOp.apex : CmpOp → String
  | .eq => "=="
  | .ne => "!="
  | .lt => "<"
  | .le => "<="
  | .gt => ">"
  | .ge => ">="

/-- How a static call is spelt. `C.m` in a class; a script flattens it, because anonymous Apex can't
declare classes with static methods. -/
abbrev CallName := String → String → String

def dottedCall : CallName := fun c m => s!"{c}.{m}"

mutual

def Expr.apex (q : CallName) : Expr → String
  | .lit l => l.apex
  | .var x => x
  | .field t f => s!"{t.apex q}.{f}"
  | .cmp op l r => s!"({l.apex q} {op.apex} {r.apex q})"
  | .and l r => s!"({l.apex q} && {r.apex q})"
  | .or l r => s!"({l.apex q} || {r.apex q})"
  | .not e => s!"(!{e.apex q})"
  | .call c m args => s!"{q c m}({Expr.apexArgs q args})"
  | .mapGet m k => s!"{m.apex q}.get({k.apex q})"

def Expr.apexArgs (q : CallName) : List Expr → String
  | [] => ""
  | [e] => e.apex q
  | e :: es => s!"{e.apex q}, {Expr.apexArgs q es}"

end

mutual

def Stmt.apex (q : CallName) (ind : String) : Stmt → String
  | .decl t x none => s!"{ind}{t.apex} {x};\n"
  | .decl t x (some e) => s!"{ind}{t.apex} {x} = {e.apex q};\n"
  | .assign x e => s!"{ind}{x} = {e.apex q};\n"
  | .setField t f e => s!"{ind}{t.apex q}.{f} = {e.apex q};\n"
  | .ite c t none => s!"{ind}if ({c.apex q})\n{t.apex q (ind ++ "  ")}"
  | .ite c t (some e) =>
    s!"{ind}if ({c.apex q})\n{t.apex q (ind ++ "  ")}{ind}else\n{e.apex q (ind ++ "  ")}"
  | .forEach t x c b => s!"{ind}for ({t.apex} {x} : {c.apex q})\n{b.apex q (ind ++ "  ")}"
  | .block b => s!"{ind}\{\n{Stmt.apexList q (ind ++ "  ") b}{ind}}\n"
  | .ret none => s!"{ind}return;\n"
  | .ret (some e) => s!"{ind}return {e.apex q};\n"
  | .addError t m => s!"{ind}{t.apex q}.addError({m.apex q});\n"

def Stmt.apexList (q : CallName) (ind : String) : List Stmt → String
  | [] => ""
  | s :: ss => s.apex q ind ++ Stmt.apexList q ind ss

end

def Method.signature (m : Method) (name : String) : String :=
  let params := ", ".intercalate (m.params.map fun (t, x) => s!"{t.apex} {x}")
  let ret := match m.ret with
    | some t => t.apex
    | none => "void"
  s!"{ret} {name}({params})"

end SfVerify.Apex
