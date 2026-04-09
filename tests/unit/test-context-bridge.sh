#!/usr/bin/env bash
# Tests for context bridge — verify bridge write in statusline hooks
# and context-awareness.sh exists with threshold patterns
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOKS_DIR="$PROJECT_ROOT/hooks"

TEST_COUNT=0; PASS_COUNT=0; FAIL_COUNT=0
pass() { TEST_COUNT=$((TEST_COUNT+1)); PASS_COUNT=$((PASS_COUNT+1)); echo "PASS: $1"; }
fail() { TEST_COUNT=$((TEST_COUNT+1)); FAIL_COUNT=$((FAIL_COUNT+1)); echo "FAIL: $1 — $2"; }

# ── Bridge write in bash statusline ─────────────────────────────────────────

if grep -q 'octopus-ctx-' "$HOOKS_DIR/octopus-statusline.sh" 2>/dev/null; then
    pass "octopus-statusline.sh writes bridge file"
else
    fail "octopus-statusline.sh writes bridge file" "no octopus-ctx- pattern"
fi

if grep -q 'used_pct' "$HOOKS_DIR/octopus-statusline.sh" 2>/dev/null; then
    pass "octopus-statusline.sh bridge has used_pct field"
else
    fail "octopus-statusline.sh bridge has used_pct field" "missing used_pct"
fi

# ── Bridge write in Node.js HUD ────────────────────────────────────────────

if grep -q 'octopus-ctx-' "$HOOKS_DIR/octopus-hud.mjs" 2>/dev/null; then
    pass "octopus-hud.mjs writes bridge file"
else
    fail "octopus-hud.mjs writes bridge file" "no octopus-ctx- pattern"
fi

if grep -q 'used_pct' "$HOOKS_DIR/octopus-hud.mjs" 2>/dev/null; then
    pass "octopus-hud.mjs bridge has used_pct field"
else
    fail "octopus-hud.mjs bridge has used_pct field" "missing used_pct"
fi

# ── context-awareness.sh exists ─────────────────────────────────────────────

AWARENESS="$HOOKS_DIR/context-awareness.sh"
if [[ -f "$AWARENESS" ]]; then
    pass "context-awareness.sh exists"
else
    fail "context-awareness.sh exists" "file not found"
    echo ""; echo "FAILURES: $FAIL_COUNT"; exit 1
fi

if [[ -x "$AWARENESS" ]]; then
    pass "context-awareness.sh is executable"
else
    fail "context-awareness.sh is executable" "not executable"
fi

# ── Threshold patterns in context-awareness.sh ──────────────────────────────

if grep -q '65' "$AWARENESS" && grep -q '75' "$AWARENESS"; then
    pass "context-awareness.sh has 65/75 thresholds"
else
    fail "context-awareness.sh has 65/75 thresholds" "missing threshold values"
fi

if grep -q 'WARNING' "$AWARENESS" && grep -q 'CRITICAL' "$AWARENESS"; then
    pass "context-awareness.sh has WARNING/CRITICAL severity levels"
else
    fail "context-awareness.sh has WARNING/CRITICAL severity levels" "missing severity"
fi

# ── Debounce mechanism ──────────────────────────────────────────────────────

if grep -q 'debounce' "$AWARENESS" 2>/dev/null; then
    pass "context-awareness.sh has debounce mechanism"
else
    fail "context-awareness.sh has debounce mechanism" "no debounce pattern"
fi

if grep -qE 'COUNT.*%.*5|5.*tool' "$AWARENESS" 2>/dev/null; then
    pass "context-awareness.sh fires every 5 tool calls"
else
    fail "context-awareness.sh fires every 5 tool calls" "missing modulo-5 pattern"
fi

# ── Severity escalation bypasses debounce ───────────────────────────────────

if grep -qi 'escalat' "$AWARENESS" 2>/dev/null; then
    pass "context-awareness.sh has severity escalation bypass"
else
    fail "context-awareness.sh has severity escalation bypass" "no escalation pattern"
fi

# ── Hook exists on disk (not registered in hooks.json — opt-in only) ────────

if [[ -x "$PROJECT_ROOT/hooks/context-awareness.sh" ]]; then
    pass "context-awareness.sh exists and is executable"
else
    fail "context-awareness.sh exists and is executable" "not found or not executable"
fi

echo ""
echo "═══════════════════════════════════════════════════"
echo "context-bridge: $PASS_COUNT/$TEST_COUNT passed"
[[ $FAIL_COUNT -gt 0 ]] && echo "FAILURES: $FAIL_COUNT" && exit 1
echo "All tests passed."
