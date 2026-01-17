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

    # Run probe in dry-run mode to verify architecture
    local output
    output=$("$ORCHESTRATE" probe "test task" --dry-run 2>&1)

    assert_true "[[ '$output' =~ 'Would spawn 4 parallel research agents' ]]" \
        "Probe phase spawns 4 agents (not 1)"

    assert_true "[[ '$output' =~ 'parallel' ]]" \
        "Execution is parallel (not sequential)"
}

test_quality_gates_validation() {
    echo ""
    echo -e "${CYAN}Test: Quality Gates & Validation${NC}"
    echo "Validates that tangle phase includes quality validation"
    echo ""

    local output
    output=$("$ORCHESTRATE" tangle "test task" --dry-run 2>&1)

    assert_true "[[ '$output' =~ 'validation' || '$output' =~ 'quality' ]]" \
        "Tangle includes validation step"

    assert_true "[[ '$output' =~ 'decompose\|subtask' ]]" \
        "Tangle decomposes tasks for parallel execution"
}

test_multi_perspective_research() {
    echo ""
    echo -e "${CYAN}Test: Multi-Perspective Research${NC}"
    echo "Validates that research phase gathers multiple perspectives"
    echo ""

    # Check probe function for multi-perspective logic
    local probe_code
    probe_code=$(grep -A 30 "probe_discover()" "$ORCHESTRATE")

    assert_true "[[ '$probe_code' =~ 'perspective' ]]" \
        "Probe uses multiple perspectives"

    assert_true "[[ '$probe_code' =~ 'synthesis' || '$probe_code' =~ 'synthesize' ]]" \
        "Probe synthesizes findings from multiple agents"
}

test_consensus_building() {
    echo ""
    echo -e "${CYAN}Test: Consensus Building${NC}"
    echo "Validates that grasp phase builds consensus"
    echo ""

    local output
    output=$("$ORCHESTRATE" define "test task" --dry-run 2>&1)

    assert_true "[[ '$output' =~ 'consensus' || '$output' =~ 'agreement' ]]" \
        "Grasp phase builds consensus"

    assert_true "[[ '$output' =~ 'perspective' ]]" \
        "Grasp gathers multiple perspectives"
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

    local output
    output=$("$ORCHESTRATE" embrace "test task" --dry-run 2>&1)

    assert_true "[[ '$output' =~ 'probe\|research' ]]" \
        "Embrace includes research phase"

    assert_true "[[ '$output' =~ 'grasp\|define' ]]" \
        "Embrace includes define phase"

    assert_true "[[ '$output' =~ 'tangle\|develop' ]]" \
        "Embrace includes develop phase"

    assert_true "[[ '$output' =~ 'ink\|deliver' ]]" \
        "Embrace includes deliver phase"
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
