#!/usr/bin/env python3
"""Static provenance checks; a successful run is NOT a Lean proof check."""
import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ALLOWED_AXIOMS = {"propext", "Classical.choice", "Quot.sound"}


def uncomment(text):
    out = []
    i = depth = 0
    while i < len(text):
        if text.startswith("/-", i):
            depth += 1
            i += 2
        elif depth and text.startswith("-/", i):
            depth -= 1
            i += 2
        elif depth:
            i += 1
        elif text.startswith("--", i):
            j = text.find("\n", i)
            i = len(text) if j < 0 else j
        else:
            out.append(text[i])
            i += 1
    if depth:
        raise ValueError("Unclosed Lean block comment")
    return "".join(out)


def compact(text):
    return re.sub(r"\s+", "", text)


def statements(text):
    clean = uncomment(text)
    result = {}
    for m in re.finditer(r"(?m)^theorem\s+(\w+)\b", clean):
        tail = clean[m.end():]
        separator = re.search(r":=\s*(?:by\b|rfl\b|⟨)|:=\s*\n", tail)
        if separator is None:
            raise ValueError(f"Cannot locate theorem body: {m.group(1)}")
        header = tail[:separator.start()]
        # Production modules have the same n binder in `variable {n : Nat}`.
        header = re.sub(r"\{n\s*:\s*Nat\}", "", header)
        result[m.group(1)] = compact(header)
    return result


def definitions(text):
    clean = uncomment(text)
    starts = list(re.finditer(r"(?m)^(def|abbrev|structure|inductive|instance)\s+(\S+)", clean))
    result = {}
    for index, m in enumerate(starts):
        end = starts[index + 1].start() if index + 1 < len(starts) else len(clean)
        block = clean[m.start():end]
        block = re.split(r"(?m)^end\b", block)[0]
        if m.group(1) != "instance":
            result[m.group(2)] = compact(block)
    return result


def audit(axioms_path):
    targets = {}
    counts = {}
    for stem in ("Ledger", "Budget", "Flow"):
        request = statements((ROOT / "aristotle" / f"{stem}Request.lean").read_text())
        production_text = (ROOT / "Mathguard" / f"{stem}.lean").read_text()
        if stem == "Ledger" and not re.search(r"variable\s+\{n\s*:\s*Nat\}", production_text):
            raise ValueError("Missing production account-count binder")
        production = statements(production_text)
        for name, statement in request.items():
            if production.get(name) != statement:
                raise ValueError(f"Changed or missing target statement: {name}")
        targets.update(request)
        counts[stem] = len(request)
    if counts != {"Ledger": 25, "Budget": 14, "Flow": 16}:
        raise ValueError(f"Unexpected original target set: {counts}")
    old = definitions((ROOT / "aristotle" / "Spec.lean").read_text())
    new = definitions((ROOT / "Mathguard" / "Spec.lean").read_text())
    if old != new:
        changed = sorted(k for k in set(old) | set(new) if old.get(k) != new.get(k))
        raise ValueError(f"Model definition changes: {changed}")
    instance_text = uncomment((ROOT / "Mathguard" / "Spec.lean").read_text())
    if "instance usageLE.decidable" not in instance_text:
        raise ValueError("Expected usageLE decidability repair absent")
    production_paths = list((ROOT / "Mathguard").glob("*.lean")) + [ROOT / "Main.lean", ROOT / "Mathguard.lean"]
    forbidden = re.compile(r"\b(sorry|admit|axiom|native_decide)\b|decide\s+\+native|debug\.skipKernelTC|addDecl|set_option\s+.*skip")
    for path in production_paths:
        if forbidden.search(uncomment(path.read_text())):
            raise ValueError(f"Forbidden proof construct in {path.relative_to(ROOT)}")
    reports = {}
    for line in axioms_path.read_text().splitlines():
        m = re.match(r"'Mathguard\.(\w+)' (?:depends on axioms: \[(.*?)\]|does not depend on any axioms)$", line)
        if m:
            if m[1] in reports:
                raise ValueError(f"Duplicate axiom record: {m[1]}")
            deps = set(x.strip() for x in (m[2] or "").split(",") if x.strip())
            if deps - ALLOWED_AXIOMS:
                raise ValueError(f"Unapproved axioms for {m[1]}: {deps}")
            reports[m[1]] = sorted(deps)
    missing = set(targets) - set(reports)
    if missing:
        raise ValueError(f"Missing axiom records: {sorted(missing)}")
    return {"targets": counts, "total": len(targets), "statements_match": True,
            "model_definition_bodies_match": True, "source_holes": False,
            "axiom_records": len(reports), "axiom_report": str(axioms_path),
            "lean_execution": "not_performed_by_this_static_script"}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--axioms", type=Path, default=ROOT / "docs/verification/axioms.txt")
    args = parser.parse_args()
    print(json.dumps(audit(args.axioms), indent=2))


if __name__ == "__main__":
    main()
