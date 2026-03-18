#!/usr/bin/env bash
# Tests for v9.6.0 enhanced HUD — gradient bar, warning indicators, agent display, project state
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HUD="$PROJECT_ROOT/hooks/octopus-hud.mjs"
STATUSLINE="$PROJECT_ROOT/hooks/octopus-statusline.sh"

TEST_COUNT=0; PASS_COUNT=0; FAIL_COUNT=0
pass() { TEST_COUNT=$((TEST_COUNT+1)); PASS_COUNT=$((PASS_COUNT+1)); echo "PASS: $1"; }
fail() { TEST_COUNT=$((TEST_COUNT+1)); FAIL_COUNT=$((FAIL_COUNT+1)); echo "FAIL: $1 — $2"; }

# ── Gradient bar characters ─────────────────────────────────────────

if grep -qE '▰|25B0' "$HUD" 2>/dev/null; then
    pass "HUD uses ▰ filled gradient char"
else
    fail "HUD uses ▰ filled gradient char" "missing U+25B0"
fi

if grep -qE '▱|25B1' "$HUD" 2>/dev/null; then
    pass "HUD uses ▱ empty gradient char"
else
    fail "HUD uses ▱ empty gradient char" "missing U+25B1"
fi

if grep -q '▰' "$STATUSLINE" 2>/dev/null; then
    pass "Bash fallback uses ▰ gradient char"
else
    fail "Bash fallback uses ▰ gradient char" "missing in statusline.sh"
fi

# ── Warning indicators ──────────────────────────────────────────────

if grep -q '💀\|\\u{1F480}' "$HUD" 2>/dev/null; then
    pass "HUD has skull emoji for >=90%"
else
    fail "HUD has skull emoji for >=90%" "missing skull indicator"
fi

if grep -q '⚠\|\\u26A0' "$HUD" 2>/dev/null; then
    pass "HUD has warning emoji for >=80%"
else
    fail "HUD has warning emoji for >=80%" "missing warning indicator"
fi

if grep -q '💀' "$STATUSLINE" 2>/dev/null; then
    pass "Bash fallback has skull emoji"
else
    fail "Bash fallback has skull emoji" "missing in statusline.sh"
fi

if grep -q '⚠' "$STATUSLINE" 2>/dev/null; then
    pass "Bash fallback has warning emoji"
else
    fail "Bash fallback has warning emoji" "missing in statusline.sh"
fi

# ── 80% threshold ───────────────────────────────────────────────────

if grep -qE 'pct >= 80|PCT.*-ge 80|80' "$HUD" 2>/dev/null; then
    pass "HUD has 80% threshold"
else
    fail "HUD has 80% threshold" "missing 80 check"
fi

if grep -qE '90.*80|80.*90|-ge 80|-ge 90' "$STATUSLINE" 2>/dev/null; then
    pass "Bash fallback has 80/90 thresholds"
else
    fail "Bash fallback has 80/90 thresholds" "missing threshold checks"
fi

# ── readProgress function ────────────────────────────────────────────

if grep -q 'readProgress' "$HUD" 2>/dev/null; then
    pass "HUD has readProgress() function"
else
    fail "HUD has readProgress() function" "missing"
fi

if grep -q 'progress.*cache\|_progressCache' "$HUD" 2>/dev/null; then
    pass "readProgress has cache for performance"
else
    fail "readProgress has cache for performance" "missing cache"
fi

# ── activeAgentName function ─────────────────────────────────────────

if grep -q 'activeAgentName' "$HUD" 2>/dev/null; then
    pass "HUD has activeAgentName() function"
else
    fail "HUD has activeAgentName() function" "missing"
fi

if grep -q 'running' "$HUD" 2>/dev/null; then
    pass "activeAgentName checks for running status"
else
    fail "activeAgentName checks for running status" "missing status check"
fi

# ── readProjectState function ────────────────────────────────────────

if grep -q 'readProjectState' "$HUD" 2>/dev/null; then
    pass "HUD has readProjectState() function"
else
    fail "HUD has readProjectState() function" "missing"
fi

if grep -q 'STATE.md' "$HUD" 2>/dev/null; then
    pass "readProjectState reads .octo/STATE.md"
else
    fail "readProjectState reads .octo/STATE.md" "missing STATE.md reference"
fi

# ── Agent name in statusline segment ─────────────────────────────────

if grep -q 'runningAgent' "$HUD" 2>/dev/null; then
    pass "HUD displays running agent name in segments"
else
    fail "HUD displays running agent name in segments" "missing runningAgent"
fi

# ── Project task in idle statusline ──────────────────────────────────

if grep -q 'projectTask' "$HUD" 2>/dev/null; then
    pass "HUD shows project task when no workflow active"
else
    fail "HUD shows project task when no workflow active" "missing projectTask"
fi

# ── Octopus branding ────────────────────────────────────────────────

if grep -qE 'Octopus\]|1F419' "$HUD" 2>/dev/null; then
    pass "HUD uses 🐙 Octopus branding"
else
    fail "HUD uses 🐙 Octopus branding" "missing octopus emoji/text"
fi

echo ""
echo "═══════════════════════════════════════════════════"
echo "enhanced-hud: $PASS_COUNT/$TEST_COUNT passed"
[[ $FAIL_COUNT -gt 0 ]] && echo "FAILURES: $FAIL_COUNT" && exit 1
echo "All tests passed."
