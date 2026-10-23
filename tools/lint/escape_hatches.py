#!/usr/bin/env python3
"""Escape-hatch lint for the Lean sources (ADR 0002). Trusted base: docs/trusted-base.md §6.

The axiom checker (`lake exe axiomcheck`) only sees what a theorem actually depends on. This lint
is the second layer: it rejects escape hatches anywhere in the checked sources, including code no
theorem depends on yet. Comments and string literals are stripped first, so prose that mentions
`sorry` is fine.

    python3 tools/lint/escape_hatches.py            # lint lean/
    python3 tools/lint/escape_hatches.py --self-test
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

REPO = Path(__file__).resolve().parents[2]
LEAN = REPO / "lean"

# Checked sources, relative to lean/. Test fixtures (lean/test/) and the checker itself are out of
# scope: the fixtures are deliberately full of escape hatches.
SCOPES = ["ApexVerify", "ApexVerify.lean", "Spec", "Spec.lean", "Proofs", "Proofs.lean",
          "Subjects", "Subjects.lean"]

AXIOMS_FILE = "ApexVerify/Semantics/Axioms.lean"

# Code that is executed by difftest or states what is proven: it must be total and transparent.
TRUSTED_EXECUTABLE = ("ApexVerify/Syntax", "ApexVerify/Semantics", "ApexVerify/Platform",
                      "Subjects", "Spec")


@dataclass(frozen=True)
class Rule:
    pattern: str
    message: str
    applies: Callable[[str], bool]  # relative path under lean/ -> does the rule apply?


def everywhere(_: str) -> bool:
    return True


def under(*prefixes: str):
    return lambda rel: any(rel == p or rel.startswith(p + "/") or rel == p + ".lean"
                           for p in prefixes)


RULES = [
    Rule(r"\bsorry\b", "`sorry` leaves a proof unfinished", everywhere),
    Rule(r"\badmit\b", "`admit` leaves a proof unfinished", everywhere),
    Rule(r"\bnative_decide\b", "`native_decide` trusts the compiler", everywhere),
    Rule(r"\bbv_decide\b", "`bv_decide` trusts the compiler", everywhere),
    Rule(r"\bofReduce(Bool|Nat)\b", "`Lean.ofReduceBool/Nat` trusts the compiler", everywhere),
    Rule(r"\btrustCompiler\b", "`Lean.trustCompiler` trusts the compiler", everywhere),
    Rule(r"\bimplemented_by\b", "`implemented_by` makes compiled code differ from kernel code",
         everywhere),
    Rule(r"\bextern\b", "`extern` makes compiled code differ from kernel code", everywhere),
    Rule(r"\bskipKernelTC\b", "`debug.skipKernelTC` disables the kernel", everywhere),
    Rule(r"\baxiom\b", f"new axioms belong only in lean/{AXIOMS_FILE}",
         lambda rel: rel != AXIOMS_FILE),
    Rule(r"\bpartial\b", "trusted executable code must be total (`partial` is opaque to the kernel)",
         under(*TRUSTED_EXECUTABLE)),
    Rule(r"\bunsafe\b", "trusted executable code must not be `unsafe`", under(*TRUSTED_EXECUTABLE)),
    Rule(r"\bopaque\b", "trusted executable code must not be `opaque`", under(*TRUSTED_EXECUTABLE)),
    # A reviewer reads Spec/ as plain statements. Local notation, macros or instances could make
    # a statement read differently from what it means; such things belong in trusted modules.
    Rule(r"#eval\b|\brun_cmd\b|\brun_elab\b|\brun_meta\b|\bmacro(_rules)?\b|\bsyntax\b"
         r"|\belab(_rules)?\b|\bnotation\b|\binfix[lr]?\b|\bprefix\b|\bpostfix\b"
         r"|\binstance\b|\battribute\b",
         "spec files hold plain statements: no meta-code, notation, macros, instances or "
         "attributes (put those in trusted ApexVerify modules)", under("Spec")),
]


def strip_comments_and_strings(src: str) -> str:
    """Blank out comments (`--`, nested `/- -/`, doc comments) and string literals, keeping
    newlines so that line numbers stay correct."""
    out: list[str] = []
    i, n, depth = 0, len(src), 0
    while i < n:
        c = src[i]
        two = src[i:i + 2]
        if depth > 0:
            if two == "/-":
                depth += 1; out.append("  "); i += 2
            elif two == "-/":
                depth -= 1; out.append("  "); i += 2
            else:
                out.append("\n" if c == "\n" else " "); i += 1
        elif two == "/-":
            depth = 1; out.append("  "); i += 2
        elif two == "--":
            while i < n and src[i] != "\n":
                out.append(" "); i += 1
        elif c == '"':
            out.append(" "); i += 1
            while i < n and src[i] != '"':
                if src[i] == "\\" and i + 1 < n:
                    out.append("  "); i += 2
                else:
                    out.append("\n" if src[i] == "\n" else " "); i += 1
            out.append(" "); i += 1
        else:
            out.append(c); i += 1
    return "".join(out)


def lint_text(rel: str, src: str) -> list[str]:
    code = strip_comments_and_strings(src)
    problems = []
    for lineno, line in enumerate(code.splitlines(), start=1):
        for rule in RULES:
            if rule.applies(rel) and re.search(rule.pattern, line):
                problems.append(f"lean/{rel}:{lineno}: {rule.message}")
    return problems


def files_in_scope() -> list[Path]:
    files: list[Path] = []
    for scope in SCOPES:
        p = LEAN / scope
        if p.is_file():
            files.append(p)
        elif p.is_dir():
            files.extend(sorted(p.rglob("*.lean")))
    return files


def self_test() -> int:
    sem = "ApexVerify/Semantics/Eval.lean"
    cases = [
        ("Proofs/A.lean", "theorem t : 1 = 1 := by sorry", 1),
        ("Proofs/A.lean", "-- sorry, not yet\ntheorem t : 1 = 1 := rfl", 0),
        ("Proofs/A.lean", "/- outer /- nested sorry -/ still comment -/ def x := 1", 0),
        ("Proofs/A.lean", '/-- doc: uses native_decide? no. -/\ndef s := "sorry admit axiom"', 0),
        ("Proofs/A.lean", "theorem t : 2 + 2 = 4 := by native_decide", 1),
        ("Proofs/A.lean", "axiom cheat : False", 1),
        (AXIOMS_FILE, "axiom platformFact : True", 0),
        ("Proofs/A.lean", "partial def f (n : Nat) : Nat := f n", 0),
        (sem, "partial def f (n : Nat) : Nat := f n", 1),
        (sem, "@[implemented_by g] def f := 1", 1),
        ("Spec/A.lean", "#eval 1", 1),
        ("Spec/A.lean", 'local notation "ClosedWon" => True', 1),
        ("Spec/A.lean", "local instance : BEq String := ⟨fun _ _ => true⟩", 1),
        ("Proofs/A.lean", "instance : Inhabited Nat := ⟨0⟩", 0),
        ("Spec/A.lean", "def P (s : String) : Prop := s.isPrefixOf \"Closed\"", 0),
        ("Proofs/A.lean", "set_option debug.skipKernelTC true in", 1),
        ("Proofs/A.lean", "theorem sorryFree : True := trivial", 0),  # word boundary
        ("Proofs/A.lean", "def s := \"a \\\" sorry\"\ntheorem t : True := trivial", 0),
    ]
    failed = 0
    for rel, src, want in cases:
        got = len(lint_text(rel, src))
        if got != want:
            failed += 1
            print(f"FAIL self-test {rel!r} {src!r}: {got} finding(s), expected {want}")
    print(f"escape-hatch lint self-test: {len(cases) - failed}/{len(cases)} passed")
    return 1 if failed else 0


def main(argv: list[str]) -> int:
    if argv[1:] == ["--self-test"]:
        return self_test()
    problems = []
    files = files_in_scope()
    for f in files:
        problems += lint_text(f.relative_to(LEAN).as_posix(), f.read_text(encoding="utf-8"))
    for p in problems:
        print(p)
    print(f"escape-hatch lint: {len(files)} file(s), {len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
