/-!
# String equality

**Trusted base** (`docs/trusted-base.md` §3). Apex `==` and `!=` on Strings ignore case; `Map` keys
and `String.equals` do not. How far "ignore case" reaches beyond ASCII is settled against the
reference org by `tools/difftest/probes/semantics.apex` and recorded in `docs/platform-model.md`.
-/

namespace SfVerify.Platform

/-- The code point a character is compared as under `==`. ASCII letters fold to lower case, and so
do the non-ASCII characters whose case mapping lands on an ASCII letter, because those can make a
non-ASCII string equal a stage name written in ASCII. Every other character compares exactly: that
is a named simplification (`docs/platform-model.md`, Values). -/
def foldCodePoint (c : Nat) : Nat :=
  if 65 ≤ c ∧ c ≤ 90 then c + 32
  else if c = 0x17F then 0x73   -- long s → s
  else if c = 0x212A then 0x6B  -- Kelvin sign → k
  else if c = 0x131 then 0x69   -- dotless i → i
  else if c = 0x130 then 0x69   -- dotted capital I → i
  else c

/-- Apex `==` on two non-null Strings. -/
def stringEq (a b : String) : Bool :=
  a.toList.map (fun c => foldCodePoint c.toNat) == b.toList.map (fun c => foldCodePoint c.toNat)

end SfVerify.Platform
