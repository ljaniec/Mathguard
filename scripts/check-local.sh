#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/check-fast.sh
bash scripts/check-lean.sh
if [[ ! -f scripts/test-integration.sh ]]; then
  echo 'Full release gate incomplete: scripts/test-integration.sh is not implemented.' >&2
  echo 'The formal-only check does not verify gateway/agent/store integration.' >&2
  exit 2
fi
bash scripts/test-integration.sh
