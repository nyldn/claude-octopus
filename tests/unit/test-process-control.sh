#!/usr/bin/env bash
# Native process handles, cancellation, and bounded cleanup.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/test-process-control.py"
