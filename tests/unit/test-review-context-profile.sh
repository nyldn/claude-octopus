#!/usr/bin/env bash
# Tests for code-review JSON profile contract context support.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "code-review context profile"

REVIEW_SH="$PROJECT_ROOT/scripts/lib/review.sh"
ORCH="$PROJECT_ROOT/scripts/orchestrate.sh"

assert_contains() {
    local file="$1"
    local pattern="$2"
    local label="$3"
    test_case "$label"
    if grep -qF "$pattern" "$file"; then
        test_pass
    else
        test_fail "missing pattern: $pattern"
    fi
}

assert_contains "$REVIEW_SH" "contextFile" "review profile accepts contextFile"
assert_contains "$REVIEW_SH" "contextText" "review profile accepts contextText"
assert_contains "$REVIEW_SH" "contextLabel" "review profile accepts contextLabel"
assert_contains "$REVIEW_SH" "OCTOPUS_REVIEW_CONTEXT_CHARS" "review context has bounded size"
assert_contains "$REVIEW_SH" "fails the supplied task contract" "review prompt checks task contract conformance"
assert_contains "$REVIEW_SH" "contextFile is not readable" "missing contextFile fails clearly"
assert_contains "$REVIEW_SH" "contextFile escapes workspace root" "contextFile is restricted to workspace root"
assert_contains "$REVIEW_SH" "context_file_resolved" "contextFile is resolved before reading"
assert_contains "$REVIEW_SH" "octo_proof_finalize" "unreadable contextFile finalizes proof packet"
assert_contains "$REVIEW_SH" "provider_status_file" "unreadable contextFile cleans up provider status"
assert_contains "$REVIEW_SH" "...[truncated]" "truncated review context is marked"
assert_contains "$ORCH" "contextFile, contextText, contextLabel" "code-review help documents context fields"
assert_contains "$ORCH" "plan-conformance" "code-review help shows plan-conformance example"

test_summary
