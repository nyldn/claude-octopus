#!/usr/bin/env bash
# Comprehensive test suite for Phases 1-3
# Tests state management, validation gates, and context capture

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Change to plugin directory
cd "$(dirname "$0")/.."

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Phase 1-3 Integration Test Suite${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

# Test helper functions
test_start() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -e "${YELLOW}TEST $TESTS_RUN:${NC} $1"
}

test_pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}  ✓ PASS${NC}"
    echo ""
}

test_fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}  ✗ FAIL:${NC} $1"
    echo ""
}

assert_file_exists() {
    if [ -f "$1" ]; then
        return 0
    else
        test_fail "File does not exist: $1"
        return 1
    fi
}

assert_command_succeeds() {
    if "$@" > /dev/null 2>&1; then
        return 0
    else
        test_fail "Command failed: $*"
        return 1
    fi
}

assert_equals() {
    if [ "$1" = "$2" ]; then
        return 0
    else
        test_fail "Expected '$2', got '$1'"
        return 1
    fi
}

assert_contains() {
    if echo "$1" | grep -q "$2"; then
        return 0
    else
        test_fail "Output does not contain '$2'"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════
# PHASE 1: State Management Tests
# ═══════════════════════════════════════════════════════

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  PHASE 1: State Management${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

# Clean up any existing state
rm -rf .claude-octopus 2>/dev/null || true

# Test 1: State initialization
test_start "State initialization"
if assert_command_succeeds ./scripts/state-manager.sh init_state; then
    if assert_file_exists ".claude-octopus/state.json"; then
        test_pass
    fi
fi

# Test 2: State file is valid JSON
test_start "State file is valid JSON"
if jq empty .claude-octopus/state.json 2>/dev/null; then
    test_pass
else
    test_fail "State file is not valid JSON"
fi

# Test 3: State has required fields
test_start "State has required fields"
required_fields=("version" "decisions" "blockers" "context" "metrics")
all_present=true
for field in "${required_fields[@]}"; do
    if ! jq -e ".$field" .claude-octopus/state.json > /dev/null 2>&1; then
        test_fail "Missing required field: $field"
        all_present=false
    fi
done
if [ "$all_present" = true ]; then
    test_pass
fi

# Test 4: Write decision
test_start "Write decision"
if assert_command_succeeds ./scripts/state-manager.sh write_decision \
    "define" "React 19 + Next.js 15" "Modern stack with best DX"; then
    decision_count=$(jq '.decisions | length' .claude-octopus/state.json)
    if assert_equals "$decision_count" "1"; then
        test_pass
    fi
fi

# Test 5: Update context
test_start "Update context"
if assert_command_succeeds ./scripts/state-manager.sh update_context \
    "discover" "Researched auth patterns, chose JWT"; then
    discover_context=$(jq -r '.context.discover' .claude-octopus/state.json)
    if assert_equals "$discover_context" "Researched auth patterns, chose JWT"; then
        test_pass
    fi
fi

# Test 6: Update metrics
test_start "Update metrics - phases completed"
if assert_command_succeeds ./scripts/state-manager.sh update_metrics "phases_completed" "1"; then
    phases=$(jq '.metrics.phases_completed' .claude-octopus/state.json)
    if assert_equals "$phases" "1"; then
        test_pass
    fi
fi

# Test 7: Update provider metrics
test_start "Update metrics - provider usage"
if assert_command_succeeds ./scripts/state-manager.sh update_metrics "provider" "gemini"; then
    gemini_usage=$(jq '.metrics.provider_usage.gemini' .claude-octopus/state.json)
    if assert_equals "$gemini_usage" "1"; then
        test_pass
    fi
fi

# Test 8: Write blocker
test_start "Write blocker"
if assert_command_succeeds ./scripts/state-manager.sh write_blocker \
    "Waiting for API deployment" "develop" "active"; then
    blocker_count=$(jq '.blockers | length' .claude-octopus/state.json)
    if assert_equals "$blocker_count" "1"; then
        test_pass
    fi
fi

# Test 9: Get decisions
test_start "Get decisions"
decisions=$(./scripts/state-manager.sh get_decisions "all")
if assert_contains "$decisions" "React 19"; then
    test_pass
fi

# Test 10: State backup created
test_start "State backup created on write"
if assert_file_exists ".claude-octopus/state.json.backup"; then
    test_pass
fi

# ═══════════════════════════════════════════════════════
# PHASE 2: Validation Gates Tests
# ═══════════════════════════════════════════════════════

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  PHASE 2: Validation Gates${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

# Test 11: Validation gates reference exists
test_start "Validation gates reference file exists"
if assert_file_exists ".claude/references/validation-gates.md"; then
    test_pass
fi

# Test 12: All flow skills have enforcement
test_start "All flow skills have enforcement"
flow_skills=("flow-discover" "flow-define" "flow-develop" "flow-deliver")
all_have_enforcement=true
for skill in "${flow_skills[@]}"; do
    if ! grep -q "execution_mode: enforced" ".claude/skills/${skill}.md" 2>/dev/null; then
        test_fail "$skill missing enforcement"
        all_have_enforcement=false
    fi
done
if [ "$all_have_enforcement" = true ]; then
    test_pass
fi

# Test 13: Count skills with enforcement
test_start "Skills with enforcement count"
enforcement_count=$(grep -l "execution_mode: enforced" .claude/skills/*.md | wc -l | tr -d ' ')
if [ "$enforcement_count" -ge 16 ]; then
    test_pass
else
    test_fail "Expected at least 16 skills with enforcement, got $enforcement_count"
fi

# Test 14: Validation gates have required fields
test_start "Enforcement skills have validation_gates"
skills_with_enforcement=$(grep -l "execution_mode: enforced" .claude/skills/*.md)
all_have_gates=true
for skill in $skills_with_enforcement; do
    if ! grep -q "validation_gates:" "$skill" 2>/dev/null; then
        test_fail "$(basename "$skill") missing validation_gates"
        all_have_gates=false
    fi
done
if [ "$all_have_gates" = true ]; then
    test_pass
fi

# Test 15: Skills have pre_execution_contract (most enforced skills have it)
test_start "Enforcement skills have pre_execution_contract"
contract_count=0
for skill in $skills_with_enforcement; do
    if grep -q "pre_execution_contract:" "$skill" 2>/dev/null; then
        contract_count=$((contract_count + 1))
    fi
done
if [ "$contract_count" -ge 4 ]; then
    test_pass
else
    test_fail "Only $contract_count skills have pre_execution_contract (expected at least 4)"
fi

# ═══════════════════════════════════════════════════════
# PHASE 3: Context Capture Tests
# ═══════════════════════════════════════════════════════

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  PHASE 3: Context Capture${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

# Test 16: Context manager script exists
test_start "Context manager script exists"
if assert_file_exists "scripts/context-manager.sh"; then
    test_pass
fi

# Test 17: Context manager is executable
test_start "Context manager is executable"
if [ -x "scripts/context-manager.sh" ]; then
    test_pass
else
    test_fail "context-manager.sh is not executable"
fi

# Test 18: Context directory initialization
test_start "Context directory initialization"
if assert_command_succeeds ./scripts/context-manager.sh init_context_dir; then
    if [ -d ".claude-octopus/context" ]; then
        test_pass
    else
        test_fail "Directory .claude-octopus/context not created"
    fi
fi

# Test 19: Create templated context
test_start "Create templated context"
if assert_command_succeeds ./scripts/context-manager.sh create_templated_context \
    "test-workflow" "Test Feature" "Test vision" "Test approach"; then
    if assert_file_exists ".claude-octopus/context/test-workflow-context.md"; then
        test_pass
    fi
fi

# Test 20: Context file has required sections
test_start "Context file has required sections"
context_file=".claude-octopus/context/test-workflow-context.md"
required_sections=("User Vision" "Technical Approach" "Scope" "Decisions Made")
all_sections_present=true
for section in "${required_sections[@]}"; do
    if ! grep -q "$section" "$context_file" 2>/dev/null; then
        test_fail "Context file missing section: $section"
        all_sections_present=false
    fi
done
if [ "$all_sections_present" = true ]; then
    test_pass
fi

# Test 21: Read context
test_start "Read context"
context_content=$(./scripts/context-manager.sh read_context "test-workflow")
if assert_contains "$context_content" "Test Feature"; then
    test_pass
fi

# Test 22: List contexts
test_start "List contexts"
context_list=$(./scripts/context-manager.sh list_contexts)
if assert_contains "$context_list" "test-workflow-context.md"; then
    test_pass
fi

# Test 23: flow-define has phase discussion step
test_start "flow-define has phase discussion step"
if grep -q "Phase Discussion" ".claude/skills/flow-define.md"; then
    test_pass
else
    test_fail "flow-define missing phase discussion step"
fi

# Test 24: flow-define uses AskUserQuestion
test_start "flow-define references AskUserQuestion"
if grep -q "AskUserQuestion" ".claude/skills/flow-define.md"; then
    test_pass
else
    test_fail "flow-define missing AskUserQuestion reference"
fi

# Test 25: flow-define creates context file
test_start "flow-define creates context file"
if grep -q "create_templated_context" ".claude/skills/flow-define.md"; then
    test_pass
else
    test_fail "flow-define missing context creation"
fi

# ═══════════════════════════════════════════════════════
# Integration Tests
# ═══════════════════════════════════════════════════════

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Integration Tests${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

# Test 26: State manager integration in orchestrate.sh
test_start "orchestrate.sh sources state-manager.sh"
if grep -q "source.*state-manager.sh" "scripts/orchestrate.sh"; then
    test_pass
else
    test_fail "orchestrate.sh doesn't source state-manager.sh"
fi

# Test 27: orchestrate.sh initializes state
test_start "orchestrate.sh initializes state"
if grep -q "init_state" "scripts/orchestrate.sh"; then
    test_pass
else
    test_fail "orchestrate.sh doesn't call init_state"
fi

# Test 28: All flow skills read state
test_start "Flow skills read prior state"
flow_with_state=0
for skill in "${flow_skills[@]}"; do
    if grep -q "state-manager.sh.*read_state\|get_context\|get_decisions" ".claude/skills/${skill}.md"; then
        flow_with_state=$((flow_with_state + 1))
    fi
done
if [ "$flow_with_state" -eq 4 ]; then
    test_pass
else
    test_fail "Only $flow_with_state/4 flow skills read state"
fi

# Test 29: All flow skills update state
test_start "Flow skills update state"
flow_with_updates=0
for skill in "${flow_skills[@]}"; do
    if grep -q "update_context\|write_decision\|update_metrics" ".claude/skills/${skill}.md"; then
        flow_with_updates=$((flow_with_updates + 1))
    fi
done
if [ "$flow_with_updates" -eq 4 ]; then
    test_pass
else
    test_fail "Only $flow_with_updates/4 flow skills update state"
fi

# Test 30: Directory structure is complete
test_start "Directory structure is complete"
required_dirs=(
    ".claude-octopus"
    ".claude-octopus/context"
    ".claude-octopus/summaries"
    ".claude-octopus/quick"
)
all_dirs_exist=true
for dir in "${required_dirs[@]}"; do
    if [ ! -d "$dir" ]; then
        test_fail "Directory missing: $dir"
        all_dirs_exist=false
    fi
done
if [ "$all_dirs_exist" = true ]; then
    test_pass
fi

# ═══════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Test Summary${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "Total tests:  ${BLUE}$TESTS_RUN${NC}"
echo -e "Passed:       ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed:       ${RED}$TESTS_FAILED${NC}"
echo ""

if [ "$TESTS_FAILED" -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
fi
