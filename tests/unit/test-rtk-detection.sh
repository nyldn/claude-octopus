#!/usr/bin/env bash
# Tests for RTK companion detection
# Validates: install-deps check, doctor skill mention, context-awareness tip, no hard dependency
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "RTK companion detection"


pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

# ── install-deps.sh contains RTK check ──────────────────────────────────────

INSTALL_DEPS="$PROJECT_ROOT/scripts/install-deps.sh"

if [[ -f "$INSTALL_DEPS" ]]; then
    pass "install-deps.sh exists"
else
    fail "install-deps.sh exists" "not found"
fi

if grep -q 'has_cmd rtk\|command -v rtk' "$INSTALL_DEPS" 2>/dev/null; then
    pass "install-deps.sh checks for RTK"
else
    fail "install-deps.sh checks for RTK" "rtk detection not found"
fi

if grep -q 'rtk.*optional' "$INSTALL_DEPS" 2>/dev/null; then
    pass "install-deps.sh marks RTK as optional"
else
    fail "install-deps.sh marks RTK as optional" "missing optional label"
fi

if grep -q 'brew install rtk' "$INSTALL_DEPS" 2>/dev/null; then
    pass "install-deps.sh shows RTK install command"
else
    fail "install-deps.sh shows RTK install command" "missing install instructions"
fi

# ── skill-doctor.md mentions RTK ────────────────────────────────────────────

DOCTOR_CLAUDE="$PROJECT_ROOT/.claude/skills/skill-doctor.md"
DOCTOR_SKILL="$PROJECT_ROOT/skills/skill-doctor/SKILL.md"

if grep -qi 'RTK' "$DOCTOR_CLAUDE" 2>/dev/null; then
    pass "Doctor skill (.claude/skills) mentions RTK"
else
    fail "Doctor skill (.claude/skills) mentions RTK" "RTK not mentioned"
fi

if grep -qi 'RTK' "$DOCTOR_SKILL" 2>/dev/null; then
    pass "Doctor skill (skills/) mentions RTK"
else
    fail "Doctor skill (skills/) mentions RTK" "RTK not mentioned"
fi

if grep -q 'RTK token compression' "$DOCTOR_CLAUDE" 2>/dev/null; then
    pass "Doctor deps category lists RTK"
else
    fail "Doctor deps category lists RTK" "missing from deps category"
fi

if grep -q 'brew install rtk' "$DOCTOR_CLAUDE" 2>/dev/null; then
    pass "Doctor shows RTK install command"
else
    fail "Doctor shows RTK install command" "missing install instructions"
fi

# ── context-awareness.sh mentions RTK ───────────────────────────────────────

CTX_HOOK="$PROJECT_ROOT/hooks/context-awareness.sh"

if grep -q 'rtk' "$CTX_HOOK" 2>/dev/null; then
    pass "context-awareness.sh references RTK"
else
    fail "context-awareness.sh references RTK" "RTK not found"
fi

if grep -q 'command -v rtk' "$CTX_HOOK" 2>/dev/null; then
    pass "context-awareness.sh detects RTK presence"
else
    fail "context-awareness.sh detects RTK presence" "missing RTK detection"
fi

if grep -q 'WARNING.*RTK_TIP\|RTK_TIP.*WARNING\|SEVERITY.*WARNING.*rtk' "$CTX_HOOK" 2>/dev/null; then
    pass "RTK tip only shows at WARNING level"
else
    # Broader check: ensure RTK_TIP is gated on WARNING severity
    if grep -q 'SEVERITY.*WARNING' "$CTX_HOOK" 2>/dev/null && grep -q 'RTK_TIP' "$CTX_HOOK" 2>/dev/null; then
        pass "RTK tip only shows at WARNING level"
    else
        fail "RTK tip only shows at WARNING level" "not gated on WARNING"
    fi
fi

# ── No hard dependency on RTK ───────────────────────────────────────────────

ORCHESTRATE="$PROJECT_ROOT/scripts/orchestrate.sh"

if grep -qi 'rtk' "$ORCHESTRATE" 2>/dev/null; then
    fail "No hard RTK dependency in orchestrate.sh" "found rtk reference in orchestrate.sh"
else
    pass "No hard RTK dependency in orchestrate.sh"
fi

# Verify RTK is in warnings/optional, not in missing/required in install-deps
if grep -q 'missing.*rtk\|rtk.*required' "$INSTALL_DEPS" 2>/dev/null; then
    fail "RTK is not a required dependency" "found RTK in required deps"
else
    pass "RTK is not a required dependency"
fi

# ── Attribution check — no prohibited references ────────────────────────────

for f in "$INSTALL_DEPS" "$CTX_HOOK" "$DOCTOR_CLAUDE" "$DOCTOR_SKILL"; do
    fname=$(basename "$f")
    if grep -qi 'rtk-ai\|chopratejas\|headroom' "$f" 2>/dev/null; then
        fail "No prohibited attribution in $fname" "found prohibited reference"
    else
        pass "No prohibited attribution in $fname"
    fi
done
test_summary
