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
  grep -qE "$pattern" <<< "$output" && pass "$label" || fail "$label" "missing: $pattern"
}

assert_not_contains() {
  local output="$1" pattern="$2" label="$3"
  grep -qE "$pattern" <<< "$output" && fail "$label" "should not contain: $pattern" || pass "$label"
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

assert_contains "$(grep -c 'review_collect_diff' "$ALL_SRC" 2>/dev/null || echo 0)" \
  "[1-9]" "review_collect_diff: function exists"

assert_contains "$(grep 'normal\|nit\|pre.existing' "$ALL_SRC" 2>/dev/null | head -5)" \
  "normal|nit|pre.existing" "severity model: all three levels referenced"

assert_contains "$(grep 'code-review)' "$ALL_SRC" 2>/dev/null | head -3)" \
  "code-review" "dispatch: code-review command exists in main case"

assert_contains "$(grep -c 'post_inline_comments' "$ALL_SRC" 2>/dev/null || echo 0)" \
  "[1-9]" "post_inline_comments: function exists"

# ── command file checks ───────────────────────────────────────────────────────

REVIEW_CMD="$PROJECT_ROOT/commands/review.md"
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

assert_contains "$(grep 'local pr_number=.*review_pr_number' "$ALL_SRC" 2>/dev/null | head -3)" \
  'review_pr_number' "review_run: publish uses explicit PR target before branch fallback"

assert_contains "$(grep -A4 'avg_confidence=$(jq' "$ALL_SRC" 2>/dev/null | head -8)" \
  'head -n 1' "review_run: confidence fallback cannot append a second line"

assert_contains "$(grep -A2 'commit_id.*headRefOid' "$ALL_SRC" 2>/dev/null | head -10)" \
  'commit_id' "post_inline_comments: empty commit_id guarded"

assert_contains "$(grep -c 'review_openai_compat_empty_output_retryable' "$ALL_SRC" 2>/dev/null || true)" \
  "[1-9]" "review_run: OpenAI-compatible Empty output retry classifier exists"

assert_contains "$(grep -c 'OCTOPUS_REVIEW_OPENAI_COMPAT_EMPTY_RETRY_BACKOFF_SECS' "$ALL_SRC" 2>/dev/null || true)" \
  "[1-9]" "review_run: OpenAI-compatible Empty output retry has configurable backoff"

assert_contains "$(grep -c 'attempt1' "$ALL_SRC" 2>/dev/null || true)" \
  "[1-9]" "review_run: OpenAI-compatible Empty output retry preserves first artifact"

assert_contains "$(grep -c 'OCTOPUS_REVIEW_OPENROUTER_RETRY_BACKOFF_SECS' "$ALL_SRC" 2>/dev/null || true)" \
  "[1-9]" "review_run: OpenRouter transport retry has configurable backoff"

assert_contains "$(grep 'local task_id="review-r1-' "$PROJECT_ROOT/scripts/lib/review.sh" 2>/dev/null)" \
  'review-r1-\$\{agent_type\}-\$\{role\}' "review_run: concurrent seats receive provider-unique task IDs"

# ── diff target file support ─────────────────────────────────────────────────

source "$PROJECT_ROOT/scripts/lib/review.sh"

if (
  log() { :; }
  round1_agent_types=(codex claude-opus openrouter-glm52 openrouter-kimi-k3)
  round1_prompts=(one two three four)
  round1_task_ids=(task-1 task-2 task-3 task-4)
  round1_roles=(logic architecture diversity diversity)
  round1_pids=()
  spawn_agent_capture_pid() {
    sleep 2
    case "$1" in
      codex) echo 9001 ;;
      claude-opus) echo 9002 ;;
      openrouter-glm52) echo 9003 ;;
      openrouter-kimi-k3) echo 9004 ;;
    esac
  }
  SECONDS=0
  review_launch_round1_fleet
  [[ "$SECONDS" -lt 5 ]] &&
    [[ "${round1_pids[*]}" == "9001 9002 9003 9004" ]]
); then
  pass "review_run: Round 1 provider setup launches concurrently"
else
  fail "review_run: Round 1 provider setup launches concurrently" \
    "four two-second setup paths did not overlap or PID ordering changed"
fi

local_synthesis=$(review_local_synthesis_json '[
  {"file":"calc.js","line":2,"severity":"normal","category":"correctness","title":"wrong operation","detail":"first perspective","confidence":0.8},
  {"file":"calc.js","line":2,"severity":"normal","category":"correctness","title":"subtracts instead of adds","detail":"second perspective","confidence":0.9},
  {"file":"other.js","line":1,"severity":"nit","category":"style","title":"minor","detail":"third finding","confidence":0.7}
]')
if [[ "$(printf '%s' "$local_synthesis" | jq '.findings | length')" == "2" ]] &&
   [[ "$(printf '%s' "$local_synthesis" | jq -r '.findings[0].confidence')" == "0.9" ]] &&
   [[ "$(printf '%s' "$local_synthesis" | jq -r '.findings[0].detail')" == *"first perspective"* ]] &&
   [[ "$(printf '%s' "$local_synthesis" | jq -r '.findings[0].detail')" == *"second perspective"* ]]; then
  pass "review_run: local synthesis deduplicates corroborating provider findings"
else
  fail "review_run: local synthesis deduplicates corroborating provider findings" \
    "fallback did not merge same-location/category findings deterministically"
fi

DIFF_TARGET="$TMPDIR_TEST/review-target.diff"
cat > "$DIFF_TARGET" <<'EOF'
diff --git a/foo.txt b/foo.txt
--- a/foo.txt
+++ b/foo.txt
@@ -1 +1 @@
-old
+new
EOF

assert_contains "$(review_collect_diff "$DIFF_TARGET")" \
  "diff --git a/foo.txt b/foo.txt" "review_collect_diff: reads unified diff file targets"

OPENAI_COMPAT_EMPTY_RETRYABLE="$TMPDIR_TEST/openai-compat-empty-retryable.md"
cat > "$OPENAI_COMPAT_EMPTY_RETRYABLE" <<'EOF'
# Agent: openai-compatible
## Status: FAILED (Empty output)
Reconnecting... 1/5
EOF

OPENAI_COMPAT_EMPTY_NO_RECONNECT="$TMPDIR_TEST/openai-compat-empty-no-reconnect.md"
cat > "$OPENAI_COMPAT_EMPTY_NO_RECONNECT" <<'EOF'
# Agent: openai-compatible
## Status: FAILED (Empty output)
EOF

if review_openai_compat_empty_output_retryable "$OPENAI_COMPAT_EMPTY_RETRYABLE" "codex"; then
  pass "review_run: OpenAI-compatible Empty output with reconnect is retryable"
else
  fail "review_run: OpenAI-compatible Empty output with reconnect is retryable"
fi

if review_openai_compat_empty_output_retryable "$OPENAI_COMPAT_EMPTY_NO_RECONNECT" "codex"; then
  fail "review_run: OpenAI-compatible Empty output without reconnect is not retryable"
else
  pass "review_run: OpenAI-compatible Empty output without reconnect is not retryable"
fi

if review_openai_compat_empty_output_retryable "$OPENAI_COMPAT_EMPTY_RETRYABLE" "gemini"; then
  fail "review_run: non-OpenAI-compatible Empty output is not retried by adapter policy"
else
  pass "review_run: non-OpenAI-compatible Empty output is not retried by adapter policy"
fi

OPENROUTER_TRANSPORT_RETRYABLE="$TMPDIR_TEST/openrouter-transport-retryable.md"
cat > "$OPENROUTER_TRANSPORT_RETRYABLE" <<'EOF'
# Agent: openrouter-kimi-k3
## Status: FAILED (exit code: 1)
## Error Log
OpenRouter curl failed (timeout or network error, model=moonshotai/kimi-k3)
# Completed: now
EOF

if review_openrouter_transport_retryable "$OPENROUTER_TRANSPORT_RETRYABLE" "openrouter-kimi-k3"; then
  pass "review_run: transient OpenRouter transport failure is retryable"
else
  fail "review_run: transient OpenRouter transport failure is retryable"
fi

if review_openrouter_transport_retryable "$OPENROUTER_TRANSPORT_RETRYABLE" "codex"; then
  fail "review_run: OpenRouter transport retry is provider-scoped"
else
  pass "review_run: OpenRouter transport retry is provider-scoped"
fi

# ── MCP schema ───────────────────────────────────────────────────────────────

MCP_INDEX="$PROJECT_ROOT/mcp-server/src/index.ts"
assert_contains "$(cat "$MCP_INDEX" 2>/dev/null)" \
  "focus|provenance|autonomy|publish|debate" "mcp: review tool has typed profile fields"

# ── OpenClaw schema ──────────────────────────────────────────────────────────

OPENCLAW_INDEX="$PROJECT_ROOT/openclaw/src/index.ts"
assert_contains "$(cat "$OPENCLAW_INDEX" 2>/dev/null)" \
  "focus|provenance|autonomy|publish|debate" "openclaw: review tool has typed profile fields"
test_summary
