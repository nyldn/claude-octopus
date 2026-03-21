#!/usr/bin/env bash
# Tests for hook profile system: hook-profile.sh library, run-with-profile.sh dispatcher
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TEST_COUNT=0; PASS_COUNT=0; FAIL_COUNT=0
pass() { TEST_COUNT=$((TEST_COUNT+1)); PASS_COUNT=$((PASS_COUNT+1)); echo "PASS: $1"; }
fail() { TEST_COUNT=$((TEST_COUNT+1)); FAIL_COUNT=$((FAIL_COUNT+1)); echo "FAIL: $1 — $2"; }

HOOK_PROFILE_LIB="$PROJECT_ROOT/scripts/lib/hook-profile.sh"
RUN_WITH_PROFILE="$PROJECT_ROOT/scripts/run-with-profile.sh"
DOCTOR_SKILL="$PROJECT_ROOT/.claude/skills/skill-doctor.md"

# ── File existence and syntax ────────────────────────────────────────────────

if [[ -f "$HOOK_PROFILE_LIB" ]]; then
    pass "hook-profile.sh exists"
else
    fail "hook-profile.sh exists" "file not found"
    echo ""; echo "FAILURES: $FAIL_COUNT"; exit 1
fi

if bash -n "$HOOK_PROFILE_LIB" 2>/dev/null; then
    pass "hook-profile.sh has valid bash syntax"
else
    fail "hook-profile.sh has valid bash syntax" "syntax errors"
fi

if [[ -f "$RUN_WITH_PROFILE" ]]; then
    pass "run-with-profile.sh exists"
else
    fail "run-with-profile.sh exists" "file not found"
fi

if [[ -x "$RUN_WITH_PROFILE" ]]; then
    pass "run-with-profile.sh is executable"
else
    fail "run-with-profile.sh is executable" "not executable"
fi

if bash -n "$RUN_WITH_PROFILE" 2>/dev/null; then
    pass "run-with-profile.sh has valid bash syntax"
else
    fail "run-with-profile.sh has valid bash syntax" "syntax errors"
fi

# ── Source the library for functional tests ──────────────────────────────────

# Reset guard so we can source fresh
unset _OCTOPUS_HOOK_PROFILE_LOADED
source "$HOOK_PROFILE_LIB"

# ── minimal profile: session hooks enabled ───────────────────────────────────

OCTO_HOOK_PROFILE=minimal OCTO_DISABLED_HOOKS="" \
  is_hook_enabled "session-start-memory" && \
    pass "minimal: session-start-memory enabled" || \
    fail "minimal: session-start-memory enabled" "returned 1"

OCTO_HOOK_PROFILE=minimal OCTO_DISABLED_HOOKS="" \
  is_hook_enabled "octopus-statusline" && \
    pass "minimal: octopus-statusline enabled" || \
    fail "minimal: octopus-statusline enabled" "returned 1"

# ── minimal profile: non-session hooks disabled ──────────────────────────────

if OCTO_HOOK_PROFILE=minimal OCTO_DISABLED_HOOKS="" is_hook_enabled "code-quality-gate"; then
    fail "minimal: code-quality-gate disabled" "returned 0"
else
    pass "minimal: code-quality-gate disabled"
fi

if OCTO_HOOK_PROFILE=minimal OCTO_DISABLED_HOOKS="" is_hook_enabled "context-awareness"; then
    fail "minimal: context-awareness disabled" "returned 0"
else
    pass "minimal: context-awareness disabled"
fi

# ── standard profile: quality gates disabled ─────────────────────────────────

if OCTO_HOOK_PROFILE=standard OCTO_DISABLED_HOOKS="" is_hook_enabled "security-gate"; then
    fail "standard: security-gate disabled" "returned 0"
else
    pass "standard: security-gate disabled"
fi

if OCTO_HOOK_PROFILE=standard OCTO_DISABLED_HOOKS="" is_hook_enabled "architecture-gate"; then
    fail "standard: architecture-gate disabled" "returned 0"
else
    pass "standard: architecture-gate disabled"
fi

# ── standard profile: non-gate hooks enabled ─────────────────────────────────

OCTO_HOOK_PROFILE=standard OCTO_DISABLED_HOOKS="" \
  is_hook_enabled "session-start-memory" && \
    pass "standard: session-start-memory enabled" || \
    fail "standard: session-start-memory enabled" "returned 1"

OCTO_HOOK_PROFILE=standard OCTO_DISABLED_HOOKS="" \
  is_hook_enabled "context-awareness" && \
    pass "standard: context-awareness enabled" || \
    fail "standard: context-awareness enabled" "returned 1"

# ── strict profile: everything enabled ───────────────────────────────────────

OCTO_HOOK_PROFILE=strict OCTO_DISABLED_HOOKS="" \
  is_hook_enabled "security-gate" && \
    pass "strict: security-gate enabled" || \
    fail "strict: security-gate enabled" "returned 1"

OCTO_HOOK_PROFILE=strict OCTO_DISABLED_HOOKS="" \
  is_hook_enabled "code-quality-gate" && \
    pass "strict: code-quality-gate enabled" || \
    fail "strict: code-quality-gate enabled" "returned 1"

# ── OCTO_DISABLED_HOOKS override ─────────────────────────────────────────────

if OCTO_HOOK_PROFILE=strict OCTO_DISABLED_HOOKS="session-start-memory,octopus-statusline" is_hook_enabled "session-start-memory"; then
    fail "OCTO_DISABLED_HOOKS overrides strict for session-start-memory" "returned 0"
else
    pass "OCTO_DISABLED_HOOKS overrides strict for session-start-memory"
fi

OCTO_HOOK_PROFILE=strict OCTO_DISABLED_HOOKS="session-start-memory,octopus-statusline" \
  is_hook_enabled "security-gate" && \
    pass "OCTO_DISABLED_HOOKS does not affect non-listed hooks" || \
    fail "OCTO_DISABLED_HOOKS does not affect non-listed hooks" "returned 1"

# ── get_hook_profile default ─────────────────────────────────────────────────

unset OCTO_HOOK_PROFILE
if [[ "$(get_hook_profile)" == "standard" ]]; then
    pass "get_hook_profile defaults to standard"
else
    fail "get_hook_profile defaults to standard" "got: $(get_hook_profile)"
fi

# ── skill-doctor.md mentions hook profile ────────────────────────────────────

if grep -q 'Hook Profile' "$DOCTOR_SKILL" 2>/dev/null; then
    pass "skill-doctor.md has Hook Profile section"
else
    fail "skill-doctor.md has Hook Profile section" "section not found"
fi

if grep -q 'OCTO_HOOK_PROFILE' "$DOCTOR_SKILL" 2>/dev/null; then
    pass "skill-doctor.md references OCTO_HOOK_PROFILE env var"
else
    fail "skill-doctor.md references OCTO_HOOK_PROFILE env var" "env var not mentioned"
fi

# ── No attribution references ────────────────────────────────────────────────

for f in "$HOOK_PROFILE_LIB" "$RUN_WITH_PROFILE"; do
    fname="$(basename "$f")"
    if grep -qiE 'ecc|STRATEGIC_REVIEW' "$f" 2>/dev/null; then
        fail "$fname: no attribution references" "found prohibited reference"
    else
        pass "$fname: no attribution references"
    fi
done

echo ""
echo "═══════════════════════════════════════════════════"
echo "hook-profile: $PASS_COUNT/$TEST_COUNT passed"
[[ $FAIL_COUNT -gt 0 ]] && echo "FAILURES: $FAIL_COUNT" && exit 1
echo "All tests passed."
