#!/usr/bin/env bash
# Test review workflow guidance for autonomous codegen and TDD verification

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "review workflow guidance for autonomous codegen and TDD verification"

REVIEW_COMMAND="$PROJECT_ROOT/.claude/commands/review.md"
REVIEW_SKILL="$PROJECT_ROOT/.claude/skills/skill-code-review.md"

TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

pass() { test_case "$1"; test_pass; }

fail() { test_case "$1"; test_fail "${2:-$1}"; }

assert_contains() {
    local file="$1"
    local pattern="$2"
    local label="$3"

    if grep -qiE "$pattern" "$file"; then
        pass "$label"
    else
        fail "$label" "Missing pattern '$pattern' in $file"
    fi
}

assert_contains "$REVIEW_COMMAND" 'header:\s*"Provenance"|Autonomous / Dark Factory|AI-assisted' \
    "review command asks for implementation mode"
assert_contains "$REVIEW_COMMAND" 'Autonomous / Dark Factory' \
    "review command offers autonomous review mode"
assert_contains "$REVIEW_COMMAND" 'TDD discipline|TDD compliance|test-first' \
    "review command surfaces TDD-focused review concerns"

assert_contains "$REVIEW_SKILL" '^## Autonomous Implementation Review' \
    "review skill has autonomous implementation review section"
assert_contains "$REVIEW_SKILL" 'TDD Evidence|failing test|test-first' \
    "review skill checks for TDD evidence"
assert_contains "$REVIEW_SKILL" 'unknown.*not assumed|do not assume TDD' \
    "review skill treats missing TDD evidence as unknown"
test_summary
