#!/usr/bin/env bash
# Tests for proactive skill suggestions in skill-context-detection.md
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "proactive skill suggestions in skill-context-detection.md"

SKILL="$PROJECT_ROOT/.claude/skills/skill-context-detection.md"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

# ── Section header present ────────────────────────────────────────────

if grep -q 'Proactive.*Suggestions' "$SKILL" 2>/dev/null; then
    pass "skill-context-detection.md mentions Proactive Suggestions"
else
    fail "skill-context-detection.md mentions Proactive Suggestions" "missing section header"
fi

# ── Suggestion mapping table ──────────────────────────────────────────

if grep -q 'Detected Context.*Suggestion' "$SKILL" 2>/dev/null; then
    pass "Contains suggestion mapping table header"
else
    fail "Contains suggestion mapping table header" "missing table header row"
fi

# ── At least 5 commands in suggestions ────────────────────────────────

CMD_COUNT=$(grep -cE '/octo:(brainstorm|plan|debug|tdd|review|deliver|research|security)' "$SKILL" 2>/dev/null || echo 0)
if [[ "$CMD_COUNT" -ge 5 ]]; then
    pass "Mentions at least 5 commands in suggestions ($CMD_COUNT found)"
else
    fail "Mentions at least 5 commands in suggestions" "only $CMD_COUNT found"
fi

# ── Opt-out mechanism ─────────────────────────────────────────────────

if grep -q 'OCTO_PROACTIVE_SUGGESTIONS' "$SKILL" 2>/dev/null; then
    pass "Mentions opt-out mechanism (OCTO_PROACTIVE_SUGGESTIONS)"
else
    fail "Mentions opt-out mechanism (OCTO_PROACTIVE_SUGGESTIONS)" "missing preference variable"
fi

# ── Persistent preferences ────────────────────────────────────────────

if grep -q 'preferences.json' "$SKILL" 2>/dev/null; then
    pass "Mentions persistent preferences file"
else
    fail "Mentions persistent preferences file" "missing preferences.json"
fi

# ── Re-enable mechanism ───────────────────────────────────────────────

if grep -qi 're-enable\|turn on tips\|be proactive' "$SKILL" 2>/dev/null; then
    pass "Mentions re-enable mechanism"
else
    fail "Mentions re-enable mechanism" "missing re-enable instructions"
fi

# ── Detection signals ─────────────────────────────────────────────────

if grep -q 'Detection Signals' "$SKILL" 2>/dev/null; then
    pass "Mentions detection signals section"
else
    fail "Mentions detection signals section" "missing Detection Signals"
fi

# ── Non-intrusive format ──────────────────────────────────────────────

if grep -qi 'non-intrusive' "$SKILL" 2>/dev/null; then
    pass "Mentions non-intrusive format"
else
    fail "Mentions non-intrusive format" "missing non-intrusive reference"
fi

# ── Dev mode vs knowledge work ────────────────────────────────────────

if grep -qi 'dev mode.*knowledge\|knowledge work' "$SKILL" 2>/dev/null; then
    pass "Mentions dev mode vs knowledge work distinction"
else
    fail "Mentions dev mode vs knowledge work distinction" "missing mode distinction"
fi

# ── Tool usage signal ─────────────────────────────────────────────────

if grep -q 'tool usage\|Bash calls' "$SKILL" 2>/dev/null; then
    pass "Detects work stage from tool usage patterns"
else
    fail "Detects work stage from tool usage patterns" "missing tool usage signal"
fi

# ── Git state signal ──────────────────────────────────────────────────

if grep -q 'Git state\|uncommitted' "$SKILL" 2>/dev/null; then
    pass "Detects work stage from git state"
else
    fail "Detects work stage from git state" "missing git state signal"
fi

# ── No attribution to gstack ─────────────────────────────────────────

if grep -qi 'gstack' "$SKILL" 2>/dev/null; then
    fail "No attribution references to gstack" "found gstack reference"
else
    pass "No attribution references to gstack"
fi
test_summary
