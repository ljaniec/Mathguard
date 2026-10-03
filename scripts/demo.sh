#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
lake build mathguard-worker
exec python3 -m gateway.server "$@"
