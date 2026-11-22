#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../helpers/test-framework.sh
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Custom provider preset admission"

test_case "Python admission and credential-isolation regressions"
if python3 "$SCRIPT_DIR/test-custom-provider-config.py"; then
    test_pass
else
    test_fail "custom provider regression suite failed"
fi

test_summary
