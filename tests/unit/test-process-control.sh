#!/usr/bin/env bash
# Native process handles, cancellation, and bounded cleanup.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Native process control"
test_case "native identity, cancellation and failure handling"
if python3 "$SCRIPT_DIR/test-process-control.py"; then
    test_pass
else
    test_fail "native process-control contracts failed"
fi
test_summary
