#!/usr/bin/env bash
# Tests for v9.6.0 workflow-aware context awareness hook
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$PROJECT_ROOT/hooks/context-awareness.sh"

TEST_COUNT=0; PASS_COUNT=0; FAIL_COUNT=0
pass() { TEST_COUNT=$((TEST_COUNT+1)); PASS_COUNT=$((PASS_COUNT+1)); echo "PASS: $1"; }
fail() { TEST_COUNT=$((TEST_COUNT+1)); FAIL_COUNT=$((FAIL_COUNT+1)); echo "FAIL: $1 — $2"; }

# ── Three severity levels ───────────────────────────────────────────

if grep -q 'AUTO_COMPACT' "$HOOK" 2>/dev/null; then
    pass "Has AUTO_COMPACT severity level"
else
    fail "Has AUTO_COMPACT severity level" "missing AUTO_COMPACT"
fi

if grep -q 'CRITICAL' "$HOOK" 2>/dev/null; then
    pass "Has CRITICAL severity level"
else
    fail "Has CRITICAL severity level" "missing CRITICAL"
fi

if grep -q 'WARNING' "$HOOK" 2>/dev/null; then
    pass "Has WARNING severity level"
else
    fail "Has WARNING severity level" "missing WARNING"
fi

# ── 80% threshold ───────────────────────────────────────────────────

if grep -qE '\-ge 80|>= 80' "$HOOK" 2>/dev/null; then
    pass "Has 80% AUTO_COMPACT threshold"
else
    fail "Has 80% AUTO_COMPACT threshold" "missing 80 check"
fi

# ── Reads session.json for workflow state ────────────────────────────

if grep -q 'session.json' "$HOOK" 2>/dev/null; then
    pass "Reads session.json for workflow state"
else
    fail "Reads session.json for workflow state" "missing session.json reference"
fi

if grep -q 'current_phase' "$HOOK" 2>/dev/null; then
    pass "Extracts current_phase from session"
else
    fail "Extracts current_phase from session" "missing current_phase"
fi

# ── Phase-specific advice ───────────────────────────────────────────

if grep -q 'probe\|grasp' "$HOOK" 2>/dev/null; then
    pass "Has advice for probe/grasp phases"
else
    fail "Has advice for probe/grasp phases" "missing research phase advice"
fi

if grep -q 'tangle' "$HOOK" 2>/dev/null; then
    pass "Has advice for tangle phase"
else
    fail "Has advice for tangle phase" "missing implementation phase advice"
fi

if grep -q 'ink' "$HOOK" 2>/dev/null; then
    pass "Has advice for ink phase"
else
    fail "Has advice for ink phase" "missing validation phase advice"
fi

# ── Workflow-specific command suggestions ────────────────────────────

if grep -q '/octo:quick\|/octo:develop' "$HOOK" 2>/dev/null; then
    pass "Suggests Octopus commands in advice"
else
    fail "Suggests Octopus commands in advice" "missing /octo: command suggestions"
fi

# ── Octopus branding ────────────────────────────────────────────────

if grep -q '🐙' "$HOOK" 2>/dev/null; then
    pass "Messages use 🐙 branding"
else
    fail "Messages use 🐙 branding" "missing octopus emoji"
fi

# ── Debounce mechanism preserved ────────────────────────────────────

if grep -q 'debounce' "$HOOK" 2>/dev/null; then
    pass "Debounce mechanism present"
else
    fail "Debounce mechanism present" "missing debounce"
fi

if grep -qE 'COUNT.*%.*5|5.*tool' "$HOOK" 2>/dev/null; then
    pass "Fires every 5 tool calls"
else
    fail "Fires every 5 tool calls" "missing modulo-5 pattern"
fi

# ── Severity escalation preserved ───────────────────────────────────

if grep -qi 'escalat' "$HOOK" 2>/dev/null; then
    pass "Severity escalation bypass present"
else
    fail "Severity escalation bypass present" "missing escalation"
fi

echo ""
echo "═══════════════════════════════════════════════════"
echo "context-awareness-v2: $PASS_COUNT/$TEST_COUNT passed"
[[ $FAIL_COUNT -gt 0 ]] && echo "FAILURES: $FAIL_COUNT" && exit 1
echo "All tests passed."
