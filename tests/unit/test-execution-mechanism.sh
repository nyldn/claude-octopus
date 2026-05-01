#!/usr/bin/env bash
# Tests that all multi-LLM workflow commands have the EXECUTION MECHANISM enforcement block.
# This block prevents the agent from substituting Claude-native tools for orchestrate.sh dispatch.
#
# Bug context: /octo:embrace displayed the workflow banner but never called orchestrate.sh.
# The agent used Agent() and WebFetch instead of multi-provider dispatch.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "that all multi-LLM workflow commands have the EXECUTION MECHANISM enforcement block."


pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

# ── Commands that MUST have EXECUTION MECHANISM ────────────────────────────
# These are multi-LLM commands where the agent must use orchestrate.sh or skill dispatch.
# Quick mode is deliberately excluded (single-model by design).

MULTI_LLM_COMMANDS="embrace discover define develop deliver multi review security debate research factory staged-review prd"

echo "=== EXECUTION MECHANISM Enforcement ==="

for cmd in $MULTI_LLM_COMMANDS; do
    cc="$PROJECT_ROOT/.claude/commands/${cmd}.md"
    if [[ -f "$cc" ]]; then
        if grep -q 'EXECUTION MECHANISM' "$cc" 2>/dev/null; then
            pass "$cmd.md has EXECUTION MECHANISM"
        else
            fail "$cmd.md missing EXECUTION MECHANISM" "Multi-LLM commands must have enforcement block"
        fi
    else
        fail "$cmd.md not found" "$cc missing"
    fi
done

echo ""
echo "=== EXECUTION MECHANISM Contains PROHIBITED ─────"

for cmd in $MULTI_LLM_COMMANDS; do
    cc="$PROJECT_ROOT/.claude/commands/${cmd}.md"
    if [[ -f "$cc" ]] && grep -q 'EXECUTION MECHANISM' "$cc" 2>/dev/null; then
        # Check the enforcement block contains prohibition markers
        if grep -A 10 'EXECUTION MECHANISM' "$cc" | grep -qE '❌|PROHIBITED'; then
            pass "$cmd.md enforcement has prohibitions"
        else
            fail "$cmd.md enforcement weak" "EXECUTION MECHANISM block must list prohibited actions"
        fi
    fi
done

echo ""
echo "=== Post-Compact Re-injection ==="

# Verify post-compact hook re-injects enforcement for active workflows
POST_COMPACT="$PROJECT_ROOT/hooks/post-compact.sh"
if [[ -f "$POST_COMPACT" ]]; then
    if grep -q 'EXECUTION ENFORCEMENT' "$POST_COMPACT" 2>/dev/null; then
        pass "post-compact.sh re-injects execution enforcement"
    else
        fail "post-compact.sh missing enforcement re-injection" "Must re-inject enforcement after compaction"
    fi
    if grep -q 'orchestrate.sh' "$POST_COMPACT" 2>/dev/null; then
        pass "post-compact.sh mentions orchestrate.sh"
    else
        fail "post-compact.sh missing orchestrate.sh reference" "Re-injection must mention orchestrate.sh"
    fi
else
    fail "post-compact.sh not found" "$POST_COMPACT missing"
fi

echo ""
echo "=== Workflow Verification Hook ==="

VERIFY_HOOK="$PROJECT_ROOT/hooks/workflow-verification.sh"
if [[ -f "$VERIFY_HOOK" ]]; then
    pass "workflow-verification.sh exists"
    if bash -n "$VERIFY_HOOK" 2>/dev/null; then
        pass "workflow-verification.sh valid syntax"
    else
        fail "workflow-verification.sh syntax error" "bash -n failed"
    fi
    if grep -q 'orchestrate.sh' "$VERIFY_HOOK" 2>/dev/null; then
        pass "workflow-verification.sh checks for orchestrate.sh usage"
    else
        fail "workflow-verification.sh missing orchestrate check" "Must detect missing orchestrate.sh calls"
    fi
else
    fail "workflow-verification.sh not found" "$VERIFY_HOOK missing"
fi

echo ""
echo "=== Embrace Chains Skills (Not One Big Bash Call) ==="

EMBRACE="$PROJECT_ROOT/.claude/commands/embrace.md"
if [[ -f "$EMBRACE" ]]; then
    skill_invocations=$(grep -c 'Skill(skill: "octo:' "$EMBRACE" 2>/dev/null || echo 0)
    if [[ $skill_invocations -ge 4 ]]; then
        pass "embrace.md chains $skill_invocations skill invocations"
    else
        fail "embrace.md only has $skill_invocations skill invocations" "Must chain at least 4 (discover+define+develop+deliver)"
    fi
fi

echo ""
echo "=== Develop Direct Dispatch Preserves Preflight ==="

for develop_file in "$PROJECT_ROOT/.claude/commands/develop.md" "$PROJECT_ROOT/commands/octo-develop.md"; do
    develop_name=$(basename "$develop_file")
    if [[ -f "$develop_file" ]]; then
        preflight_line=$(grep -n 'helpers/check-providers.sh' "$develop_file" | head -1 | cut -d: -f1 || true)
        banner_line=$(grep -n 'CLAUDE OCTOPUS ACTIVATED' "$develop_file" | head -1 | cut -d: -f1 || true)
        dispatch_line=$(grep -n 'orchestrate.sh" develop' "$develop_file" | head -1 | cut -d: -f1 || true)

        if [[ -n "$dispatch_line" ]]; then
            pass "$develop_name dispatches via orchestrate.sh develop"
        else
            fail "$develop_name missing direct dispatch" "Develop docs must call orchestrate.sh develop"
        fi

        if [[ -n "$dispatch_line" ]]; then
            if [[ -n "$preflight_line" && "$preflight_line" -lt "$dispatch_line" ]]; then
                pass "$develop_name checks provider availability before dispatch"
            else
                fail "$develop_name missing provider preflight" "Direct develop dispatch must run helpers/check-providers.sh before orchestrate.sh"
            fi

            if [[ -n "$banner_line" && "$banner_line" -lt "$dispatch_line" ]]; then
                pass "$develop_name displays workflow indicator before dispatch"
            else
                fail "$develop_name missing workflow indicator" "Direct develop dispatch must show the Octopus activation banner before orchestrate.sh"
            fi
        fi

        if grep -q 'OCTOPUS_EFFORT_OVERRIDE' "$develop_file" \
           && grep -q 'OCTOPUS_OPUS_MODE' "$develop_file" \
           && grep -q 'Fast Opus 4.6 mode is 6x more expensive' "$develop_file" \
           && grep -q 'project memory' "$develop_file"; then
            pass "$develop_name documents model effort and memory policy"
        else
            fail "$develop_name missing model effort policy" "Develop command must document effort overrides, Fast Opus cost, and memory recording policy"
        fi
    else
        fail "$develop_name not found" "$develop_file missing"
    fi
done
test_summary
