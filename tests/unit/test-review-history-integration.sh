#!/usr/bin/env bash
# Static integration checks for round-aware /octo:review wiring.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ORCH="$PROJECT_ROOT/scripts/orchestrate.sh"
REVIEW_LIB="$PROJECT_ROOT/scripts/lib/review.sh"
STATE_LIB="$PROJECT_ROOT/scripts/lib/pr-review-state.sh"
CLAUDE_CMD="$PROJECT_ROOT/.claude/commands/review.md"
CODEX_CMD="$PROJECT_ROOT/commands/octo-review.md"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "round-aware review integration"

assert_file_has() {
    local file="$1"
    local pattern="$2"
    local label="$3"
    test_case "$label"
    if grep -qE "$pattern" "$file"; then
        test_pass
    else
        test_fail "pattern not found in $(basename "$file"): $pattern"
    fi
}

test_case "pr-review-state.sh has valid bash syntax"
if [[ -f "$STATE_LIB" ]] && bash -n "$STATE_LIB" 2>/dev/null; then
    test_pass
else
    test_fail "missing or invalid $STATE_LIB"
fi

assert_file_has "$ORCH" 'lib/pr-review-state\.sh' \
    "orchestrate.sh sources review state module"

assert_file_has "$REVIEW_LIB" '\.history[[:space:]]*//[[:space:]]*"auto"' \
    "review_run parses structured history profile"

assert_file_has "$REVIEW_LIB" 'pr_review_state_context_for_prompt' \
    "review_run augments prompt with prior round context"

assert_file_has "$REVIEW_LIB" 'pr_review_state_render_timeline' \
    "review_run renders inline round timeline"

assert_file_has "$REVIEW_LIB" 'pr_review_state_append_round' \
    "review_run persists final findings as a new round"

assert_file_has "$REVIEW_LIB" 'OCTOPUS_PR_HISTORY' \
    "review_run honors global history opt-out"

assert_file_has "$CLAUDE_CMD" 'fresh' \
    "Claude slash command documents fresh mode"

assert_file_has "$CLAUDE_CMD" 'OCTOPUS_PR_HISTORY=0' \
    "Claude slash command documents global opt-out"

assert_file_has "$CLAUDE_CMD" '~/.claude-octopus/pr-state' \
    "Claude slash command documents local state path"

assert_file_has "$CODEX_CMD" 'history' \
    "Codex command mirrors structured history profile"

test_summary
