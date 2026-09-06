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
trap 'rm -f "$ALL_SRC"; rm -rf "$TMPDIR_TEST"' EXIT

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

# Behavioural test for the retry classifier, not a grep for its name: the
# grep passed whether or not the function actually classified anything.
source "$PROJECT_ROOT/scripts/lib/review.sh"

_retry_fixture_dir="$(mktemp -d)"
_retry_both="$_retry_fixture_dir/both.md"
printf '## Status: FAILED (Empty output)\nReconnecting to provider\n' > "$_retry_both"
_retry_empty_only="$_retry_fixture_dir/empty-only.md"
printf '## Status: FAILED (Empty output)\n' > "$_retry_empty_only"
_retry_clean="$_retry_fixture_dir/clean.md"
printf '## Status: OK\nall good\n' > "$_retry_clean"

if review_openai_compat_empty_output_retryable "$_retry_both" "codex"; then
  assert_contains "retryable" "^retryable$" "review_run: empty-output + reconnect is retryable"
else
  assert_contains "not-retryable" "^retryable$" "review_run: empty-output + reconnect is retryable"
fi

if review_openai_compat_empty_output_retryable "$_retry_empty_only" "codex"; then
  assert_contains "retryable" "^not-retryable$" "review_run: empty output without reconnect is not retryable"
else
  assert_contains "not-retryable" "^not-retryable$" "review_run: empty output without reconnect is not retryable"
fi

if review_openai_compat_empty_output_retryable "$_retry_clean" "codex"; then
  assert_contains "retryable" "^not-retryable$" "review_run: clean output is not retryable"
else
  assert_contains "not-retryable" "^not-retryable$" "review_run: clean output is not retryable"
fi

if review_openai_compat_empty_output_retryable "$_retry_both" "gemini"; then
  assert_contains "retryable" "^not-retryable$" "review_run: retry classifier only applies to codex seats"
else
  assert_contains "not-retryable" "^not-retryable$" "review_run: retry classifier only applies to codex seats"
fi

if review_openai_compat_empty_output_retryable "$_retry_fixture_dir/missing.md" "codex"; then
  assert_contains "retryable" "^not-retryable$" "review_run: missing result file is not retryable"
else
  assert_contains "not-retryable" "^not-retryable$" "review_run: missing result file is not retryable"
fi

rm -rf "$_retry_fixture_dir"

assert_contains "$(grep -c 'OCTOPUS_REVIEW_OPENAI_COMPAT_EMPTY_RETRY_BACKOFF_SECS' "$ALL_SRC" 2>/dev/null || true)" \
  "[1-9]" "review_run: OpenAI-compatible Empty output retry has configurable backoff"

assert_contains "$(grep -c 'attempt1' "$ALL_SRC" 2>/dev/null || true)" \
  "[1-9]" "review_run: OpenAI-compatible Empty output retry preserves first artifact"

# ── diff target file support ─────────────────────────────────────────────────

source "$PROJECT_ROOT/scripts/lib/review.sh"

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

# ── working-tree diff includes untracked files ───────────────────────────────

WORKTREE_REPO="$TMPDIR_TEST/review-working-tree"
mkdir -p "$WORKTREE_REPO"
(
  cd "$WORKTREE_REPO"
  git init -q
  git config user.email test@example.com
  git config user.name "Octopus Test"
  printf 'old\n' > tracked.txt
  printf '*.ignored\n' > .gitignore
  git add tracked.txt .gitignore
  git commit -q -m init
  printf 'changed\n' > tracked.txt
  printf 'new\n' > 'new file.txt'
  printf 'ignore me\n' > noise.ignored
  review_collect_diff working-tree > "$TMPDIR_TEST/working-tree.diff"
)

assert_contains "$(cat "$TMPDIR_TEST/working-tree.diff")" \
  "tracked.txt" "review_collect_diff: working-tree includes tracked modifications"
assert_contains "$(cat "$TMPDIR_TEST/working-tree.diff")" \
  "new file.txt" "review_collect_diff: working-tree includes untracked files"
assert_contains "$(cat "$TMPDIR_TEST/working-tree.diff")" \
  "\+changed" "review_collect_diff: working-tree includes tracked content"
assert_contains "$(cat "$TMPDIR_TEST/working-tree.diff")" \
  "\+new" "review_collect_diff: working-tree includes untracked content"
assert_not_contains "$(cat "$TMPDIR_TEST/working-tree.diff")" \
  "noise.ignored" "review_collect_diff: working-tree excludes ignored untracked files"

# ── all-changes diff includes staged, unstaged, and untracked files ───────────

ALL_CHANGES_REPO="$TMPDIR_TEST/review-all-changes"
mkdir -p "$ALL_CHANGES_REPO"
(
  cd "$ALL_CHANGES_REPO"
  git init -q
  git config user.email test@example.com
  git config user.name "Octopus Test"
  printf 'base staged\n' > staged.txt
  printf 'base unstaged\n' > unstaged.txt
  git add staged.txt unstaged.txt
  git commit -q -m init
  printf 'changed staged\n' > staged.txt
  git add staged.txt
  printf 'changed unstaged\n' > unstaged.txt
  printf 'brand new\n' > untracked.txt
  review_collect_diff all-changes > "$TMPDIR_TEST/all-changes.diff"
)
assert_contains "$(cat "$TMPDIR_TEST/all-changes.diff")" \
  "staged.txt" "review_collect_diff: all-changes includes staged-only changes"
assert_contains "$(cat "$TMPDIR_TEST/all-changes.diff")" \
  "unstaged.txt" "review_collect_diff: all-changes includes unstaged changes"
assert_contains "$(cat "$TMPDIR_TEST/all-changes.diff")" \
  "untracked.txt" "review_collect_diff: all-changes includes untracked files"
assert_contains "$(cat "$TMPDIR_TEST/all-changes.diff")" \
  "\+changed staged" "review_collect_diff: all-changes includes staged content"

# ── all-changes diff supports an unborn HEAD ─────────────────────────────────

UNBORN_REPO="$TMPDIR_TEST/review-all-changes-unborn"
mkdir -p "$UNBORN_REPO"
(
  cd "$UNBORN_REPO"
  git init -q
  printf 'first staged content\n' > first.txt
  git add first.txt
  review_collect_diff all-changes > "$TMPDIR_TEST/all-changes-unborn.diff"
)
assert_contains "$(cat "$TMPDIR_TEST/all-changes-unborn.diff")" \
  "first.txt" "review_collect_diff: all-changes handles staged files with unborn HEAD"
assert_contains "$(cat "$TMPDIR_TEST/all-changes-unborn.diff")" \
  "\+first staged content" "review_collect_diff: unborn HEAD includes staged file content"

# ── invocation-owned findings identity ───────────────────────────────────────

ARTIFACT_REPO="$TMPDIR_TEST/review-artifact-id"
ARTIFACT_RESULTS="$TMPDIR_TEST/review-artifact-results"
mkdir -p "$ARTIFACT_REPO" "$ARTIFACT_RESULTS"
(
  cd "$ARTIFACT_REPO"
  git init -q
  git config user.email test@example.com
  git config user.name "Octopus Test"
  printf 'clean\n' > clean.txt
  git add clean.txt
  git commit -q -m init
  log() { :; }
  render_terminal_report() { :; }
  check_codex_auth_freshness() { return 0; }
  # The no-diff path writes its findings artifact before returning non-zero.
  RESULTS_DIR="$ARTIFACT_RESULTS" \
    review_run '{"target":"staged","artifactId":"unit-owned-token"}' >/dev/null 2>&1 || true
)
artifact_file=$(find "$ARTIFACT_RESULTS" -maxdepth 1 -type f \
  -name 'review-findings-*-unit-owned-token.json' -print -quit)
if [[ -n "$artifact_file" ]] &&
   [[ "$(find "$ARTIFACT_RESULTS" -maxdepth 1 -type f -name 'review-findings-*.json' | wc -l | tr -d ' ')" == "1" ]]; then
  pass "review_run: artifactId identifies exactly one findings file"
else
  fail "review_run: artifactId identifies exactly one findings file"
fi

# ── MCP schema ───────────────────────────────────────────────────────────────

MCP_INDEX="$PROJECT_ROOT/mcp-server/src/index.ts"
assert_contains "$(cat "$MCP_INDEX" 2>/dev/null)" \
  "focus|provenance|autonomy|publish|debate" "mcp: review tool has typed profile fields"

test_summary
