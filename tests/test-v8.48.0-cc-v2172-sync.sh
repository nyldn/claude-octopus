#!/bin/bash
# Test suite for v8.48.0 — Claude Code v2.1.72 feature detection sync
# Validates new SUPPORTS_* flags, detection blocks, wired integrations, and behavioral changes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/helpers/test-framework.sh"
test_suite "for v8.48.0 — Claude Code v2.1.72 feature detection sync"

PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ORCH="$PLUGIN_DIR/scripts/orchestrate.sh"
ALL_SRC=$(mktemp)
cat "$ORCH" "$PLUGIN_DIR/scripts/lib/"*.sh > "$ALL_SRC" 2>/dev/null
trap 'rm -f "$ALL_SRC"' EXIT

PASS=0
FAIL=0
TOTAL=0

pass() { test_case "$1"; test_pass; }

fail() { test_case "$1"; test_fail "${2:-$1}"; }

suite() {
  echo ""
  echo "━━━ $1 ━━━"
}

# ─────────────────────────────────────────────────────────────────────
# Suite 1: New flag declarations (8 flags for v2.1.72)
# ─────────────────────────────────────────────────────────────────────
suite "1. v8.48.0 Flag Declarations"

# 6 of original 8 flags pruned in v9.5 (banner-only). Only AGENT_MODEL_OVERRIDE, EFFORT_REDESIGN, DISABLE_CRON_ENV kept.
for flag in SUPPORTS_AGENT_MODEL_OVERRIDE \
            SUPPORTS_EFFORT_REDESIGN SUPPORTS_DISABLE_CRON_ENV; do
  if grep -q "^${flag}=false" "$ALL_SRC"; then
    pass "$flag declared"
  else
    fail "$flag not declared in orchestrate.sh"
  fi
done

# Pruned flags should be gone
for flag in SUPPORTS_EXIT_WORKTREE \
            SUPPORTS_HIDDEN_HTML_COMMENTS SUPPORTS_BASH_ALLOWLIST_V2 \
            SUPPORTS_CLEAR_PRESERVES_BG SUPPORTS_TEAM_MODEL_INHERIT_FIX; do
  if grep -q "^${flag}=false" "$ALL_SRC"; then
    fail "$flag should have been pruned but still declared"
  else
    pass "$flag correctly pruned"
  fi
done

# ─────────────────────────────────────────────────────────────────────
# Suite 2: v2.1.72 detection block
# ─────────────────────────────────────────────────────────────────────
suite "2. v2.1.72 Detection Block"

if grep -q 'version_compare.*2\.1\.72' "$ALL_SRC"; then
  pass "v2.1.72 version_compare block exists"
else
  fail "v2.1.72 version_compare block missing"
fi

# Remaining flags should be set in the v2.1.72 block (6 pruned in v9.5, 4 kept + PARALLEL_TOOL_RESILIENCE)
for flag in SUPPORTS_AGENT_MODEL_OVERRIDE \
            SUPPORTS_EFFORT_REDESIGN SUPPORTS_DISABLE_CRON_ENV \
            SUPPORTS_PARALLEL_TOOL_RESILIENCE; do
  if grep -A 15 'version_compare.*2\.1\.72' "$ALL_SRC" | grep -q "${flag}=true"; then
    pass "$flag set in v2.1.72 block"
  else
    fail "$flag not set in v2.1.72 block"
  fi
done

# ─────────────────────────────────────────────────────────────────────
# Suite 3: Log lines for new flags
# ─────────────────────────────────────────────────────────────────────
suite "3. Log Lines"

# After v9.5 pruning, banner line consolidated: Agent Model Override | Effort Redesign | Disable Cron Env
if grep -q 'Agent Model Override.*Effort Redesign.*Disable Cron Env' "$ALL_SRC"; then
  pass "v2.1.72 remaining flags logged"
else
  fail "v2.1.72 remaining flags not logged"
fi

# Pruned flags should NOT be in log lines
if grep -q 'Exit Worktree:.*SUPPORTS_EXIT_WORKTREE' "$ALL_SRC"; then
  fail "Pruned Exit Worktree still in log lines"
else
  pass "Pruned Exit Worktree removed from log lines"
fi

if grep -q 'Clear Preserves BG:.*SUPPORTS_CLEAR_PRESERVES_BG' "$ALL_SRC"; then
  fail "Pruned Clear Preserves BG still in log lines"
else
  pass "Pruned Clear Preserves BG removed from log lines"
fi

# ─────────────────────────────────────────────────────────────────────
# Suite 4: Effort redesign symbols wired
# ─────────────────────────────────────────────────────────────────────
suite "4. Effort Redesign Integration"

if grep -q 'SUPPORTS_EFFORT_REDESIGN.*true' "$ALL_SRC"; then
  pass "Effort redesign gated by SUPPORTS_EFFORT_REDESIGN"
else
  fail "Effort redesign not gated by flag"
fi

# Check all three v2.1.72 effort symbols are present
for symbol in '○' '◐' '●'; do
  if grep -q "$symbol" "$ALL_SRC"; then
    pass "Effort symbol $symbol present"
  else
    fail "Effort symbol $symbol missing"
  fi
done

# Verify effort levels are low/medium/high only (no "max")
# Use grep -c with || true to avoid pipefail issues
max_in_effort=0
while IFS= read -r line; do
  ((max_in_effort++)) || true
done < <(grep -n 'effort.*"max"\|effort_level.*max' "$ALL_SRC" 2>/dev/null | grep -v '#.*max\|comment\|OCTOPUS_MAX' 2>/dev/null || true)
if [[ "$max_in_effort" -eq 0 ]]; then
  pass "No 'max' effort level in effort mapping (v2.1.72 compat)"
else
  fail "Found $max_in_effort 'max' effort level references — v2.1.72 removed max"
fi

# ─────────────────────────────────────────────────────────────────────
# Suite 5: CLAUDE_CODE_DISABLE_CRON wired in workflows
# ─────────────────────────────────────────────────────────────────────
suite "5. Cron Disable Integration"

if grep -A 5 'embrace_full_workflow()' "$ALL_SRC" | head -20 | grep -q 'CLAUDE_CODE_DISABLE_CRON' || \
   grep -B 2 -A 3 'SUPPORTS_DISABLE_CRON_ENV' "$ALL_SRC" | grep -q 'CLAUDE_CODE_DISABLE_CRON'; then
  pass "CLAUDE_CODE_DISABLE_CRON set in embrace workflow"
else
  fail "CLAUDE_CODE_DISABLE_CRON not set in embrace workflow"
fi

# Check cron var is cleaned up at end of embrace
embrace_cleanup_count=$(grep -c 'unset CLAUDE_CODE_DISABLE_CRON' "$ALL_SRC" || echo 0)
if [[ "$embrace_cleanup_count" -ge 2 ]]; then
  pass "CLAUDE_CODE_DISABLE_CRON cleaned up ($embrace_cleanup_count locations)"
else
  fail "CLAUDE_CODE_DISABLE_CRON cleanup missing (found $embrace_cleanup_count, expected >= 2)"
fi

if grep -A 10 'parallel_execute()' "$ALL_SRC" | grep -q 'CLAUDE_CODE_DISABLE_CRON'; then
  pass "CLAUDE_CODE_DISABLE_CRON set in parallel_execute"
else
  fail "CLAUDE_CODE_DISABLE_CRON not set in parallel_execute"
fi

# ─────────────────────────────────────────────────────────────────────
# Suite 6: Agent model override in Agent Teams JSON
# ─────────────────────────────────────────────────────────────────────
suite "6. Agent Model Override Integration"

if grep -q 'model_override_supported' "$ALL_SRC"; then
  pass "model_override_supported field in Agent Teams JSON"
else
  fail "model_override_supported field missing from Agent Teams JSON"
fi

if grep -q 'SUPPORTS_AGENT_MODEL_OVERRIDE' "$ALL_SRC" | head -1; then
  pass "SUPPORTS_AGENT_MODEL_OVERRIDE referenced in dispatch"
else
  # Broader check
  ref_count=$(grep -c 'SUPPORTS_AGENT_MODEL_OVERRIDE' "$ALL_SRC" || echo 0)
  if [[ "$ref_count" -ge 3 ]]; then
    pass "SUPPORTS_AGENT_MODEL_OVERRIDE referenced $ref_count times"
  else
    fail "SUPPORTS_AGENT_MODEL_OVERRIDE under-referenced ($ref_count refs)"
  fi
fi

# ─────────────────────────────────────────────────────────────────────
# Suite 7: Header comment updated
# ─────────────────────────────────────────────────────────────────────
suite "7. Header Comment"

if grep -q 'v2\.1\.72' "$ALL_SRC"; then
  pass "v2.1.72 referenced in header comment"
else
  fail "v2.1.72 not referenced in header"
fi

# ─────────────────────────────────────────────────────────────────────
# Suite 8: Total flag count (should be >= 80 with 8 new flags)
# ─────────────────────────────────────────────────────────────────────
suite "8. Total Flag Count"

FLAG_COUNT=$(grep -c '^SUPPORTS_.*=false' "$ALL_SRC")
if [[ "$FLAG_COUNT" -ge 80 ]]; then
  pass "Total SUPPORTS_* flags: $FLAG_COUNT (expected >= 80)"
else
  fail "Total SUPPORTS_* flags: $FLAG_COUNT (expected >= 80)"
fi

# ─────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────
test_summary
