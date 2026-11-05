#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Council policy findings"
test_case "policy extraction and quote exemptions agree"
if python3 "$SCRIPT_DIR/test-council-policy-findings.py"; then
    test_pass
else
    test_fail "policy findings regression tests failed"
fi
test_summary
