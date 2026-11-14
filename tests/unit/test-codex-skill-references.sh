#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Codex skill references"
test_case "generated routes and host registration retain valid skill targets"
if python3 "$PROJECT_ROOT/tests/fixtures/native-skills/codex-references.py" "$PROJECT_ROOT"; then
    test_pass
else
    test_fail "Codex reference adaptation failed"
fi
test_summary
