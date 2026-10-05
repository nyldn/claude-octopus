#!/usr/bin/env bash
# Default descriptor backend safety and bounded process-count regression.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$SCRIPT_DIR/test-consultative-copy.py"
