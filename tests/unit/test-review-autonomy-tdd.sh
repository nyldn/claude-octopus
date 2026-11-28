#!/usr/bin/env bash
# Test review workflow guidance for autonomous codegen and TDD verification

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "review workflow guidance for autonomous codegen and TDD verification"

REVIEW_COMMAND="$PROJECT_ROOT/commands/review.md"
REVIEW_SKILL="$(resolve_claude_skill_path "skill-code-review")"

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
for tree in .claude/skills skills codex-skills; do
    skill="$PROJECT_ROOT/$tree/skill-code-review/SKILL.md"
    test_case "$tree review guidance works with the invoking host and runtime route"
    if grep -Fq 'Use the provider and model selected by the runtime' "$skill" &&
       grep -Fq 'Ask the user whether to post' "$skill" &&
       ! grep -Eq 'AskUserQuestion|gpt-5\.2-codex|background Sonnet agents|/octo:embrace' "$skill"; then
        test_pass
    else
        test_fail "review guidance hardcodes a host tool or reviewer route"
    fi

    test_case "$tree comment attributes only the reviews in the synthesis"
    body_recipe=$(awk '
        /^[[:space:]]*REVIEW_BODY="/ { start = NR }
        start { print }
        start && NR > start && /"$/ { exit }
    ' "$skill")
    body=$(REVIEW_SYNTHESIS='Reviewed by Antigravity. Codex unavailable.' \
        bash -eu -c "$body_recipe"$'\nprintf "%s\n" "$REVIEW_BODY"')
    if [[ "$body" == *'Reviewed by Antigravity. Codex unavailable.'* &&
          "$body" != *'available external providers'* && "$body" != *'/octo:review'* ]]; then
        test_pass
    else
        test_fail "the comment template adds an unverified provider or a host-specific command"
    fi
done
test_summary
