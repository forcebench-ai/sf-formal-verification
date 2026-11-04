#!/usr/bin/env python3
"""Run difftest batches in the reference org, then compare (tools/difftest/README.md).

    run.py [--dir DIR] [--org sfv-dev] [--api-version 68.0]
    run.py --self-test

Only ever target the dedicated reference org (ADR 0003). Exit 0: agree, 1: mismatches, 2: the run
itself is invalid. A failed script is never treated as a pass: every vector catches its own
exceptions, so a script-level failure means the batch didn't run as designed.
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Callable

sys.path.insert(0, str(Path(__file__).resolve().parent))
from compare import compare  # noqa: E402


class InvalidRun(Exception):
    pass


def sf_apex_run(path: Path, org: str, api_version: str) -> str:
    done = subprocess.run(
        ["sf", "apex", "run", "--target-org", org, "--api-version", api_version,
         "--file", str(path), "--json"],
        capture_output=True, text=True, env={**os.environ, "SF_DISABLE_LOG_FILE": "true"})
    return done.stdout


def parse_logs(logs: str, batch: str) -> tuple[list[dict], list[dict]]:
    """The SFVDT results and SFVMETA objects in one batch's debug log."""
    results, meta = [], []
    for line in logs.splitlines():
        if "|USER_DEBUG|" not in line:
            continue
        for marker, into in (("SFVDT ", results), ("SFVMETA ", meta)):
            at = line.find(marker)
            if at >= 0:
                try:
                    into.append(json.loads(line[at + len(marker):]))
                except json.JSONDecodeError as e:
                    raise InvalidRun(f"{batch}: unparseable {marker.strip()} line "
                                     f"(truncated log?): {e}") from e
                break
    return results, meta


def run_batch(path: Path, invoke: Callable[[Path], str]) -> tuple[list[dict], list[dict], str]:
    stdout = invoke(path)
    try:
        reply = json.loads(stdout)
    except json.JSONDecodeError:
        # Deliberately not echoed: unparsed CLI output could hold anything.
        raise InvalidRun(f"{path.name}: sf did not return JSON") from None
    result = reply.get("result")
    if not isinstance(result, dict):
        raise InvalidRun(f"{path.name}: sf error: status {reply.get('status')}: {reply.get('message')}")
    if not result.get("compiled"):
        raise InvalidRun(f"{path.name}: did not compile: line {result.get('line')}, "
                         f"column {result.get('column')}: {result.get('compileProblem')}")
    if not result.get("success"):
        raise InvalidRun(f"{path.name}: script failed: {result.get('exceptionMessage')}")
    logs = result.get("logs") or ""
    results, meta = parse_logs(logs, path.name)
    return results, meta, logs


def run_all(directory: Path, org: str, api_version: str, invoke: Callable[[Path], str]) -> int:
    batches = sorted(directory.glob("batch-*.apex"))
    if not batches:
        raise InvalidRun(f"{directory}: no batches; run `lake exe difftest` first")
    log_dir = directory / "logs"
    log_dir.mkdir(exist_ok=True)
    all_results, all_meta = [], []
    for path in batches:
        results, meta, logs = run_batch(path, invoke)
        (log_dir / f"{path.stem}.log").write_text(logs, encoding="utf-8")
        all_results += results
        all_meta += meta
        print(f"{path.name}: {len(results)} results")
    with (directory / "org-results.jsonl").open("w", encoding="utf-8") as out:
        for row in all_results:
            out.write(json.dumps(row, ensure_ascii=False) + "\n")
    (directory / "run-meta.json").write_text(json.dumps({
        "org": org, "apiVersion": api_version, "batches": len(batches),
        "utc": datetime.datetime.now(datetime.timezone.utc).isoformat(), "orgInfo": all_meta[:1],
    }, indent=2) + "\n")
    return compare(directory)


def self_test() -> int:
    good = json.dumps({"id": "v", "outcome": {"kind": "normal", "ret": None}, "heap": []})
    log_ok = f"12:00|USER_DEBUG|[1]|DEBUG|SFVMETA {{\"instance\":\"X\"}}\n12:00|USER_DEBUG|[2]|DEBUG|SFVDT {good}\n"

    def reply(**result):
        return lambda _: json.dumps({"status": 0, "result": result})

    ok = reply(compiled=True, success=True, logs=log_ok)
    cases = [
        ("good batch", ok, None),
        ("compile failure", reply(compiled=False, compileProblem="bad", line=1, column=1), "compile"),
        ("script failure", reply(compiled=True, success=False, exceptionMessage="boom"), "failed"),
        ("unparseable marker",
         reply(compiled=True, success=True, logs="|USER_DEBUG|[1]|DEBUG|SFVDT {cut"), "unparseable"),
        ("sf error", lambda _: json.dumps({"status": 1, "message": "no org"}), "no org"),
        ("not json", lambda _: "access-token-like text", "did not return JSON"),
    ]
    failures = 0
    for name, invoke, want in cases:
        with tempfile.TemporaryDirectory() as t:
            d = Path(t)
            (d / "batch-0001.apex").write_text("// x")
            (d / "expected.jsonl").write_text(good + "\n")
            try:
                sink, sys.stdout = sys.stdout, open(os.devnull, "w")
                try:
                    code = run_all(d, "o", "68.0", invoke)
                finally:
                    sys.stdout.close()
                    sys.stdout = sink
                if want is not None or code != 0:
                    failures += 1
                    print(f"FAIL {name}: exit {code}")
                elif (d / "run-meta.json").exists() is False:
                    failures += 1
                    print(f"FAIL {name}: no run-meta.json")
            except InvalidRun as e:
                if want is None or want not in str(e) or "access-token" in str(e):
                    failures += 1
                    print(f"FAIL {name}: {e}")
    print(f"run self-test: {len(cases) - failures}/{len(cases)} passed")
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dir", type=Path, default=Path("out"))
    parser.add_argument("--org", default="sfv-dev")
    parser.add_argument("--api-version", default="68.0")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    try:
        return run_all(args.dir, args.org, args.api_version,
                       lambda path: sf_apex_run(path, args.org, args.api_version))
    except InvalidRun as e:
        print(f"difftest: invalid run: {e}")
        return 2


if __name__ == "__main__":
    sys.exit(main())
