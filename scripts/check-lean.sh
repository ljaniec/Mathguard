#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v lake >/dev/null 2>&1; then
  echo 'Missing Lake/Lean toolchain; no verification performed.' >&2
  exit 127
fi
lake env lean --version
lake build
mathguard_axiom_report=$(mktemp)
trap 'rm -f "$mathguard_axiom_report"' EXIT
lake env lean scripts/Axioms.lean > "$mathguard_axiom_report"
python3 scripts/audit_sources.py --axioms "$mathguard_axiom_report"
lake exe mathguard
