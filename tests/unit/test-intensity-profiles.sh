#!/usr/bin/env bash
# Tests for Intensity Profile System (CONSOLIDATED-04)
# Validates: hook-profile.sh functions, profile resolution, model hints, doctor integration
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Intensity Profile System (CONSOLIDATED-04)"


PROFILE_LIB="$PROJECT_ROOT/scripts/lib/hook-profile.sh"
DOCTOR="$PROJECT_ROOT/.claude/skills/skill-doctor.md"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

# ── File existence and syntax ─────────────────────────────────────────────────

if [[ -f "$PROFILE_LIB" ]]; then
    pass "hook-profile.sh exists"
else
    fail "hook-profile.sh exists" "not found"
fi

if bash -n "$PROFILE_LIB" 2>/dev/null; then
    pass "hook-profile.sh has valid bash syntax"
else
    fail "hook-profile.sh has valid bash syntax" "syntax error"
fi

# ── Core functions exist ──────────────────────────────────────────────────────

for fn in is_hook_enabled get_profile_model_hint should_skip_phase get_context_verbosity get_profile_display suggest_profile_from_intent get_hook_profile; do
    if grep -q "${fn}()" "$PROFILE_LIB" 2>/dev/null; then
        pass "$fn() exists"
    else
        fail "$fn() exists" "missing"
    fi
done

# ── OCTO_PROFILE env var ─────────────────────────────────────────────────────

if grep -q 'OCTO_PROFILE' "$PROFILE_LIB" 2>/dev/null; then
    pass "Uses OCTO_PROFILE env var"
else
    fail "Uses OCTO_PROFILE env var" "missing"
fi

# ── Three profile levels ─────────────────────────────────────────────────────

for level in budget balanced quality; do
    if grep -q "$level" "$PROFILE_LIB" 2>/dev/null; then
        pass "Profile level '$level' defined"
    else
        fail "Profile level '$level' defined" "missing"
    fi
done

# ── Legacy compat ─────────────────────────────────────────────────────────────

if grep -q 'OCTO_HOOK_PROFILE' "$PROFILE_LIB" 2>/dev/null; then
    pass "Legacy OCTO_HOOK_PROFILE supported"
else
    fail "Legacy OCTO_HOOK_PROFILE supported" "missing"
fi

if grep -q 'minimal.*budget\|standard.*balanced\|strict.*quality' "$PROFILE_LIB" 2>/dev/null; then
    pass "Legacy profile names mapped (minimal→budget, etc.)"
else
    fail "Legacy profile names mapped (minimal→budget, etc.)" "missing mapping"
fi

# ── Kill switch ───────────────────────────────────────────────────────────────

if grep -q 'OCTO_PROFILE_GATING' "$PROFILE_LIB" 2>/dev/null; then
    pass "Has OCTO_PROFILE_GATING kill switch"
else
    fail "Has OCTO_PROFILE_GATING kill switch" "missing"
fi

# ── Per-hook override ─────────────────────────────────────────────────────────

if grep -q 'OCTO_DISABLED_HOOKS' "$PROFILE_LIB" 2>/dev/null; then
    pass "Supports OCTO_DISABLED_HOOKS per-hook override"
else
    fail "Supports OCTO_DISABLED_HOOKS per-hook override" "missing"
fi

# ── Model hints for phases ────────────────────────────────────────────────────

if grep -q 'sonnet\|opus' "$PROFILE_LIB" 2>/dev/null; then
    pass "Model hints include sonnet and opus"
else
    fail "Model hints include sonnet and opus" "missing model names"
fi

# ── Context verbosity levels ──────────────────────────────────────────────────

for level in compressed standard full; do
    if grep -q "$level" "$PROFILE_LIB" 2>/dev/null; then
        pass "Context verbosity '$level' defined"
    else
        fail "Context verbosity '$level' defined" "missing"
    fi
done

# ── Intent auto-selection ─────────────────────────────────────────────────────

if grep -q 'suggest_profile_from_intent' "$PROFILE_LIB" 2>/dev/null; then
    pass "Intent-to-profile auto-selection exists"
else
    fail "Intent-to-profile auto-selection exists" "missing"
fi

if grep -q 'quick' "$PROFILE_LIB" 2>/dev/null && grep -q 'budget' "$PROFILE_LIB" 2>/dev/null; then
    pass "Quick/question intents map to budget"
else
    fail "Quick/question intents map to budget" "missing mapping"
fi

if grep -q 'deploy' "$PROFILE_LIB" 2>/dev/null && grep -q 'quality' "$PROFILE_LIB" 2>/dev/null; then
    pass "Deploy/release intents map to quality"
else
    fail "Deploy/release intents map to quality" "missing mapping"
fi

# ── Doctor integration ────────────────────────────────────────────────────────

if grep -qi 'Intensity Profile' "$DOCTOR" 2>/dev/null; then
    pass "Doctor mentions Intensity Profile"
else
    fail "Doctor mentions Intensity Profile" "missing from doctor"
fi

if grep -q 'budget.*balanced.*quality' "$DOCTOR" 2>/dev/null; then
    pass "Doctor shows profile summary table"
else
    fail "Doctor shows profile summary table" "missing table"
fi

# ── Functional: profile resolution ────────────────────────────────────────────

FUNC_RESULT=$(bash -c '
    source "'"$PROFILE_LIB"'"

    # Test default
    echo "DEFAULT=$(_resolve_profile)"

    # Test explicit
    OCTO_PROFILE=quality
    echo "EXPLICIT=$(_resolve_profile)"

    # Test legacy mapping
    unset OCTO_PROFILE
    OCTO_HOOK_PROFILE=minimal
    echo "LEGACY=$(_resolve_profile)"

    # Test model hint
    OCTO_PROFILE=balanced
    echo "MODEL_DELIVER=$(get_profile_model_hint deliver)"
    echo "MODEL_DISCOVER=$(get_profile_model_hint discover)"

    # Test verbosity
    OCTO_PROFILE=budget
    echo "VERB=$(get_context_verbosity)"

    # Test intent suggestion
    echo "INTENT_QUICK=$(suggest_profile_from_intent "quick fix")"
    echo "INTENT_DEPLOY=$(suggest_profile_from_intent "deploy to production")"
' 2>/dev/null) || true

if echo "$FUNC_RESULT" | grep -q "DEFAULT=balanced"; then
    pass "Functional: default profile is balanced"
else
    fail "Functional: default profile is balanced" "$(echo "$FUNC_RESULT" | grep DEFAULT)"
fi

if echo "$FUNC_RESULT" | grep -q "EXPLICIT=quality"; then
    pass "Functional: explicit OCTO_PROFILE works"
else
    fail "Functional: explicit OCTO_PROFILE works" "not quality"
fi

if echo "$FUNC_RESULT" | grep -q "LEGACY=budget"; then
    pass "Functional: legacy minimal maps to budget"
else
    fail "Functional: legacy minimal maps to budget" "$(echo "$FUNC_RESULT" | grep LEGACY)"
fi

if echo "$FUNC_RESULT" | grep -q "MODEL_DELIVER=opus"; then
    pass "Functional: balanced profile uses opus for deliver"
else
    fail "Functional: balanced profile uses opus for deliver" "$(echo "$FUNC_RESULT" | grep MODEL_DELIVER)"
fi

if echo "$FUNC_RESULT" | grep -q "MODEL_DISCOVER=sonnet"; then
    pass "Functional: balanced profile uses sonnet for discover"
else
    fail "Functional: balanced profile uses sonnet for discover" "$(echo "$FUNC_RESULT" | grep MODEL_DISCOVER)"
fi

if echo "$FUNC_RESULT" | grep -q "VERB=compressed"; then
    pass "Functional: budget profile uses compressed verbosity"
else
    fail "Functional: budget profile uses compressed verbosity" "$(echo "$FUNC_RESULT" | grep VERB)"
fi

if echo "$FUNC_RESULT" | grep -q "INTENT_QUICK=budget"; then
    pass "Functional: quick intent suggests budget"
else
    fail "Functional: quick intent suggests budget" "$(echo "$FUNC_RESULT" | grep INTENT_QUICK)"
fi

if echo "$FUNC_RESULT" | grep -q "INTENT_DEPLOY=quality"; then
    pass "Functional: deploy intent suggests quality"
else
    fail "Functional: deploy intent suggests quality" "$(echo "$FUNC_RESULT" | grep INTENT_DEPLOY)"
fi

# ── No attribution ────────────────────────────────────────────────────────────

if grep -qi 'ecc\|gsd-2\|strategic-audit' "$PROFILE_LIB" 2>/dev/null; then
    fail "No attribution references" "found prohibited reference"
else
    pass "No attribution references"
fi
test_summary
