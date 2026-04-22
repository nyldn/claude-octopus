#!/usr/bin/env bash
# =============================================================================
# test-provider-activation.sh — Provider activation and reliability tests
# =============================================================================
# Tests for:
#   P0-A: Probe synthesis timeout recovery (synthesize-probe command)
#   P0-B: Claude-sonnet legacy dispatch in probe phase (OCTOPUS_FORCE_LEGACY_DISPATCH)
#   P1-A: Codex OAuth token freshness check
#   P1-B: Model name consistency (no stale gpt-5.3-codex defaults)
#   P2-C: Probe agent slot configuration
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/helpers/test-framework.sh"
test_suite "============================================================================="

ORCHESTRATE="$PROJECT_ROOT/scripts/orchestrate.sh"
# v9.7.8: Also search lib/ modules for extracted functions
SCRIPTS_ALL="$PROJECT_ROOT/scripts/orchestrate.sh $PROJECT_ROOT/scripts/lib/*.sh"

PASS=0
FAIL=0
TOTAL=0

pass() { test_case "$1"; test_pass; }

fail() { test_case "$1"; test_fail "${2:-$1}"; }

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "\033[0;34mProvider Activation & Reliability Tests\033[0m"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ═══════════════════════════════════════════════════════════════
# Test Group 1: synthesize-probe command exists (P0-A)
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "\033[0;34mTest Group 1: Probe synthesis timeout recovery (P0-A)\033[0m"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1.1: synthesize-probe command is registered in the dispatch
if grep -q 'synthesize-probe' "$ORCHESTRATE"; then
    pass "1.1 synthesize-probe command exists in orchestrate.sh"
else
    fail "1.1 synthesize-probe command missing from orchestrate.sh" \
        "P0-A: Need standalone synthesis recovery command"
fi

# 1.2: synthesize-probe appears in help text
if grep -rq 'synthesize-probe.*Synthesize\|synthesize-probe.*probe' $SCRIPTS_ALL; then
    pass "1.2 synthesize-probe documented in help text"
else
    fail "1.2 synthesize-probe missing from help text"
fi

# 1.3: Synthesis marker file is created before synthesis attempt
if grep -q 'synthesis-pending\|\.marker\|synthesis.*marker' "$ORCHESTRATE"; then
    pass "1.3 Synthesis marker file mechanism exists for timeout recovery"
else
    fail "1.3 No synthesis marker file mechanism found" \
        "P0-A: Need marker so synthesize-probe can find pending sessions"
fi

# 1.4: synthesize-probe can auto-detect most recent probe session
if grep -q 'most.recent\|auto.detect\|latest.*probe\|sort.*-t\|ls.*-t.*probe' "$ORCHESTRATE"; then
    pass "1.4 synthesize-probe has auto-detection for recent probe sessions"
else
    fail "1.4 synthesize-probe lacks auto-detection" \
        "P0-A: Should find most recent probe without explicit task_group"
fi

# ═══════════════════════════════════════════════════════════════
# Test Group 2: Claude-sonnet legacy dispatch in probe (P0-B)
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "\033[0;34mTest Group 2: Claude-sonnet probe dispatch fix (P0-B)\033[0m"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 2.1: OCTOPUS_FORCE_LEGACY_DISPATCH guard exists in should_use_agent_teams
if grep -rA 15 'should_use_agent_teams()' $SCRIPTS_ALL | grep -q 'OCTOPUS_FORCE_LEGACY_DISPATCH\|FORCE_LEGACY'; then
    pass "2.1 should_use_agent_teams checks OCTOPUS_FORCE_LEGACY_DISPATCH"
else
    fail "2.1 should_use_agent_teams missing FORCE_LEGACY_DISPATCH guard" \
        "P0-B: Claude-sonnet must use legacy bash dispatch in probe phase"
fi

# 2.2: probe_discover sets OCTOPUS_FORCE_LEGACY_DISPATCH before spawn loop
# v9.24.0: fleet_dispatch_begin/end helpers wrap the spawn loop (agent-sync.sh)
if grep -rB 5 -A 30 'for i in.*perspectives' $SCRIPTS_ALL | grep -q 'FORCE_LEGACY_DISPATCH=true\|FORCE_LEGACY.*true\|fleet_dispatch_begin'; then
    pass "2.2 probe_discover sets FORCE_LEGACY_DISPATCH before spawn loop"
else
    fail "2.2 probe_discover doesn't set FORCE_LEGACY_DISPATCH" \
        "P0-B: Probe agents must use legacy dispatch when run via Bash tool"
fi

# 2.3: OCTOPUS_FORCE_LEGACY_DISPATCH is unset after spawn loop
if grep -rq 'unset.*FORCE_LEGACY_DISPATCH\|FORCE_LEGACY_DISPATCH.*false' $SCRIPTS_ALL; then
    pass "2.3 FORCE_LEGACY_DISPATCH is cleaned up after spawn loop"
else
    fail "2.3 FORCE_LEGACY_DISPATCH not cleaned up after spawn loop" \
        "Leaked env var could affect subsequent agent dispatches"
fi

# 2.4: Agent Teams dispatch path checks FORCE_LEGACY
if grep -rB 2 -A 8 'OCTOPUS_FORCE_LEGACY_DISPATCH\|FORCE_LEGACY' $SCRIPTS_ALL | grep -q 'return 1'; then
    pass "2.4 FORCE_LEGACY_DISPATCH returns 1 (legacy path) when set"
else
    fail "2.4 FORCE_LEGACY_DISPATCH doesn't force legacy path"
fi

# ═══════════════════════════════════════════════════════════════
# Test Group 3: Codex OAuth health check (P1-A)
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "\033[0;34mTest Group 3: Codex OAuth token freshness check (P1-A)\033[0m"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 3.1: check_codex_auth_freshness function exists (may be in lib/)
if grep -rq 'check_codex_auth_freshness()' $SCRIPTS_ALL; then
    pass "3.1 check_codex_auth_freshness() function exists"
else
    fail "3.1 check_codex_auth_freshness() function missing" \
        "P1-A: Need OAuth token expiry check before probe"
fi

# 3.2: Function checks auth.json expiry
if grep -rA 20 'check_codex_auth_freshness()' $SCRIPTS_ALL | grep -q 'expires_at\|expiry\|auth\.json'; then
    pass "3.2 check_codex_auth_freshness checks token expiry field"
else
    fail "3.2 check_codex_auth_freshness doesn't check token expiry"
fi

# 3.3: Function is called from preflight (not just defined)
call_count=$(grep -rc 'check_codex_auth_freshness' $SCRIPTS_ALL 2>/dev/null | awk -F: '{s+=$NF} END{print s}')
if [[ $call_count -ge 2 ]]; then
    pass "3.3 check_codex_auth_freshness is called (not just defined)"
else
    fail "3.3 check_codex_auth_freshness defined but never called ($call_count refs)" \
        "P1-A: Must be called from preflight_check()"
fi

# 3.4: Function provides actionable error message
if grep -rA 30 'check_codex_auth_freshness()' $SCRIPTS_ALL | grep -q 'codex auth\|codex login'; then
    pass "3.4 Function provides actionable fix suggestion (codex auth)"
else
    fail "3.4 Function doesn't suggest 'codex auth' fix"
fi

# ═══════════════════════════════════════════════════════════════
# Test Group 4: Model name consistency (P1-B)
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "\033[0;34mTest Group 4: Model name consistency — no stale defaults (P1-B)\033[0m"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 4.1: resolve_octopus_model uses gpt-5.4 for codex default
if grep -rA 10 "case \"\$agent_type\" in" $SCRIPTS_ALL | grep -A 1 "codex\*)" | grep -q 'gpt-5\.4'; then
    pass "4.1 resolve_octopus_model returns gpt-5.4 for codex default"
else
    fail "4.1 resolve_octopus_model uses stale model for codex default"
fi

# 4.2: Tier mapping aliases in resolve_octopus_model (premium/standard/budget)
if grep -rq "tier_mapped_model" $SCRIPTS_ALL && grep -rq "OCTOPUS_COST_MODE" $SCRIPTS_ALL; then
    pass "4.2 resolve_octopus_model supports tier mapping"
else
    fail "4.2 resolve_octopus_model lacks tier mapping"
fi
# 4.3: No stale gpt-5.3-codex in active model routing
# Allow: gpt-5.3-codex-spark (the current model)
# Exclude: pricing tables, dead code, config templates, comments, help text, sparks
stale_in_routing=0
while IFS= read -r line; do
    ((stale_in_routing++)) || true
done < <(grep -nE '\b"gpt-5\.3-codex"\b' "$ORCHESTRATE" 2>/dev/null | grep -v 'pricing\|cost_per\|config_template\|default_config\|select_codex_model_for_context\|#.*gpt-5\.3' 2>/dev/null || true)
if [[ $stale_in_routing -eq 0 ]]; then
    pass "4.3 No stale gpt-5.3-codex in active model routing"
else
    fail "4.3 Found $stale_in_routing stale gpt-5.3-codex in model routing" \
        "Check resolve_octopus_model fallbacks"
fi


# 4.4: Role-to-agent mapping in resolve_octopus_model
if grep -rq "routing.roles" $SCRIPTS_ALL; then
    pass "4.4 resolve_octopus_model supports role routing"
else
    fail "4.4 resolve_octopus_model missing role routing"
fi

# 4.5: codex fallbacks use gpt-5.4
if grep -rA 20 "Fallback to hard-coded defaults" $SCRIPTS_ALL | grep -A 1 "codex\*)" | grep -q 'gpt-5\.4'; then
    pass "4.5 codex fallback uses gpt-5.4"
else
    fail "4.5 codex fallback uses stale model"
fi

# ═══════════════════════════════════════════════════════════════
# Test Group 5: Probe agent configuration
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "\033[0;34mTest Group 5: Probe agent slot configuration\033[0m"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 5.1: smart dispatch includes codex for review/security workflows
if grep -rc 'codex.*gemini.*claude-sonnet\|codex,claude-sonnet' $SCRIPTS_ALL >/dev/null 2>&1; then
    pass "5.1 smart dispatch includes codex for review/security"
else
    fail "5.1 smart dispatch missing codex for review/security"
fi

# 5.2: smart dispatch includes gemini for research workflows
if grep -rc 'gemini,claude-sonnet' $SCRIPTS_ALL >/dev/null 2>&1; then
    pass "5.2 smart dispatch includes gemini for research"
else
    fail "5.2 smart dispatch missing gemini for research"
fi

# 5.3: get_dispatch_strategy function exists
if grep -rc 'get_dispatch_strategy()' $SCRIPTS_ALL >/dev/null 2>&1; then
    pass "5.3 get_dispatch_strategy function defined"
else
    fail "5.3 get_dispatch_strategy function missing"
fi

# 5.4: synthesis uses >500 byte threshold to filter probe results
if grep -rA 5 'synthesize_probe_results' $SCRIPTS_ALL | grep -q '500\|file_size.*gt'; then
    pass "5.4 Synthesis filters probe results by minimum size (>500 bytes)"
else
    # Check in the function body
    if grep -rA 30 'synthesize_probe_results()' $SCRIPTS_ALL | grep -q '500'; then
        pass "5.4 Synthesis filters probe results by minimum size (>500 bytes)"
    else
        fail "5.4 Synthesis doesn't filter small/empty probe results"
    fi
fi

# 5.5: Graceful degradation with partial results
if grep -rA 40 'synthesize_probe_results()' $SCRIPTS_ALL | grep -q 'result_count.*-eq 1\|Proceeding with.*usable'; then
    pass "5.5 Synthesis handles partial results gracefully"
else
    fail "5.5 No graceful degradation for partial probe results"
fi

# ═══════════════════════════════════════════════════════════════
# Test Group 6: Agent Teams dispatch safety
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "\033[0;34mTest Group 6: Agent Teams dispatch safety\033[0m"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 6.1: should_use_agent_teams only returns 0 for Claude agents
if grep -rA 20 'should_use_agent_teams()' $SCRIPTS_ALL | grep -q 'claude|claude-sonnet|claude-opus'; then
    pass "6.1 Agent Teams only routes Claude agent types"
else
    fail "6.1 Agent Teams may route non-Claude agents incorrectly"
fi

# 6.2: Agent Teams dispatch writes result file header
if grep -rA 50 'should_use_agent_teams.*agent_type' $SCRIPTS_ALL | grep -q 'Agent.*via.*Agent Teams\|result_file'; then
    pass "6.2 Agent Teams dispatch writes result file header"
else
    fail "6.2 Agent Teams dispatch may not write result file header"
fi

# 6.3: Legacy path writes actual output content
if grep -rq 'tee.*raw_output\|LEGACY PATH.*output\|legacy.*subprocess.*output\|raw_output.*result_file' $SCRIPTS_ALL; then
    pass "6.3 Legacy bash path captures actual agent output"
else
    fail "6.3 Legacy path may not capture agent output correctly"
fi

# ═══════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "\033[0;34mTest Summary — Provider Activation & Reliability\033[0m"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "Total tests:  \033[0;34m$TOTAL\033[0m"
test_summary
