#!/usr/bin/env bash
# Tests for session handoff — write-handoff.sh and integration with hooks
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "session handoff — write-handoff.sh and integration with hooks"

HANDOFF="$PROJECT_ROOT/scripts/write-handoff.sh"
PRE_COMPACT="$PROJECT_ROOT/hooks/pre-compact.sh"
SESSION_END="$PROJECT_ROOT/hooks/session-end.sh"
RESUME_SKILL="$PROJECT_ROOT/.claude/skills/skill-resume.md"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

# ── write-handoff.sh exists and is executable ────────────────────────

if [[ -f "$HANDOFF" ]]; then
    pass "write-handoff.sh exists"
else
    fail "write-handoff.sh exists" "file not found"
fi

if [[ -x "$HANDOFF" ]]; then
    pass "write-handoff.sh is executable"
else
    fail "write-handoff.sh is executable" "not executable"
fi

# ── Reads session.json ──────────────────────────────────────────────

if grep -q 'session.json' "$HANDOFF" 2>/dev/null; then
    pass "write-handoff.sh reads session.json"
else
    fail "write-handoff.sh reads session.json" "missing session.json reference"
fi

# ── Reads STATE.md ──────────────────────────────────────────────────

if grep -q 'STATE.md' "$HANDOFF" 2>/dev/null; then
    pass "write-handoff.sh reads STATE.md"
else
    fail "write-handoff.sh reads STATE.md" "missing STATE.md reference"
fi

# ── Writes .octo-continue.md ─────────────────────────────────────

if grep -q 'octo-continue.md' "$HANDOFF" 2>/dev/null; then
    pass "write-handoff.sh writes .octo-continue.md"
else
    fail "write-handoff.sh writes .octo-continue.md" "missing output filename"
fi

# ── Has octopus branding ────────────────────────────────────────────

if grep -q '🐙' "$HANDOFF" 2>/dev/null; then
    pass "write-handoff.sh uses 🐙 branding"
else
    fail "write-handoff.sh uses 🐙 branding" "missing octopus emoji"
fi

# ── Includes resume instructions ────────────────────────────────────

if grep -q '/octo:resume' "$HANDOFF" 2>/dev/null; then
    pass "write-handoff.sh includes /octo:resume instructions"
else
    fail "write-handoff.sh includes /octo:resume instructions" "missing resume"
fi

# ── Pre-compact calls write-handoff.sh ──────────────────────────────

if grep -q 'write-handoff.sh' "$PRE_COMPACT" 2>/dev/null; then
    pass "pre-compact.sh calls write-handoff.sh"
else
    fail "pre-compact.sh calls write-handoff.sh" "not wired in pre-compact"
fi

# ── Session-end calls write-handoff.sh ──────────────────────────────

if grep -q 'write-handoff.sh' "$SESSION_END" 2>/dev/null; then
    pass "session-end.sh calls write-handoff.sh"
else
    fail "session-end.sh calls write-handoff.sh" "not wired in session-end"
fi

# ── Resume skill reads .octo-continue.md ─────────────────────────

if grep -q 'octo-continue.md' "$RESUME_SKILL" 2>/dev/null; then
    pass "skill-resume.md reads .octo-continue.md"
else
    fail "skill-resume.md reads .octo-continue.md" "not wired in resume skill"
fi

# ── Extracts decisions and blockers ─────────────────────────────────

if grep -q 'decisions' "$HANDOFF" 2>/dev/null; then
    pass "write-handoff.sh extracts decisions"
else
    fail "write-handoff.sh extracts decisions" "missing decisions extraction"
fi

if grep -q 'blockers' "$HANDOFF" 2>/dev/null; then
    pass "write-handoff.sh extracts blockers"
else
    fail "write-handoff.sh extracts blockers" "missing blockers extraction"
fi
test_summary
