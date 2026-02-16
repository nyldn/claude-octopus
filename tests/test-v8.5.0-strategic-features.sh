#!/usr/bin/env bash
# Test: v8.5.0 Strategic Feature Implementation
# Validates all new features introduced in v8.5.0:
#   Opp 7: /fast toggle detection (detect_fast_mode, select_opus_mode enhancement)
#   Opp 2: Pre-execution cost estimates (estimate_workflow_cost, show_cost_estimate)
#   Opp 3: Cross-memory warm start (build_memory_context, spawn_agent memory injection)
#   Opp 4: Enhanced statusline (octopus-hud.mjs, statusline.sh delegation)
#   Opp 5: Agent Teams conditional migration (should_use_agent_teams, spawn_agent branching)
#   Opp 6: Workflow-as-Code YAML runtime (parse_yaml_workflow, execute_workflow_phase, etc.)
#
# NOTE: orchestrate.sh has a main execution block that runs on source,
# so we use grep-based static analysis rather than sourcing the whole file.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
ORCHESTRATE_SH="${PLUGIN_DIR}/scripts/orchestrate.sh"
STATUSLINE_SH="${PLUGIN_DIR}/hooks/octopus-statusline.sh"
HUD_MJS="${PLUGIN_DIR}/hooks/octopus-hud.mjs"
EMBRACE_YAML="${PLUGIN_DIR}/workflows/embrace.yaml"
SCHEMA_YAML="${PLUGIN_DIR}/workflows/schema.yaml"
CONFIG_YAML="${PLUGIN_DIR}/agents/config.yaml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

assert_pass() {
    local test_name="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} $test_name"
}

assert_fail() {
    local test_name="$1"
    local detail="${2:-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} $test_name"
    [[ -n "$detail" ]] && echo -e "  ${YELLOW}$detail${NC}"
}

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  v8.5.0 Strategic Feature Implementation Tests             ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# PREREQUISITE: File existence checks
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}Prerequisite: File Existence${NC}"
echo "------------------------------------------------------------"

if [[ -f "$ORCHESTRATE_SH" ]]; then
    assert_pass "P.1 orchestrate.sh exists"
else
    assert_fail "P.1 orchestrate.sh exists" "Not found: $ORCHESTRATE_SH"
    echo -e "${RED}Cannot continue without orchestrate.sh${NC}"
    exit 1
fi

if [[ -f "$STATUSLINE_SH" ]]; then
    assert_pass "P.2 octopus-statusline.sh exists"
else
    assert_fail "P.2 octopus-statusline.sh exists"
fi

if [[ -f "$HUD_MJS" ]]; then
    assert_pass "P.3 octopus-hud.mjs exists (new file)"
else
    assert_fail "P.3 octopus-hud.mjs exists (new file)"
fi

if [[ -f "$EMBRACE_YAML" ]]; then
    assert_pass "P.4 embrace.yaml exists"
else
    assert_fail "P.4 embrace.yaml exists"
fi

# Syntax checks
if bash -n "$ORCHESTRATE_SH" 2>/dev/null; then
    assert_pass "P.5 orchestrate.sh passes bash -n syntax check"
else
    assert_fail "P.5 orchestrate.sh passes bash -n syntax check"
fi

if bash -n "$STATUSLINE_SH" 2>/dev/null; then
    assert_pass "P.6 octopus-statusline.sh passes bash -n syntax check"
else
    assert_fail "P.6 octopus-statusline.sh passes bash -n syntax check"
fi

if command -v node &>/dev/null; then
    if node --check "$HUD_MJS" 2>/dev/null; then
        assert_pass "P.7 octopus-hud.mjs passes node --check syntax check"
    else
        assert_fail "P.7 octopus-hud.mjs passes node --check syntax check"
    fi
else
    assert_pass "P.7 octopus-hud.mjs syntax check (skipped - no node)"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST GROUP 1: Opp 7 - /fast Toggle Detection (8 tests)
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}Test Group 1: Opp 7 - /fast Toggle Detection${NC}"
echo "------------------------------------------------------------"

# 1.1: USER_FAST_MODE global variable declared
if grep -q '^USER_FAST_MODE=' "$ORCHESTRATE_SH"; then
    assert_pass "1.1 USER_FAST_MODE global variable declared"
else
    assert_fail "1.1 USER_FAST_MODE global variable declared"
fi

# 1.2: detect_fast_mode() function exists
if grep -q '^detect_fast_mode()' "$ORCHESTRATE_SH"; then
    assert_pass "1.2 detect_fast_mode() function exists"
else
    assert_fail "1.2 detect_fast_mode() function exists"
fi

# 1.3: detect_fast_mode checks CLAUDE_CODE_FAST_MODE env var
if grep -A 30 '^detect_fast_mode()' "$ORCHESTRATE_SH" | grep -q 'CLAUDE_CODE_FAST_MODE'; then
    assert_pass "1.3 detect_fast_mode checks CLAUDE_CODE_FAST_MODE env var"
else
    assert_fail "1.3 detect_fast_mode checks CLAUDE_CODE_FAST_MODE env var"
fi

# 1.4: detect_fast_mode checks settings.json
if grep -A 30 '^detect_fast_mode()' "$ORCHESTRATE_SH" | grep -q 'settings.json'; then
    assert_pass "1.4 detect_fast_mode checks settings.json"
else
    assert_fail "1.4 detect_fast_mode checks settings.json"
fi

# 1.5: detect_fast_mode called from detect_claude_code_version
if grep -B 2 -A 2 'detect_fast_mode' "$ORCHESTRATE_SH" | grep -q 'User /fast mode'; then
    assert_pass "1.5 detect_fast_mode integrated into version detection"
else
    assert_fail "1.5 detect_fast_mode integrated into version detection"
fi

# 1.6: select_opus_mode references USER_FAST_MODE
if grep -A 50 '^select_opus_mode()' "$ORCHESTRATE_SH" | grep -q 'USER_FAST_MODE'; then
    assert_pass "1.6 select_opus_mode references USER_FAST_MODE"
else
    assert_fail "1.6 select_opus_mode references USER_FAST_MODE"
fi

# 1.7: /fast mode protects multi-phase workflows from cost explosion
if grep -A 60 '^select_opus_mode()' "$ORCHESTRATE_SH" | grep -q 'inside multi-phase workflow.*using standard'; then
    assert_pass "1.7 /fast mode protects multi-phase workflows"
else
    assert_fail "1.7 /fast mode protects multi-phase workflows"
fi

# 1.8: show_provider_status displays /fast mode status
if grep -A 50 '^show_provider_status()' "$ORCHESTRATE_SH" | grep -q '/fast Mode'; then
    assert_pass "1.8 show_provider_status displays /fast mode status"
else
    assert_fail "1.8 show_provider_status displays /fast mode status"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST GROUP 2: Opp 2 - Pre-Execution Cost Estimates (8 tests)
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}Test Group 2: Opp 2 - Pre-Execution Cost Estimates${NC}"
echo "------------------------------------------------------------"

# 2.1: estimate_workflow_cost() function exists
if grep -q '^estimate_workflow_cost()' "$ORCHESTRATE_SH"; then
    assert_pass "2.1 estimate_workflow_cost() function exists"
else
    assert_fail "2.1 estimate_workflow_cost() function exists"
fi

# 2.2: show_cost_estimate() function exists
if grep -q '^show_cost_estimate()' "$ORCHESTRATE_SH"; then
    assert_pass "2.2 show_cost_estimate() function exists"
else
    assert_fail "2.2 show_cost_estimate() function exists"
fi

# 2.3: estimate_workflow_cost handles embrace workflow
if grep -A 20 '^estimate_workflow_cost()' "$ORCHESTRATE_SH" | grep -q 'embrace)'; then
    assert_pass "2.3 estimate_workflow_cost handles embrace workflow"
else
    assert_fail "2.3 estimate_workflow_cost handles embrace workflow"
fi

# 2.4: estimate_workflow_cost calls is_api_based_provider
if grep -A 40 '^estimate_workflow_cost()' "$ORCHESTRATE_SH" | grep -q 'is_api_based_provider'; then
    assert_pass "2.4 estimate_workflow_cost calls is_api_based_provider"
else
    assert_fail "2.4 estimate_workflow_cost calls is_api_based_provider"
fi

# 2.5: show_cost_estimate skips when all providers are auth-connected
if grep -A 20 '^show_cost_estimate()' "$ORCHESTRATE_SH" | grep -q 'has_cost.*false'; then
    assert_pass "2.5 show_cost_estimate skips when all auth-connected"
else
    assert_fail "2.5 show_cost_estimate skips when all auth-connected"
fi

# 2.6: show_cost_estimate shows /fast mode warning when active
if grep -A 30 '^show_cost_estimate()' "$ORCHESTRATE_SH" | grep -q 'USER_FAST_MODE.*true'; then
    assert_pass "2.6 show_cost_estimate shows /fast mode warning"
else
    assert_fail "2.6 show_cost_estimate shows /fast mode warning"
fi

# 2.7: embrace_full_workflow calls show_cost_estimate
if grep -A 80 '^embrace_full_workflow()' "$ORCHESTRATE_SH" | grep -q 'show_cost_estimate'; then
    assert_pass "2.7 embrace_full_workflow calls show_cost_estimate"
else
    assert_fail "2.7 embrace_full_workflow calls show_cost_estimate"
fi

# 2.8: estimate_workflow_cost handles individual phases (probe/grasp/tangle/ink)
phase_count=$(grep -A 30 '^estimate_workflow_cost()' "$ORCHESTRATE_SH" | grep -c 'probe\|grasp\|tangle\|ink\|discover\|define\|develop\|deliver')
if [[ "$phase_count" -ge 4 ]]; then
    assert_pass "2.8 estimate_workflow_cost handles individual phases ($phase_count matches)"
else
    assert_fail "2.8 estimate_workflow_cost handles individual phases" "Found $phase_count, expected >= 4"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST GROUP 3: Opp 3 - Cross-Memory Warm Start (8 tests)
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}Test Group 3: Opp 3 - Cross-Memory Warm Start${NC}"
echo "------------------------------------------------------------"

# 3.1: MEMORY_INJECTION_ENABLED flag declared
if grep -q '^MEMORY_INJECTION_ENABLED=' "$ORCHESTRATE_SH"; then
    assert_pass "3.1 MEMORY_INJECTION_ENABLED flag declared"
else
    assert_fail "3.1 MEMORY_INJECTION_ENABLED flag declared"
fi

# 3.2: build_memory_context() function exists
if grep -q '^build_memory_context()' "$ORCHESTRATE_SH"; then
    assert_pass "3.2 build_memory_context() function exists"
else
    assert_fail "3.2 build_memory_context() function exists"
fi

# 3.3: build_memory_context guards on SUPPORTS_PERSISTENT_MEMORY
if grep -A 20 '^build_memory_context()' "$ORCHESTRATE_SH" | grep -q 'SUPPORTS_PERSISTENT_MEMORY.*true'; then
    assert_pass "3.3 build_memory_context guards on SUPPORTS_PERSISTENT_MEMORY"
else
    assert_fail "3.3 build_memory_context guards on SUPPORTS_PERSISTENT_MEMORY"
fi

# 3.4: build_memory_context handles project/user/local scopes
if grep -A 40 '^build_memory_context()' "$ORCHESTRATE_SH" | grep -q 'project)'; then
    assert_pass "3.4 build_memory_context handles project scope"
else
    assert_fail "3.4 build_memory_context handles project scope"
fi

if grep -A 40 '^build_memory_context()' "$ORCHESTRATE_SH" | grep -q 'user)'; then
    assert_pass "3.5 build_memory_context handles user scope"
else
    assert_fail "3.5 build_memory_context handles user scope"
fi

if grep -A 40 '^build_memory_context()' "$ORCHESTRATE_SH" | grep -q 'local)'; then
    assert_pass "3.6 build_memory_context handles local scope"
else
    assert_fail "3.6 build_memory_context handles local scope"
fi

# 3.7: build_memory_context reads MEMORY.md files
if grep -A 40 '^build_memory_context()' "$ORCHESTRATE_SH" | grep -q 'MEMORY.md'; then
    assert_pass "3.7 build_memory_context reads MEMORY.md files"
else
    assert_fail "3.7 build_memory_context reads MEMORY.md files"
fi

# 3.8: spawn_agent injects memory via build_memory_context
if grep -A 200 '^spawn_agent()' "$ORCHESTRATE_SH" | grep -q 'build_memory_context'; then
    assert_pass "3.8 spawn_agent injects memory via build_memory_context"
else
    assert_fail "3.8 spawn_agent injects memory via build_memory_context"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST GROUP 4: Opp 4 - Enhanced Statusline / METRICC HUD (8 tests)
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}Test Group 4: Opp 4 - Enhanced Statusline (Node.js HUD)${NC}"
echo "------------------------------------------------------------"

# 4.1: octopus-hud.mjs file exists
if [[ -f "$HUD_MJS" ]]; then
    assert_pass "4.1 octopus-hud.mjs file exists"
else
    assert_fail "4.1 octopus-hud.mjs file exists"
fi

# 4.2: HUD reads session.json for workflow state
if grep -q 'session.json' "$HUD_MJS"; then
    assert_pass "4.2 HUD reads session.json for workflow state"
else
    assert_fail "4.2 HUD reads session.json for workflow state"
fi

# 4.3: HUD has phase emoji mapping
if grep -q 'PHASE_EMOJI' "$HUD_MJS"; then
    assert_pass "4.3 HUD has phase emoji mapping"
else
    assert_fail "4.3 HUD has phase emoji mapping"
fi

# 4.4: HUD builds context window bar
if grep -q 'contextBar' "$HUD_MJS"; then
    assert_pass "4.4 HUD builds context window bar"
else
    assert_fail "4.4 HUD builds context window bar"
fi

# 4.5: HUD has provider indicators
if grep -q 'providerIndicators' "$HUD_MJS"; then
    assert_pass "4.5 HUD has provider indicators"
else
    assert_fail "4.5 HUD has provider indicators"
fi

# 4.6: HUD has quality gate display
if grep -q 'qualityGate' "$HUD_MJS"; then
    assert_pass "4.6 HUD has quality gate display"
else
    assert_fail "4.6 HUD has quality gate display"
fi

# 4.7: statusline.sh delegates to Node.js HUD
if grep -q 'octopus-hud.mjs' "$STATUSLINE_SH"; then
    assert_pass "4.7 statusline.sh delegates to octopus-hud.mjs"
else
    assert_fail "4.7 statusline.sh delegates to octopus-hud.mjs"
fi

# 4.8: statusline.sh preserves bash fallback
if grep -q 'BASH FALLBACK' "$STATUSLINE_SH"; then
    assert_pass "4.8 statusline.sh preserves bash fallback"
else
    assert_fail "4.8 statusline.sh preserves bash fallback"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST GROUP 5: Opp 5 - Agent Teams Conditional Migration (8 tests)
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}Test Group 5: Opp 5 - Agent Teams Conditional Migration${NC}"
echo "------------------------------------------------------------"

# 5.1: OCTOPUS_AGENT_TEAMS env var declared
if grep -q '^OCTOPUS_AGENT_TEAMS=' "$ORCHESTRATE_SH"; then
    assert_pass "5.1 OCTOPUS_AGENT_TEAMS env var declared"
else
    assert_fail "5.1 OCTOPUS_AGENT_TEAMS env var declared"
fi

# 5.2: should_use_agent_teams() function exists
if grep -q '^should_use_agent_teams()' "$ORCHESTRATE_SH"; then
    assert_pass "5.2 should_use_agent_teams() function exists"
else
    assert_fail "5.2 should_use_agent_teams() function exists"
fi

# 5.3: should_use_agent_teams handles legacy override
if grep -A 15 '^should_use_agent_teams()' "$ORCHESTRATE_SH" | grep -q '"legacy"'; then
    assert_pass "5.3 should_use_agent_teams handles legacy override"
else
    assert_fail "5.3 should_use_agent_teams handles legacy override"
fi

# 5.4: should_use_agent_teams checks SUPPORTS_STABLE_AGENT_TEAMS
if grep -A 30 '^should_use_agent_teams()' "$ORCHESTRATE_SH" | grep -q 'SUPPORTS_STABLE_AGENT_TEAMS'; then
    assert_pass "5.4 should_use_agent_teams checks SUPPORTS_STABLE_AGENT_TEAMS"
else
    assert_fail "5.4 should_use_agent_teams checks SUPPORTS_STABLE_AGENT_TEAMS"
fi

# 5.5: should_use_agent_teams only allows Claude agent types
if grep -A 40 '^should_use_agent_teams()' "$ORCHESTRATE_SH" | grep -q 'claude|claude-sonnet|claude-opus|claude-opus-fast'; then
    assert_pass "5.5 should_use_agent_teams only allows Claude agent types"
else
    assert_fail "5.5 should_use_agent_teams only allows Claude agent types"
fi

# 5.6: spawn_agent calls should_use_agent_teams
if grep -A 200 '^spawn_agent()' "$ORCHESTRATE_SH" | grep -q 'should_use_agent_teams'; then
    assert_pass "5.6 spawn_agent calls should_use_agent_teams"
else
    assert_fail "5.6 spawn_agent calls should_use_agent_teams"
fi

# 5.7: Agent Teams path writes dispatch instruction file
if grep -A 250 '^spawn_agent()' "$ORCHESTRATE_SH" | grep -q 'AGENT_TEAMS_DISPATCH'; then
    assert_pass "5.7 Agent Teams path writes dispatch instruction"
else
    assert_fail "5.7 Agent Teams path writes dispatch instruction"
fi

# 5.8: Legacy path comment exists for Codex/Gemini fallback
if grep -q 'LEGACY PATH.*Execute agent in bash subprocess' "$ORCHESTRATE_SH"; then
    assert_pass "5.8 Legacy path documented for Codex/Gemini fallback"
else
    assert_fail "5.8 Legacy path documented for Codex/Gemini fallback"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST GROUP 6: Opp 6 - Workflow-as-Code YAML Runtime (12 tests)
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}Test Group 6: Opp 6 - Workflow-as-Code YAML Runtime${NC}"
echo "------------------------------------------------------------"

# 6.1: OCTOPUS_YAML_RUNTIME feature flag declared
if grep -q '^OCTOPUS_YAML_RUNTIME=' "$ORCHESTRATE_SH"; then
    assert_pass "6.1 OCTOPUS_YAML_RUNTIME feature flag declared"
else
    assert_fail "6.1 OCTOPUS_YAML_RUNTIME feature flag declared"
fi

# 6.2: parse_yaml_workflow() function exists
if grep -q '^parse_yaml_workflow()' "$ORCHESTRATE_SH"; then
    assert_pass "6.2 parse_yaml_workflow() function exists"
else
    assert_fail "6.2 parse_yaml_workflow() function exists"
fi

# 6.3: yaml_get_phases() function exists
if grep -q '^yaml_get_phases()' "$ORCHESTRATE_SH"; then
    assert_pass "6.3 yaml_get_phases() function exists"
else
    assert_fail "6.3 yaml_get_phases() function exists"
fi

# 6.4: yaml_get_phase_config() function exists
if grep -q '^yaml_get_phase_config()' "$ORCHESTRATE_SH"; then
    assert_pass "6.4 yaml_get_phase_config() function exists"
else
    assert_fail "6.4 yaml_get_phase_config() function exists"
fi

# 6.5: yaml_get_phase_agents() function exists
if grep -q '^yaml_get_phase_agents()' "$ORCHESTRATE_SH"; then
    assert_pass "6.5 yaml_get_phase_agents() function exists"
else
    assert_fail "6.5 yaml_get_phase_agents() function exists"
fi

# 6.6: resolve_prompt_template() function exists
if grep -q '^resolve_prompt_template()' "$ORCHESTRATE_SH"; then
    assert_pass "6.6 resolve_prompt_template() function exists"
else
    assert_fail "6.6 resolve_prompt_template() function exists"
fi

# 6.7: execute_workflow_phase() function exists
if grep -q '^execute_workflow_phase()' "$ORCHESTRATE_SH"; then
    assert_pass "6.7 execute_workflow_phase() function exists"
else
    assert_fail "6.7 execute_workflow_phase() function exists"
fi

# 6.8: run_yaml_workflow() function exists
if grep -q '^run_yaml_workflow()' "$ORCHESTRATE_SH"; then
    assert_pass "6.8 run_yaml_workflow() function exists"
else
    assert_fail "6.8 run_yaml_workflow() function exists"
fi

# 6.9: embrace_full_workflow delegates to YAML runtime
if grep -A 150 '^embrace_full_workflow()' "$ORCHESTRATE_SH" | grep -q 'run_yaml_workflow'; then
    assert_pass "6.9 embrace_full_workflow delegates to YAML runtime"
else
    assert_fail "6.9 embrace_full_workflow delegates to YAML runtime"
fi

# 6.10: YAML runtime has feature flag check (auto/enabled/disabled)
if grep -A 150 '^embrace_full_workflow()' "$ORCHESTRATE_SH" | grep -q 'OCTOPUS_YAML_RUNTIME'; then
    assert_pass "6.10 YAML runtime delegation checks feature flag"
else
    assert_fail "6.10 YAML runtime delegation checks feature flag"
fi

# 6.11: Hardcoded fallback preserved
if grep -q 'HARDCODED PHASE LOGIC.*fallback' "$ORCHESTRATE_SH"; then
    assert_pass "6.11 Hardcoded phase logic preserved as fallback"
else
    assert_fail "6.11 Hardcoded phase logic preserved as fallback"
fi

# 6.12: YAML runtime references embrace.yaml
if grep -A 20 '^run_yaml_workflow()' "$ORCHESTRATE_SH" | grep -q 'workflows/.*yaml'; then
    assert_pass "6.12 YAML runtime references workflow YAML files"
else
    assert_fail "6.12 YAML runtime references workflow YAML files"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST GROUP 7: Hook Integration & Session State (6 tests)
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}Test Group 7: Hook Integration & Session State${NC}"
echo "------------------------------------------------------------"

# 7.1: Session state includes phase_tasks field
if grep -q 'phase_tasks' "$ORCHESTRATE_SH"; then
    assert_pass "7.1 Session state includes phase_tasks field"
else
    assert_fail "7.1 Session state includes phase_tasks field"
fi

# 7.2: Session state includes agent_queue field
if grep -q 'agent_queue' "$ORCHESTRATE_SH"; then
    assert_pass "7.2 Session state includes agent_queue field"
else
    assert_fail "7.2 Session state includes agent_queue field"
fi

# 7.3: Session state includes quality_gates field
if grep -q 'quality_gates' "$ORCHESTRATE_SH"; then
    assert_pass "7.3 Session state includes quality_gates field"
else
    assert_fail "7.3 Session state includes quality_gates field"
fi

# 7.4: execute_workflow_phase updates phase_tasks for task-completed-transition.sh
if grep -A 100 '^execute_workflow_phase()' "$ORCHESTRATE_SH" | grep -q 'phase_tasks'; then
    assert_pass "7.4 execute_workflow_phase updates phase_tasks"
else
    assert_fail "7.4 execute_workflow_phase updates phase_tasks"
fi

# 7.5: task-completed-transition.sh hook file exists
if [[ -f "${PLUGIN_DIR}/hooks/task-completed-transition.sh" ]]; then
    assert_pass "7.5 task-completed-transition.sh hook file exists"
else
    assert_fail "7.5 task-completed-transition.sh hook file exists"
fi

# 7.6: teammate-idle-dispatch.sh hook file exists
if [[ -f "${PLUGIN_DIR}/hooks/teammate-idle-dispatch.sh" ]]; then
    assert_pass "7.6 teammate-idle-dispatch.sh hook file exists"
else
    assert_fail "7.6 teammate-idle-dispatch.sh hook file exists"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST GROUP 8: embrace.yaml Schema Validation (6 tests)
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}Test Group 8: embrace.yaml Schema Validation${NC}"
echo "------------------------------------------------------------"

if [[ -f "$EMBRACE_YAML" ]]; then
    # 8.1: embrace.yaml has 4 phases defined
    phase_count=$(grep -c '  - name:' "$EMBRACE_YAML" || echo "0")
    if [[ "$phase_count" -eq 4 ]]; then
        assert_pass "8.1 embrace.yaml has 4 phases defined"
    else
        assert_fail "8.1 embrace.yaml has 4 phases defined" "Found: $phase_count"
    fi

    # 8.2: embrace.yaml defines probe/grasp/tangle/ink phases
    for phase in probe grasp tangle ink; do
        if grep -q "name: $phase" "$EMBRACE_YAML"; then
            assert_pass "8.2.$phase embrace.yaml defines $phase phase"
        else
            assert_fail "8.2.$phase embrace.yaml defines $phase phase"
        fi
    done

    # 8.3: embrace.yaml has autonomy_modes
    if grep -q 'autonomy_modes:' "$EMBRACE_YAML"; then
        assert_pass "8.3 embrace.yaml has autonomy_modes"
    else
        assert_fail "8.3 embrace.yaml has autonomy_modes"
    fi

    # 8.4: embrace.yaml defines providers
    if grep -q 'providers:' "$EMBRACE_YAML"; then
        assert_pass "8.4 embrace.yaml defines providers"
    else
        assert_fail "8.4 embrace.yaml defines providers"
    fi
else
    assert_fail "8.1-8.4 embrace.yaml not found, skipping schema tests"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST GROUP 9: Cross-Cutting Concerns (5 tests)
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}Test Group 9: Cross-Cutting Concerns${NC}"
echo "------------------------------------------------------------"

# 9.1: resolve_prompt_template handles {{prompt}} placeholder
if grep -A 10 '^resolve_prompt_template()' "$ORCHESTRATE_SH" | grep -q 'prompt'; then
    assert_pass "9.1 resolve_prompt_template handles {{prompt}} placeholder"
else
    assert_fail "9.1 resolve_prompt_template handles {{prompt}} placeholder"
fi

# 9.2: Memory injection prepends "Previous Context" header
if grep -q '## Previous Context (from' "$ORCHESTRATE_SH"; then
    assert_pass "9.2 Memory injection uses Previous Context header"
else
    assert_fail "9.2 Memory injection uses Previous Context header"
fi

# 9.3: build_memory_context truncates to ~2000 chars
if grep -A 80 '^build_memory_context()' "$ORCHESTRATE_SH" | grep -q 'head -c 2000'; then
    assert_pass "9.3 build_memory_context truncates to 2000 chars"
else
    assert_fail "9.3 build_memory_context truncates to 2000 chars"
fi

# 9.4: HUD has silent error handling (outputs empty on failure)
if grep -q 'process.exit(0)' "$HUD_MJS"; then
    assert_pass "9.4 HUD exits cleanly on error (silent fallback)"
else
    assert_fail "9.4 HUD exits cleanly on error (silent fallback)"
fi

# 9.5: statusline.sh reads stdin once before delegation decision
if head -25 "$STATUSLINE_SH" | grep -q 'input=$(cat)'; then
    assert_pass "9.5 statusline.sh reads stdin once before delegation"
else
    assert_fail "9.5 statusline.sh reads stdin once before delegation"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Group 10: Release Validation Safety (v8.5.0 fixes)
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}Test Group 10: Release Validation Safety${NC}"
echo "------------------------------------------------------------"

VALIDATE_RELEASE="$PLUGIN_DIR/scripts/validate-release.sh"

# 10.1: validate-release.sh exists
if [[ -f "$VALIDATE_RELEASE" ]]; then
    assert_pass "10.1 validate-release.sh exists"
else
    assert_fail "10.1 validate-release.sh exists"
fi

# 10.2: Command frontmatter grep has pipefail guard
if grep "grep -o 'command: " "$VALIDATE_RELEASE" | grep -q '|| true'; then
    assert_pass "10.2 Command frontmatter grep has pipefail guard (|| true)"
else
    assert_fail "10.2 Command frontmatter grep has pipefail guard (|| true)"
fi

# 10.3: Skill frontmatter grep has pipefail guard
if grep "grep -o 'name: " "$VALIDATE_RELEASE" | grep -q '|| true'; then
    assert_pass "10.3 Skill frontmatter grep has pipefail guard (|| true)"
else
    assert_fail "10.3 Skill frontmatter grep has pipefail guard (|| true)"
fi

# 10.4: All skill files use valid name prefixes
invalid_skill_count=0
for skill_file in "$PLUGIN_DIR/.claude/skills/"*.md; do
    sname=$(sed -n '2p' "$skill_file" | grep -o 'name: .*' | sed 's/name: //' || true)
    if [[ -n "$sname" ]] && ! echo "$sname" | grep -qE '^(skill-|flow-|octopus-|sys-)'; then
        invalid_skill_count=$((invalid_skill_count + 1))
    fi
done
if [[ $invalid_skill_count -eq 0 ]]; then
    assert_pass "10.4 All skill names use valid prefixes"
else
    assert_fail "10.4 All skill names use valid prefixes ($invalid_skill_count invalid)"
fi

# 10.5: validate-release.sh uses set -euo pipefail
if head -10 "$VALIDATE_RELEASE" | grep -q 'set -euo pipefail'; then
    assert_pass "10.5 validate-release.sh uses strict mode (set -euo pipefail)"
else
    assert_fail "10.5 validate-release.sh uses strict mode (set -euo pipefail)"
fi

# 10.6: No command frontmatter uses namespace prefix (octo:)
has_namespace=0
for cmd_file in "$PLUGIN_DIR/.claude/commands/"*.md; do
    cname=$(sed -n '2p' "$cmd_file" | grep -o 'command: .*' | sed 's/command: //' || true)
    if [[ -n "$cname" ]] && [[ "$cname" == *":"* ]]; then
        has_namespace=$((has_namespace + 1))
    fi
done
if [[ $has_namespace -eq 0 ]]; then
    assert_pass "10.6 No commands use namespace prefix in frontmatter"
else
    assert_fail "10.6 No commands use namespace prefix in frontmatter ($has_namespace found)"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════
echo "============================================================"
echo -e "${BLUE}Test Summary - v8.5.0 Strategic Feature Implementation${NC}"
echo "============================================================"
echo -e "Total tests:  ${BLUE}$TESTS_RUN${NC}"
echo -e "Passed:       ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed:       ${RED}$TESTS_FAILED${NC}"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}All v8.5.0 strategic feature tests passed!${NC}"
    exit 0
else
    echo -e "${RED}$TESTS_FAILED test(s) failed${NC}"
    exit 1
fi
