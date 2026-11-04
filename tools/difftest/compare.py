#!/usr/bin/env python3
"""Compare the Lean interpreter's results with the reference org's (tools/difftest/README.md).

    compare.py [--dir DIR]    exit 0: agree, 1: mismatches, 2: the run itself is invalid
    compare.py --self-test

Any mismatch is a bug in the Lean model. Decimals compare by value. A scale difference is reported
but isn't a failure, because the model doesn't claim to track scale through every operation.
"""

from __future__ import annotations

import argparse
import decimal
import json
import sys
import tempfile
from pathlib import Path

DEC = decimal.Context(prec=200)


class InvalidRun(Exception):
    pass


def load(path: Path) -> dict[str, dict]:
    if not path.exists():
        raise InvalidRun(f"{path}: missing")
    results: dict[str, dict] = {}
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        try:
            row = json.loads(line)
            vector_id = row["id"]
        except (json.JSONDecodeError, KeyError, TypeError) as e:
            raise InvalidRun(f"{path}:{number}: malformed result: {e}") from e
        if vector_id in results:
            raise InvalidRun(f"{path}:{number}: duplicate vector id {vector_id}")
        results[vector_id] = row
    return results


def compare_value(path: str, lean, org, problems: list, notes: list) -> None:
    if isinstance(lean, dict) and isinstance(org, dict) and "dec" in lean and "dec" in org:
        a, b = DEC.create_decimal(lean["dec"]), DEC.create_decimal(org["dec"])
        if a != b:
            problems.append((path, lean, org))
        elif lean["dec"] != org["dec"]:
            notes.append((path, lean["dec"], org["dec"]))
    elif lean != org:
        problems.append((path, lean, org))


def compare_vector(lean: dict, org: dict, problems: list, notes: list) -> None:
    lean_outcome, org_outcome = lean.get("outcome", {}), org.get("outcome", {})
    kind = lean_outcome.get("kind")
    if kind in ("unsupported", "outOfFuel"):
        problems.append(("outcome.kind", f"{kind}: {lean_outcome.get('why', '')}", org_outcome))
        return
    if kind != org_outcome.get("kind"):
        problems.append(("outcome", lean_outcome, org_outcome))
    elif kind == "exception":
        if lean_outcome.get("type") != org_outcome.get("type"):
            problems.append(("outcome.type", lean_outcome.get("type"), org_outcome.get("type")))
    else:
        compare_value("outcome.ret", lean_outcome.get("ret"), org_outcome.get("ret"), problems, notes)

    lean_heap, org_heap = lean.get("heap", []), org.get("heap", [])
    if len(lean_heap) != len(org_heap):
        problems.append(("heap.length", len(lean_heap), len(org_heap)))
        return
    for i, (a, b) in enumerate(zip(lean_heap, org_heap)):
        if a.get("error") != b.get("error"):
            problems.append((f"heap[{i}].error", a.get("error"), b.get("error")))
        lean_fields, org_fields = a.get("fields", {}), b.get("fields", {})
        for field in sorted(set(lean_fields) | set(org_fields)):
            path = f"heap[{i}].fields.{field}"
            if field not in lean_fields:
                problems.append((path, "<not populated>", org_fields[field]))
            elif field not in org_fields:
                problems.append((path, lean_fields[field], "<not populated>"))
            else:
                compare_value(path, lean_fields[field], org_fields[field], problems, notes)


def compare(directory: Path, out=None) -> int:
    """Print the report and return the exit code."""
    out = out or sys.stdout
    try:
        expected = load(directory / "expected.jsonl")
        actual = load(directory / "org-results.jsonl")
    except InvalidRun as e:
        print(f"difftest: invalid run: {e}", file=out)
        return 2
    if not expected:
        print("difftest: invalid run: no vectors (an empty run must not look like a pass)", file=out)
        return 2

    mismatches = 0
    scale_notes = []
    for vector_id, lean in expected.items():
        problems: list = []
        notes: list = []
        if vector_id not in actual:
            problems.append(("<vector>", "present", "<missing from org results>"))
        else:
            compare_vector(lean, actual[vector_id], problems, notes)
        scale_notes += [(vector_id, *n) for n in notes]
        for path, a, b in problems:
            mismatches += 1
            print(f"MISMATCH {vector_id} {path}\n  lean: {json.dumps(a, ensure_ascii=False)}"
                  f"\n  org:  {json.dumps(b, ensure_ascii=False)}", file=out)
    for vector_id in actual.keys() - expected.keys():
        mismatches += 1
        print(f"MISMATCH {vector_id} <vector>\n  lean: <missing>\n  org:  present", file=out)
    if scale_notes:
        print("scale differences (not failures):", file=out)
        for vector_id, path, a, b in scale_notes:
            print(f"  {vector_id} {path}: lean {a}, org {b}", file=out)
    print(f"difftest: {len(expected)} vectors, {mismatches} mismatches, "
          f"{len(scale_notes)} scale notes", file=out)
    return 1 if mismatches else 0


def self_test() -> int:
    class Sink:
        def write(self, _):
            pass

    def row(ret=None, fields=None, error=None, vector="v", kind="normal", **extra):
        outcome = {"kind": kind, **extra}
        if kind == "normal":
            outcome["ret"] = ret
        return {"id": vector, "outcome": outcome, "heap": [{"fields": fields or {}, "error": error}]}

    npe = {"kind": "exception", "type": "System.NullPointerException"}
    dec = {"dec": "1.0"}
    cases = [
        ("exact match", [row(dec)], [row(dec)], 0),
        ("dec by value", [row({"dec": "1.0"})], [row({"dec": "1.00"})], 0),
        ("dec differs", [row({"dec": "1.0"})], [row({"dec": "1.1"})], 1),
        ("dec beyond float precision",
         [row({"dec": "1234567890123456789.01"})], [row({"dec": "1234567890123456789.02"})], 1),
        ("int vs dec", [row({"int": "1"})], [row({"dec": "1"})], 1),
        ("field order", [row(fields={"A": {"str": "x"}, "B": None})],
         [row(fields={"B": None, "A": {"str": "x"}})], 0),
        ("missing field", [row(fields={"A": None})], [row()], 1),
        ("extra field", [row()], [row(fields={"A": None})], 1),
        ("error case", [row(error="m")], [row(error="M")], 1),
        ("string case", [row({"str": "a"})], [row({"str": "A"})], 1),
        ("missing vector", [row(), row(vector="w")], [row()], 1),
        ("extra vector", [row()], [row(), row(vector="w")], 1),
        ("duplicate id", [row(), row()], [row()], 2),
        ("unsupported", [row(kind="unsupported", why="x")], [row()], 1),
        ("out of fuel", [row(kind="outOfFuel")], [row()], 1),
        ("kind differs", [{"id": "v", "outcome": npe, "heap": []}],
         [{"id": "v", "outcome": {"kind": "normal", "ret": None}, "heap": []}], 1),
        ("exception type", [{"id": "v", "outcome": npe, "heap": []}],
         [{"id": "v", "outcome": {"kind": "exception", "type": "System.ListException"}, "heap": []}], 1),
        ("heap length", [{"id": "v", "outcome": npe, "heap": []}],
         [{"id": "v", "outcome": npe, "heap": [{"fields": {}, "error": None}]}], 1),
        ("empty expected", [], [], 2),
    ]
    failures = 0
    for name, lean, org, want in cases:
        with tempfile.TemporaryDirectory() as t:
            d = Path(t)
            (d / "expected.jsonl").write_text("".join(json.dumps(r) + "\n" for r in lean))
            (d / "org-results.jsonl").write_text("".join(json.dumps(r) + "\n" for r in org))
            got = compare(d, Sink())
        if got != want:
            failures += 1
            print(f"FAIL {name}: exit {got}, wanted {want}")
    with tempfile.TemporaryDirectory() as t:
        d = Path(t)
        (d / "expected.jsonl").write_text("{not json\n")
        (d / "org-results.jsonl").write_text("")
        if compare(d, Sink()) != 2:
            failures += 1
            print("FAIL malformed line")
    print(f"compare self-test: {len(cases) + 1 - failures}/{len(cases) + 1} passed")
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dir", type=Path, default=Path("out"))
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    return self_test() if args.self_test else compare(args.dir)


if __name__ == "__main__":
    sys.exit(main())
