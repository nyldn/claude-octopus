#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Optional research search HTTP contract"
test_case "offline transport, limits, allowlist and untrusted boundaries"
if python3 "$SCRIPT_DIR/test-keenable-search.py"; then test_pass
else test_fail "optional search contract regression"; fi
test_summary
