#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Vibe keyring readiness"
test_case "keyring readiness, isolation and setup regressions"
if python3 "$SCRIPT_DIR/test-vibe-keyring.py"; then
    test_pass
else
    test_fail "Vibe keyring regression suite failed"
fi
test_summary
