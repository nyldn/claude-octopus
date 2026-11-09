#!/usr/bin/env bash
# Offline checks for provider panels, paired dispatch and shipped phase resources.
set -euo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/../helpers/test-framework.sh"
test_suite "Refinement workflow efficiency"
test_case "provider panels, paired dispatch and shipped resources"
if python3 "$TEST_DIR/test-refinement-efficiency.py"; then
    test_pass
else
    test_fail "Refinement workflow efficiency regressions failed"
fi
test_summary
