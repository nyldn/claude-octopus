#!/usr/bin/env bash
# Regression coverage for evidence-based review provider status (#891).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT/scripts/lib/review.sh"

test_suite "Review provider report"

status_file="$TEST_TMP_DIR/provider-status.txt"

test_case "Claude is not reported healthy without a successful execution"
printf '%s\n' 'codex|fallback|Round 1 agent did not complete successfully' > "$status_file"
report="$(env "HOME=${TEST_TMP_DIR}" bash -c '
    source "$1"
    print_provider_report "$2"
' _ "$PROJECT_ROOT/scripts/lib/review.sh" "$status_file")"
if grep -Eq 'Claude:[[:space:]]+not used' <<< "$report"; then
    test_pass
else
    test_fail "Claude received an optimistic status without execution evidence: $report"
fi

test_case "Claude failures are rendered as failures"
printf '%s\n' 'claude|fallback|Round 1 agent did not complete successfully' > "$status_file"
report="$(env "HOME=${TEST_TMP_DIR}" bash -c '
    source "$1"
    print_provider_report "$2"
' _ "$PROJECT_ROOT/scripts/lib/review.sh" "$status_file")"
if grep -Eq 'Claude:[[:space:]]+.*FALLBACK' <<< "$report" &&
   [[ "$report" == *"Round 1 agent did not complete successfully"* ]]; then
    test_pass
else
    test_fail "Claude failure was hidden by the provider report: $report"
fi

test_summary
