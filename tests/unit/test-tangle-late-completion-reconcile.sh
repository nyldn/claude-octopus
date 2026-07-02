#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_TMP_DIR="${TEST_TMP_DIR:-/tmp/octopus-tests-$$}"
trap 'rm -rf "$TEST_TMP_DIR"' EXIT INT TERM

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "tangle late completion reconciliation"

test_case "latest tangle result status wins over earlier missing-marker failure"
mkdir -p "$TEST_TMP_DIR"
result="$TEST_TMP_DIR/agy-tangle-123-2.md"
cat > "$result" <<'EOF'
# Agent: agy
# Task ID: tangle-123-2

## Output
partial

## Status: FAILED (Missing completion marker)
# Completed: earlier

## Output
final

## Status: SUCCESS
# Completed: later
EOF
source "$PROJECT_ROOT/scripts/lib/testing.sh"
if [[ "$(tangle_result_latest_status "$result")" == "success" ]]; then
    test_pass
else
    test_fail "latest SUCCESS status should override an earlier missing-marker failure"
fi

test_case "latest terminal failure is still counted as failed"
cat > "$result" <<'EOF'
# Agent: agy
# Task ID: tangle-123-2

## Status: SUCCESS
# Completed: earlier

## Status: FAILED (Missing completion marker)
# Completed: later
EOF
if [[ "$(tangle_result_latest_status "$result")" == "failed" ]]; then
    test_pass
else
    test_fail "latest FAILED status should not be hidden by an earlier success"
fi

test_case "workflow waits before converting missing marker into terminal failure"
if grep -q 'OCTOPUS_TANGLE_MISSING_MARKER_GRACE' "$PROJECT_ROOT/scripts/lib/workflows.sh" \
   && grep -q 'wrapper exited without completion marker' "$PROJECT_ROOT/scripts/lib/workflows.sh" \
   && grep -q 'still lacks completion marker after' "$PROJECT_ROOT/scripts/lib/workflows.sh"; then
    test_pass
else
    test_fail "missing marker grace period is not wired into tangle watcher"
fi

test_case "workflow reconciles late successful result before quality gate"
if grep -q 'Reconciled late successful result' "$PROJECT_ROOT/scripts/lib/workflows.sh" \
   && grep -q 'before quality gate' "$PROJECT_ROOT/scripts/lib/workflows.sh"; then
    test_pass
else
    test_fail "late success reconciliation is missing before quality gate"
fi

test_summary
