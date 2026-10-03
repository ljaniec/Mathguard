#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/audit_sources.py
python3 -m unittest discover -s scripts -p 'test_*.py'
for mathguard_script in scripts/*.sh; do
  bash -n "$mathguard_script"
done
echo 'Static preflight passed; Lean proof and whole-stack integration checks are separate.'
