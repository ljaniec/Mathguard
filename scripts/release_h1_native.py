#!/usr/bin/env python3
"""Native (compiled) cases for H1, run against the real `mathguard-worker` binary.

The execute/preview command lines are produced by the Lean encoders `executeJson` and
`previewJson` (see scripts/release/H1Commands.lean), so the bytes sent to the worker are
exactly the ones the H1 theorems talk about. Contexts both without an approval (`null`)
and with one are exercised.

This is a runtime test of the compiled worker, not a proof. Prerequisites:
    lake build MathguardRelease mathguard-worker
Run:
    python3 scripts/release_h1_native.py
"""
from __future__ import annotations

import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
WORKER = ROOT / ".lake" / "build" / "bin" / "mathguard-worker"

CONTROLS = {
    "strictness": "strict", "allowedModels": [1], "allowedTools": [1],
    "irreversibleTools": [], "pinnedArtifacts": [], "signatures": [],
    "piiRedactAt": 50, "piiBlockAt": 90, "semReviewAt": 50, "semBlockAt": 90,
    "maxSteps": 10,
}


def configure(epoch: int, calls: int) -> str:
    return json.dumps({
        "op": "configure", "epoch": epoch, "limit": [0, 0, 0, calls],
        "maxTransfer": 50000, "approvalThreshold": 10000, "controls": CONTROLS,
    })


RESERVE_PROBE = json.dumps({"op": "reserve", "bound": [0, 0, 0, 0]})


def lean_commands() -> dict[str, str]:
    out = subprocess.run(
        ["lake", "env", "lean", "scripts/release/H1Commands.lean"],
        cwd=ROOT, check=True, capture_output=True, text=True).stdout
    commands = {}
    for line in out.splitlines():
        key, _, rest = line.partition(" ")
        commands[key] = rest
    return commands


def run_worker(lines: list[str]) -> list[dict]:
    proc = subprocess.run(
        [str(WORKER)], input="\n".join(lines) + "\n", cwd=ROOT,
        check=True, capture_output=True, text=True)
    return [json.loads(line) for line in proc.stdout.splitlines()]


failures: list[str] = []


def check(cond: bool, message: str) -> None:
    print(("PASS " if cond else "FAIL ") + message)
    if not cond:
        failures.append(message)


def main() -> int:
    cmd = lean_commands()
    # Uninitialized worker: rejected with the fixed error frame, no state.
    [r] = run_worker([cmd["EXECUTE"]])
    check(r == {"error": "WORKER_REQUEST_REJECTED"}, "uninitialized execute is rejected")

    # Session A: two tool-call slots.
    rs = run_worker([
        configure(7, 2),
        cmd["PREVIEW"],
        cmd["EXECUTE"],
        configure(8, 2),           # later policy epoch
        cmd["REPLAY"],             # exact retry, expired approval, late clock
        cmd["CONFLICT"],           # same id, changed amount
        RESERVE_PROBE,             # reveals the next ticket counter
    ])
    _, preview, commit, _, replay, conflict, probe = rs
    st0 = preview["state"]
    check(preview["outcome"] == "ALLOWED" and st0["revision"] == 0 and st0["spent"] == [0, 0, 0, 0]
          and st0["pending"] == 0, "preview: ALLOWED, nothing published or reserved")
    st1 = commit["state"]
    check(commit["outcome"] == "COMMITTED" and st1["revision"] == 1
          and st1["balances"] == [97500, 22500, 0] and st1["spent"] == [0, 0, 0, 1]
          and st1["pending"] == 0 and st1["reserved"] == [0, 0, 0, 0],
          "fresh commit: ledger published, exactly one tool slot charged, none pending")
    st2 = replay["state"]
    check(replay["outcome"] == "REPLAYED" and replay["reason"] == "EXACT_RETRY"
          and st2["revision"] == 1 and st2["spent"] == [0, 0, 0, 1] and st2["pending"] == 0
          and st2["epoch"] == 8,
          "expired exact replay after policy reload: REPLAYED, no new debit or charge")
    st3 = conflict["state"]
    check(conflict["outcome"] == "BLOCKED" and conflict["reason"] == "IDEMPOTENCY_CONFLICT"
          and st3["revision"] == 1 and st3["spent"] == [0, 0, 0, 1],
          "conflict: BLOCKED, no mutation")
    check(probe.get("ticket") == 1, "next ticket advanced exactly once (by the commit only)")

    # Session B: no tool-call capacity.
    rs = run_worker([configure(7, 0), cmd["PREVIEW"], cmd["EXECUTE"], RESERVE_PROBE])
    _, preview, denied, probe = rs
    check(preview["outcome"] == "BLOCKED" and preview["reason"] == "BUDGET_EXHAUSTED",
          "capacity denial reported by preview")
    st = denied["state"]
    check(denied["outcome"] == "BLOCKED" and denied["reason"] == "BUDGET_EXHAUSTED"
          and st["revision"] == 0 and st["balances"] == [100000, 20000, 0]
          and st["spent"] == [0, 0, 0, 0] and st["pending"] == 0,
          "capacity denial: ledger not published, nothing charged")
    check(probe.get("ticket") == 0, "capacity denial did not consume a ticket")

    print(f"{'OK' if not failures else 'FAILED'}: {len(failures)} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
