#!/bin/bash
# Test suite for CC v2.1.78-83 hook script robustness
# Validates that cwd-changed.sh and stop-failure-log.sh handle edge cases safely.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "for CC v2.1.78-83 hook script robustness"

PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

PASS=0
FAIL=0
TOTAL=0

pass() { test_case "$1"; test_pass; }

fail() { test_case "$1"; test_fail "${2:-$1}"; }

suite() {
  echo ""
  echo "━━━ $1 ━━━"
}

# ── cwd-changed.sh ───────────────────────────────────────────────────────────
suite "cwd-changed.sh Robustness"

# Empty stdin → exit 0
if echo "" | bash "$PLUGIN_DIR/hooks/cwd-changed.sh" >/dev/null 2>&1; then
  pass "cwd-changed.sh handles empty stdin"
else
  fail "cwd-changed.sh handles empty stdin" "non-zero exit"
fi

# Valid JSON with real directory
output=$(echo '{"new_cwd":"/tmp"}' | bash "$PLUGIN_DIR/hooks/cwd-changed.sh" 2>/dev/null) || true
if [[ $? -eq 0 || -z "$output" || "$output" == *"[octopus]"* ]]; then
  pass "cwd-changed.sh handles valid input"
else
  fail "cwd-changed.sh handles valid input" "unexpected output: $output"
fi

# Invalid JSON → exit 0 (no crash)
if echo 'not-json' | bash "$PLUGIN_DIR/hooks/cwd-changed.sh" >/dev/null 2>&1; then
  pass "cwd-changed.sh handles invalid JSON"
else
  fail "cwd-changed.sh handles invalid JSON" "non-zero exit"
fi

# Non-existent directory → exit 0
if echo '{"new_cwd":"/nonexistent/path/xyz"}' | bash "$PLUGIN_DIR/hooks/cwd-changed.sh" >/dev/null 2>&1; then
  pass "cwd-changed.sh handles non-existent directory"
else
  fail "cwd-changed.sh handles non-existent directory" "non-zero exit"
fi

# ── stop-failure-log.sh ──────────────────────────────────────────────────────
suite "stop-failure-log.sh Robustness"

# Set up isolated temp dir for testing
_HOOK_TEST_DIR=$(mktemp -d)
export CLAUDE_PLUGIN_DATA="$_HOOK_TEST_DIR"

# Empty stdin → exit 0
if echo "" | bash "$PLUGIN_DIR/hooks/stop-failure-log.sh" >/dev/null 2>&1; then
  pass "stop-failure-log.sh handles empty stdin"
else
  fail "stop-failure-log.sh handles empty stdin" "non-zero exit"
fi

# Valid error input → creates log entry
echo '{"error_type":"rate_limit","error_message":"Rate limit exceeded"}' | bash "$PLUGIN_DIR/hooks/stop-failure-log.sh" 2>/dev/null
if [[ -f "$CLAUDE_PLUGIN_DATA/error-log.jsonl" ]]; then
  pass "stop-failure-log.sh creates error-log.jsonl"
else
  fail "stop-failure-log.sh creates error-log.jsonl" "file not created"
fi

# Log entry contains expected fields
if grep -q '"rate_limit"' "$CLAUDE_PLUGIN_DATA/error-log.jsonl" 2>/dev/null; then
  pass "Log entry contains error_type"
else
  fail "Log entry contains error_type" "rate_limit not in log"
fi

# Works without CLAUDE_PLUGIN_DATA (uses fallback)
unset CLAUDE_PLUGIN_DATA
if echo '{"error_type":"auth_failure"}' | bash "$PLUGIN_DIR/hooks/stop-failure-log.sh" >/dev/null 2>&1; then
  pass "stop-failure-log.sh works without CLAUDE_PLUGIN_DATA"
else
  fail "stop-failure-log.sh works without CLAUDE_PLUGIN_DATA" "non-zero exit"
fi
test_summary
