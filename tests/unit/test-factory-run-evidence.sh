#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Factory run evidence"
test_case "factory approval, scoring, coverage and artifact identity"
if python3 "$PROJECT_ROOT/tests/fixtures/native-skills/factory-recipes.py"; then
    test_pass
else
    test_fail "factory behavior fixtures failed"
fi
test_summary
