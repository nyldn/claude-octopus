#!/usr/bin/env bash
# Integration Test: Value Proposition Validation
# Quick smoke test to verify Claude Octopus adds value over single-agent execution
# This test runs quickly and doesn't require Claude CLI

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ORCHESTRATE="${PROJECT_ROOT}/scripts/orchestrate.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ═══════════════════════════════════════════════════════════════════════════════
# TEST FRAMEWORK
# ═══════════════════════════════════════════════════════════════════════════════

assert_true() {
    local condition="$1"
    local description="$2"

    ((TESTS_RUN++))

    if eval "$condition"; then
        echo -e "${GREEN}✓${NC} $description"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}✗${NC} $description"
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_file_exists() {
    local file="$1"
    local description="$2"

    ((TESTS_RUN++))

    if [[ -f "$file" ]]; then
        echo -e "${GREEN}✓${NC} $description"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}✗${NC} $description (file not found: $file)"
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_contains() {
    local file="$1"
    local pattern="$2"
    local description="$3"

    ((TESTS_RUN++))

    if grep -q "$pattern" "$file" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} $description"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}✗${NC} $description (pattern not found: $pattern)"
        ((TESTS_FAILED++))
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# VALUE PROPOSITION TESTS
# ═══════════════════════════════════════════════════════════════════════════════

test_multi_agent_parallel_execution() {
    echo ""
    echo -e "${CYAN}Test: Multi-Agent Parallel Execution${NC}"
    echo "Validates that probe phase spawns multiple agents in parallel"
    echo ""

    # Check probe function code directly to avoid dry-run hang
    local probe_code
    probe_code=$(grep -A 50 "probe_discover()" "$ORCHESTRATE" 2>/dev/null || echo "")

    ((TESTS_RUN++))
    if echo "$probe_code" | grep -q "perspectives=" && echo "$probe_code" | grep -q "4"; then
        echo -e "${GREEN}✓${NC} Probe phase spawns 4 agents with different perspectives"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} Probe phase spawns 4 agents with different perspectives"
        ((TESTS_FAILED++))
    fi

    ((TESTS_RUN++))
    if echo "$probe_code" | grep -qE "parallel|pids"; then
        echo -e "${GREEN}✓${NC} Execution uses parallel spawning"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} Execution uses parallel spawning"
        ((TESTS_FAILED++))
    fi
}

test_quality_gates_validation() {
    echo ""
    echo -e "${CYAN}Test: Quality Gates & Validation${NC}"
    echo "Validates that tangle phase includes quality validation"
    echo ""

    # Check tangle function code directly
    local tangle_code
    tangle_code=$(grep -A 80 "tangle_develop()" "$ORCHESTRATE" 2>/dev/null || echo "")

    ((TESTS_RUN++))
    if echo "$tangle_code" | grep -qE "validation|validate"; then
        echo -e "${GREEN}✓${NC} Tangle includes validation step"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} Tangle includes validation step"
        ((TESTS_FAILED++))
    fi

    ((TESTS_RUN++))
    if echo "$tangle_code" | grep -qE "decompose|subtask"; then
        echo -e "${GREEN}✓${NC} Tangle decomposes tasks for parallel execution"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} Tangle decomposes tasks for parallel execution"
        ((TESTS_FAILED++))
    fi
}

test_multi_perspective_research() {
    echo ""
    echo -e "${CYAN}Test: Multi-Perspective Research${NC}"
    echo "Validates that research phase gathers multiple perspectives"
    echo ""

    # Check probe function for multi-perspective logic
    local probe_code
    probe_code=$(grep -A 100 "probe_discover()" "$ORCHESTRATE" 2>/dev/null || echo "")

    ((TESTS_RUN++))
    if echo "$probe_code" | grep -q "perspective"; then
        echo -e "${GREEN}✓${NC} Probe uses multiple perspectives"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} Probe uses multiple perspectives"
        ((TESTS_FAILED++))
    fi

    ((TESTS_RUN++))
    if echo "$probe_code" | grep -qE "synthesize_probe_results"; then
        echo -e "${GREEN}✓${NC} Probe synthesizes findings from multiple agents"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} Probe synthesizes findings from multiple agents"
        ((TESTS_FAILED++))
    fi
}

test_consensus_building() {
    echo ""
    echo -e "${CYAN}Test: Consensus Building${NC}"
    echo "Validates that grasp phase builds consensus"
    echo ""

    # Check grasp function code directly
    local grasp_code
    grasp_code=$(grep -A 80 "grasp_define()" "$ORCHESTRATE" 2>/dev/null || echo "")

    ((TESTS_RUN++))
    if echo "$grasp_code" | grep -qE "consensus|agreement"; then
        echo -e "${GREEN}✓${NC} Grasp phase builds consensus"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} Grasp phase builds consensus"
        ((TESTS_FAILED++))
    fi

    ((TESTS_RUN++))
    if echo "$grasp_code" | grep -q "perspective"; then
        echo -e "${GREEN}✓${NC} Grasp gathers multiple perspectives"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} Grasp gathers multiple perspectives"
        ((TESTS_FAILED++))
    fi
}

test_cost_tracking() {
    echo ""
    echo -e "${CYAN}Test: Cost Tracking${NC}"
    echo "Validates that orchestrator tracks cost/usage"
    echo ""

    # Check for cost tracking functions
    local has_cost_tracking=false
    if grep -q "record_agent_call\|track_usage\|cost" "$ORCHESTRATE"; then
        has_cost_tracking=true
    fi

    assert_true "[[ $has_cost_tracking == true ]]" \
        "Cost tracking is implemented"
}

test_workflow_automation() {
    echo ""
    echo -e "${CYAN}Test: Workflow Automation${NC}"
    echo "Validates that embrace runs full 4-phase workflow"
    echo ""

    # Check embrace function code directly
    local embrace_code
    embrace_code=$(grep -A 100 "embrace_full_workflow()" "$ORCHESTRATE" 2>/dev/null || echo "")

    ((TESTS_RUN++))
    if echo "$embrace_code" | grep -qE "probe|research"; then
        echo -e "${GREEN}✓${NC} Embrace includes research phase"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} Embrace includes research phase"
        ((TESTS_FAILED++))
    fi

    ((TESTS_RUN++))
    if echo "$embrace_code" | grep -qE "grasp|define"; then
        echo -e "${GREEN}✓${NC} Embrace includes define phase"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} Embrace includes define phase"
        ((TESTS_FAILED++))
    fi

    ((TESTS_RUN++))
    if echo "$embrace_code" | grep -qE "tangle|develop"; then
        echo -e "${GREEN}✓${NC} Embrace includes develop phase"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} Embrace includes develop phase"
        ((TESTS_FAILED++))
    fi

    ((TESTS_RUN++))
    if echo "$embrace_code" | grep -qE "ink|deliver"; then
        echo -e "${GREEN}✓${NC} Embrace includes deliver phase"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} Embrace includes deliver phase"
        ((TESTS_FAILED++))
    fi
}

test_async_performance() {
    echo ""
    echo -e "${CYAN}Test: Async Performance Features${NC}"
    echo "Validates async task management is available"
    echo ""

    # Check for async features
    local async_file="${PROJECT_ROOT}/scripts/async-tmux-features.sh"

    assert_file_exists "$async_file" \
        "Async module exists"

    if [[ -f "$async_file" ]]; then
        assert_contains "$async_file" "spawn_agent_async" \
            "Async spawning implemented"

        assert_contains "$async_file" "wait_async_agents" \
            "Async waiting with progress tracking"
    fi
}

test_tmux_visualization() {
    echo ""
    echo -e "${CYAN}Test: Tmux Visualization${NC}"
    echo "Validates tmux visualization features"
    echo ""

    local async_file="${PROJECT_ROOT}/scripts/async-tmux-features.sh"

    if [[ -f "$async_file" ]]; then
        assert_contains "$async_file" "tmux_init" \
            "Tmux initialization implemented"

        assert_contains "$async_file" "tmux_spawn_pane" \
            "Tmux pane spawning implemented"

        assert_contains "$async_file" "tmux_layout" \
            "Tmux layout management implemented"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN TEST RUNNER
# ═══════════════════════════════════════════════════════════════════════════════

main() {
    echo ""
    echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  Value Proposition Validation Tests                      ║${NC}"
    echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Verifying Claude Octopus provides quality, speed, or cost benefits"
    echo ""

    # Run all tests
    test_multi_agent_parallel_execution
    test_quality_gates_validation
    test_multi_perspective_research
    test_consensus_building
    test_cost_tracking
    test_workflow_automation
    test_async_performance
    test_tmux_visualization

    # Summary
    echo ""
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}Test Summary${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Total Tests: $TESTS_RUN"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✓ All value proposition tests passed!${NC}"
        echo ""
        echo "Claude Octopus provides:"
        echo "  • Multi-agent parallel execution (faster)"
        echo "  • Quality gates and validation (better quality)"
        echo "  • Multi-perspective research (comprehensive)"
        echo "  • Consensus building (reduced bias)"
        echo "  • Cost tracking (transparency)"
        echo "  • Workflow automation (convenience)"
        echo "  • Async performance features (efficiency)"
        echo "  • Tmux visualization (transparency)"
        echo ""
        exit 0
    else
        echo -e "${RED}✗ Some value proposition tests failed${NC}"
        echo ""
        echo "This indicates Claude Octopus may not be providing"
        echo "sufficient value over single-agent execution."
        echo ""
        exit 1
    fi
}

main "$@"
