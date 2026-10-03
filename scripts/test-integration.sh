#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
lake build mathguard-worker
python3 scripts/check-integration.py
