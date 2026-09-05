#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Codex safety contract"
test_case "real hooks enforce the cross-host safety contract"
if python3 "$SCRIPT_DIR/codex_safety_contract_test.py" "$PROJECT_ROOT"; then
    test_pass
else
    test_fail "Python safety-contract assertions failed"
fi
test_summary
