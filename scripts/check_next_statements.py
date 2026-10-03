#!/usr/bin/env python3
"""Static comparison of the Mathguard.Next request statements with the production modules.

For every top-level declaration of each request file under `aristotle/next/`:
* a `theorem` must appear in the production module with an identical statement
  (all text up to and including `:= by`);
* every `structure`/`inductive`/`def` must appear verbatim.
It also checks that the production modules contain no proof holes or banned tactics.

This is a *static source comparison*, not a Lean proof check; the proof check is
`lake build` plus `lake env lean scripts/Axioms.lean`.
Run from the project root:  python3 scripts/check_next_statements.py
"""
import re
import sys

PACKAGES = [
    ("C1", "aristotle/next/CompositeRequest.lean", "Mathguard/Composite.lean", 14),
    ("P1", "aristotle/next/PolicyHistoryRequest.lean", "Mathguard/PolicyHistory.lean", 12),
    ("W1", "aristotle/next/WireRequest.lean", "Mathguard/Wire.lean", 9),
]
BANNED = ["sorry", "admit", "native_decide", "decide +native", "axiom ", "implemented_by",
          "debug.skipKernelTC", "unsafe"]
DECL = re.compile(r"^(theorem|def|structure|inductive) ", re.M)


def blocks(src):
    body = src.split("namespace Mathguard.Next", 1)[1].split("end Mathguard.Next", 1)[0]
    starts = [m.start() for m in DECL.finditer(body)] + [len(body)]
    for a, b in zip(starts, starts[1:]):
        yield body[a:b].rstrip()


def strip_comments(src):
    src = re.sub(r"/-.*?-/", "", src, flags=re.S)
    return re.sub(r"--[^\n]*", "", src)


ok = True
total = 0
for name, req_path, prod_path, expected in PACKAGES:
    req = open(req_path).read()
    prod = open(prod_path).read()
    theorems = 0
    for blk in blocks(req):
        kind, ident = blk.split()[0], blk.split()[1]
        if kind == "theorem":
            theorems += 1
            stmt = blk[: blk.index(":= by") + len(":= by")]
            found = stmt in prod
        else:
            found = blk in prod
        status = "match" if found else "MISMATCH"
        if not found:
            ok = False
        print(f"{name} {kind:9} {ident:48} {status}")
    if theorems != expected:
        ok = False
        print(f"{name}: expected {expected} theorem targets, found {theorems}")
    code = strip_comments(prod)
    for word in BANNED:
        if word in code:
            ok = False
            print(f"{name}: banned token `{word}` in {prod_path}")
    if "import Mathguard\n" in prod:
        ok = False
        print(f"{name}: {prod_path} imports the root module")
    print(f"{name}: {theorems} theorem statements compared")
    total += theorems

print(f"total new targets compared: {total}")
print("RESULT:", "PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
