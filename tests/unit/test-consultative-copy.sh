#!/usr/bin/env bash
# Default descriptor backend safety and bounded process-count regression.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Consultative descriptor copy"
test_case "descriptor copier filesystem contracts"
if ! command -v python3 >/dev/null 2>&1; then
    test_skip "python3 unavailable; portable shell copier has separate coverage"
elif python3 -I "$SCRIPT_DIR/test-consultative-copy.py"; then
    test_pass
else
    test_fail "descriptor copier filesystem contracts failed"
fi
test_summary
