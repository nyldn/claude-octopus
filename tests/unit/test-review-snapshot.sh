#!/usr/bin/env bash
# Review snapshot selection and publication gates use inert local fixtures.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Review snapshot and posting recipes"
test_case "selected Git bytes, private evidence and authorized report posting"
if python3 "$PROJECT_ROOT/tests/fixtures/native-skills/review-recipes.py" "$PROJECT_ROOT"; then
    test_pass
else
    test_fail "review snapshot or publication contract failed"
fi
test_summary
