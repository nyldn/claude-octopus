#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Parallel workflow process and worktree isolation"
test_case "the shipped coordinator owns branches, dependencies, processes and evidence"
if python3 "$PROJECT_ROOT/tests/fixtures/native-skills/parallel-workflow.py" "$PROJECT_ROOT"; then
    test_pass
else
    test_fail "parallel workflow isolation contract failed"
fi
test_case "source, native and Codex entries use the same bounded run protocol"
if python3 "$PROJECT_ROOT/tests/fixtures/native-skills/parallel-aggregation.py" "$PROJECT_ROOT"; then
    test_pass
else
    test_fail "parallel workflow host binding failed"
fi
test_summary
