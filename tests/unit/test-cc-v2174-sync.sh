#!/usr/bin/env bash
# Tests for CC v2.1.74 feature detection sync (+ 2 untracked v2.1.72 flags)
# Validates: 8 new SUPPORTS_* flags, v2.1.74 detection block, wiring, doctor checks
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ORCH="$PROJECT_ROOT/scripts/orchestrate.sh"

TEST_COUNT=0; PASS_COUNT=0; FAIL_COUNT=0
pass() { TEST_COUNT=$((TEST_COUNT+1)); PASS_COUNT=$((PASS_COUNT+1)); echo "PASS: $1"; }
fail() { TEST_COUNT=$((TEST_COUNT+1)); FAIL_COUNT=$((FAIL_COUNT+1)); echo "FAIL: $1 — $2"; }

# ── 1. Flag declarations exist ────────────────────────────────────────

for flag in SUPPORTS_PARALLEL_TOOL_RESILIENCE SUPPORTS_PLAN_WITH_ARGS \
            SUPPORTS_AUTO_MEMORY_DIR SUPPORTS_FULL_MODEL_IDS \
            SUPPORTS_SESSION_END_TIMEOUT SUPPORTS_CONTEXT_SUGGESTIONS \
            SUPPORTS_PLUGIN_DIR_OVERRIDE SUPPORTS_MANAGED_POLICY_FIX; do
    if grep -c "${flag}=false" "$ORCH" >/dev/null 2>&1; then
        pass "Declaration: $flag"
    else
        fail "Declaration: $flag" "missing ${flag}=false in orchestrate.sh"
    fi
done

# ── 2. v2.1.72 detection block includes new flags ────────────────────

v2172_block=$(grep -A20 'version_compare.*2\.1\.72' "$ORCH" | head -20)

for flag in SUPPORTS_PARALLEL_TOOL_RESILIENCE SUPPORTS_PLAN_WITH_ARGS; do
    if echo "$v2172_block" | grep -c "$flag=true" >/dev/null 2>&1; then
        pass "v2.1.72 block sets: $flag"
    else
        fail "v2.1.72 block sets: $flag" "not found in v2.1.72 detection block"
    fi
done

# ── 3. v2.1.74 detection block exists and sets all 6 flags ───────────

if grep -c 'version_compare.*2\.1\.74' "$ORCH" >/dev/null 2>&1; then
    pass "v2.1.74 detection block exists"
else
    fail "v2.1.74 detection block exists" "no version_compare for 2.1.74"
fi

v2174_block=$(grep -A15 'version_compare.*2\.1\.74' "$ORCH" | head -15)

for flag in SUPPORTS_AUTO_MEMORY_DIR SUPPORTS_FULL_MODEL_IDS \
            SUPPORTS_SESSION_END_TIMEOUT SUPPORTS_CONTEXT_SUGGESTIONS \
            SUPPORTS_PLUGIN_DIR_OVERRIDE SUPPORTS_MANAGED_POLICY_FIX; do
    if echo "$v2174_block" | grep -c "$flag=true" >/dev/null 2>&1; then
        pass "v2.1.74 block sets: $flag"
    else
        fail "v2.1.74 block sets: $flag" "not found in v2.1.74 detection block"
    fi
done

# ── 4. Logging lines for new flags ───────────────────────────────────

for label in "Parallel Tool Resilience" "Plan With Args" "Auto Memory Dir" \
             "Full Model IDs" "Session End Timeout" "Context Suggestions" \
             "Plugin Dir Override" "Managed Policy Fix"; do
    if grep -c "$label" "$ORCH" >/dev/null 2>&1; then
        pass "Log line: $label"
    else
        fail "Log line: $label" "missing from logging output"
    fi
done

# ── 5. Wiring: spawn_agent full model IDs ────────────────────────────

if grep -c 'SUPPORTS_FULL_MODEL_IDS.*true' "$ORCH" >/dev/null 2>&1; then
    # Should be wired in spawn_agent context (near SUPPORTS_SUBAGENT_MODEL_FIX)
    spawn_context=$(grep -A5 'SUPPORTS_SUBAGENT_MODEL_FIX.*true' "$ORCH" | head -10)
    if echo "$spawn_context" | grep -c 'SUPPORTS_FULL_MODEL_IDS' >/dev/null 2>&1; then
        pass "Wired: SUPPORTS_FULL_MODEL_IDS in spawn_agent"
    else
        fail "Wired: SUPPORTS_FULL_MODEL_IDS in spawn_agent" "not found near SUBAGENT_MODEL_FIX check"
    fi
fi

# ── 6. Wiring: doctor context suggestions ────────────────────────────

if grep -c 'SUPPORTS_CONTEXT_SUGGESTIONS.*true.*doctor\|doctor.*context-suggestions' "$ORCH" >/dev/null 2>&1; then
    pass "Wired: doctor context-suggestions check"
else
    # Try alternate pattern — doctor_add with context-suggestions
    if grep -c 'doctor_add.*context-suggestions' "$ORCH" >/dev/null 2>&1; then
        pass "Wired: doctor context-suggestions check"
    else
        fail "Wired: doctor context-suggestions check" "no doctor_add for context-suggestions"
    fi
fi

# ── 7. Wiring: doctor autoMemoryDirectory ────────────────────────────

if grep -c 'autoMemoryDirectory' "$ORCH" >/dev/null 2>&1; then
    pass "Wired: doctor autoMemoryDirectory check"
else
    fail "Wired: doctor autoMemoryDirectory check" "no autoMemoryDirectory reference"
fi

# ── 8. Flag comments reference correct CC versions ───────────────────

for flag_ver in "PARALLEL_TOOL_RESILIENCE.*v2.1.72" "PLAN_WITH_ARGS.*v2.1.72" \
                "AUTO_MEMORY_DIR.*v2.1.74" "FULL_MODEL_IDS.*v2.1.74" \
                "SESSION_END_TIMEOUT.*v2.1.74" "CONTEXT_SUGGESTIONS.*v2.1.74" \
                "PLUGIN_DIR_OVERRIDE.*v2.1.74" "MANAGED_POLICY_FIX.*v2.1.74"; do
    if grep -cE "$flag_ver" "$ORCH" >/dev/null 2>&1; then
        pass "Version comment: $flag_ver"
    else
        fail "Version comment: $flag_ver" "missing or wrong version in comment"
    fi
done

# ── Summary ──────────────────────────────────────────────────────────

echo ""
echo "==============================================="
echo "CC v2.1.74 sync tests: $PASS_COUNT/$TEST_COUNT passed"
if [[ $FAIL_COUNT -gt 0 ]]; then
    echo "$FAIL_COUNT FAILED"
    exit 1
fi
echo "All tests passed."
