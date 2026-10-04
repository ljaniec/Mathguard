#!/usr/bin/env python3
"""Static provenance checks; a successful run is NOT a Lean proof check."""
import argparse
import json
import re
from pathlib import Path
from lean_source import definitions, proof_scan, statements, tokens

ROOT = Path(__file__).resolve().parents[1]
ALLOWED_AXIOMS = {"propext", "Classical.choice", "Quot.sound"}
EXTRA_TARGETS = {"reservedTotals_eq", "reservedAt_eq", "reserveOptimized_eq",
                 "budgetStepOptimized_eq", "ledgerResultUpdate_eq"}


def audit(axioms_path, require_extra=False, require_control=False):
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
    instance_values = [t.value for t in tokens((ROOT / "Mathguard" / "Spec.lean").read_text())]
    if not any(instance_values[i:i + 2] == ["instance", "usageLE.decidable"]
               for i in range(len(instance_values) - 1)):
        raise ValueError("Expected usageLE decidability repair absent")
    production_paths = list((ROOT / "Mathguard").rglob("*.lean")) + [ROOT / "Main.lean", ROOT / "Mathguard.lean"]
    production_paths += [ROOT / "Bench.lean", ROOT / "Tests.lean"]
    forbidden = re.compile(r"\b(sorry|admit|axiom|native_decide)\b|decide\s+\+\s*native|debug\.skipKernelTC|addDecl|set_option\s+.*skip")
    for path in production_paths:
        if not path.exists():
            raise ValueError(f"Missing production source: {path.relative_to(ROOT)}")
        if forbidden.search(proof_scan(path.read_text())):
            raise ValueError(f"Forbidden proof construct in {path.relative_to(ROOT)}")
    reports = {}
    for line in axioms_path.read_text().splitlines():
        m = re.fullmatch(r"'Mathguard\.([\w.]+)' (?:depends on axioms: \[(.*?)\]|does not depend on any axioms)", line)
        if line.startswith("'Mathguard.") and m is None:
            raise ValueError(f"Malformed axiom record: {line}")
        if m:
            if m[1] in reports:
                raise ValueError(f"Duplicate axiom record: {m[1]}")
            deps = set(x.strip() for x in (m[2] or "").split(",") if x.strip())
            if deps - ALLOWED_AXIOMS:
                raise ValueError(f"Unapproved axioms for {m[1]}: {deps}")
            reports[m[1]] = sorted(deps)
    missing = (set(targets) | (EXTRA_TARGETS if require_extra else set())) - set(reports)
    if missing:
        raise ValueError(f"Missing axiom records: {sorted(missing)}")
    if require_control:
        listed=set(re.findall(r'^#print axioms Mathguard\.([\w.]+)$',
          (ROOT/'scripts/Axioms.lean').read_text(),re.M))
        new={x for x in listed if x.startswith(('Next.','Control.'))}
        if len(new)!=96 or len([x for x in new if x.startswith('Control.')])!=53:
            raise ValueError('Unexpected Next/Control target catalog')
        if new-set(reports): raise ValueError(f'Missing Next/Control records: {sorted(new-set(reports))}')
        for name in new:
            if name.startswith('Control.') and set(reports[name])-{'propext','Quot.sound'}:
                raise ValueError(f'Unexpected generic control axiom dependency: {name}')
    return {"targets": counts, "total": len(targets), "statements_match": True,
            "model_definition_bodies_match": True, "source_holes": False,
            "additional_targets_reported": sorted(EXTRA_TARGETS & set(reports)),
            "additional_targets_required": require_extra,
            "axiom_records": len(reports), "axiom_report": str(axioms_path),
            "lean_execution": "not_performed_by_this_static_script"}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--axioms", type=Path, default=ROOT / "docs/verification/axioms.txt")
    parser.add_argument("--require-extra", action="store_true",
                        help="Require the five refinement/snapshot axiom records (fresh report).")
    parser.add_argument('--require-control',action='store_true')
    args = parser.parse_args()
    print(json.dumps(audit(args.axioms, args.require_extra,args.require_control), indent=2))


if __name__ == "__main__":
    main()
