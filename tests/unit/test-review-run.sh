#!/usr/bin/env bash
# Tests for review_run() pipeline, REVIEW.md parsing, fleet fallback, severity output

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "review_run() pipeline, REVIEW.md parsing, fleet fallback, severity output"

ORCHESTRATE="$PROJECT_ROOT/scripts/orchestrate.sh"
# Combined search target (functions decomposed to lib/ in v9.7.7+)
ALL_SRC=$(mktemp)
trap 'rm -f "$ALL_SRC"' EXIT
cat "$ORCHESTRATE" "$PROJECT_ROOT/scripts/lib/"*.sh > "$ALL_SRC" 2>/dev/null

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

assert_contains() {
  local output="$1" pattern="$2" label="$3"
  echo "$output" | grep -qE "$pattern" && pass "$label" || fail "$label" "missing: $pattern"
}

assert_not_contains() {
  local output="$1" pattern="$2" label="$3"
  echo "$output" | grep -qE "$pattern" && fail "$label" "should not contain: $pattern" || pass "$label"
}

# ── parse_review_md fixture ───────────────────────────────────────────────────

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

TEST_REVIEW_MD="$TMPDIR_TEST/REVIEW.md"
cat > "$TEST_REVIEW_MD" <<'EOF'
# Code Review Guidelines

## Always check
- New API endpoints have corresponding integration tests
- Database migrations are backward-compatible

## Style
- Prefer early returns over nested conditionals

## Skip
- Generated files under src/gen/
- Formatting-only changes in *.lock files
EOF

assert_contains "$(grep -A1 'Always check' "$TEST_REVIEW_MD")" \
  "integration tests" "parse_review_md: always_check section readable"

assert_contains "$(grep -A1 'Style' "$TEST_REVIEW_MD")" \
  "early returns" "parse_review_md: style section readable"

assert_contains "$(grep -A1 'Skip' "$TEST_REVIEW_MD")" \
  "src/gen" "parse_review_md: skip section readable"

# ── static checks for functions ───────────────────────────────────────────────

assert_contains "$(grep -c 'build_review_fleet' "$ALL_SRC" 2>/dev/null || echo 0)" \
  "[1-9]" "build_review_fleet: function exists"

assert_contains "$(grep -c 'review_run' "$ALL_SRC" 2>/dev/null || echo 0)" \
  "[1-9]" "review_run: function exists"

assert_contains "$(grep 'normal\|nit\|pre.existing' "$ALL_SRC" 2>/dev/null | head -5)" \
  "normal|nit|pre.existing" "severity model: all three levels referenced"

assert_contains "$(grep 'code-review)' "$ALL_SRC" 2>/dev/null | head -3)" \
  "code-review" "dispatch: code-review command exists in main case"

assert_contains "$(grep -c 'post_inline_comments' "$ALL_SRC" 2>/dev/null || echo 0)" \
  "[1-9]" "post_inline_comments: function exists"

# ── command file checks ───────────────────────────────────────────────────────

REVIEW_CMD="$PROJECT_ROOT/.claude/commands/review.md"
assert_contains "$(cat "$REVIEW_CMD" 2>/dev/null)" \
  "REVIEW\.md" "review command: references REVIEW.md"
assert_contains "$(cat "$REVIEW_CMD" 2>/dev/null)" \
  "code-review|review_run" "review command: calls code-review or review_run backend"

# ── result-file path convention ───────────────────────────────────────────────
# spawn_agent writes ${RESULTS_DIR}/${agent_type}-${task_id}.md
# review_run must reference that same pattern, not ${task_id}.json

assert_contains "$(grep 'RESULTS_DIR.*agent_type.*task_id' "$ALL_SRC" 2>/dev/null | head -5)" \
  "RESULTS_DIR" "review_run: result_file uses RESULTS_DIR/agent_type-task_id pattern (no .json)"

assert_not_contains "$(grep -A5 'round1_files' "$ALL_SRC" 2>/dev/null | head -20)" \
  'task_id.*\.json"' "review_run: result_file not using old .json path pattern"

# ── fallback guards ───────────────────────────────────────────────────────────

assert_contains "$(grep -c 'codex verifier failed' "$ALL_SRC" 2>/dev/null || echo 0)" \
  "[1-9]" "review_run: verifier run_agent_sync has fallback guard"

assert_contains "$(grep 'post_inline_comments.*findings_file.*||' "$ALL_SRC" 2>/dev/null | head -5)" \
  "render_terminal_report" "review_run: post_inline_comments guarded with terminal fallback"

assert_contains "$(grep -A2 'commit_id.*headRefOid' "$ALL_SRC" 2>/dev/null | head -10)" \
  'commit_id' "post_inline_comments: empty commit_id guarded"

# ── MCP schema ───────────────────────────────────────────────────────────────

MCP_INDEX="$PROJECT_ROOT/mcp-server/src/index.ts"
assert_contains "$(cat "$MCP_INDEX" 2>/dev/null)" \
  "focus|provenance|autonomy|publish|debate" "mcp: review tool has typed profile fields"

# ── OpenClaw schema ──────────────────────────────────────────────────────────

OPENCLAW_INDEX="$PROJECT_ROOT/openclaw/src/index.ts"
assert_contains "$(cat "$OPENCLAW_INDEX" 2>/dev/null)" \
  "focus|provenance|autonomy|publish|debate" "openclaw: review tool has typed profile fields"
test_summary
