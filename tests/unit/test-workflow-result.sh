#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Workflow result gates"
test_case "native and generated workflow invocations validate their fresh reports"
if python3 "$SCRIPT_DIR/test-workflow-result.py"; then
    test_pass
else
    test_fail "workflow result gate regressions failed"
fi
test_summary
