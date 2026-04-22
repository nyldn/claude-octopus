#!/bin/bash
# Test suite for v2.1.12+ feature integration
# Tests new features while ensuring backward compatibility

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/helpers/test-framework.sh"
test_suite "for v2.1.12+ feature integration"

ORCHESTRATE="${PROJECT_ROOT}/scripts/orchestrate.sh"
# v9.12: Search orchestrate.sh + lib/*.sh for functions that may have been decomposed
ALL_SRC=$(mktemp)
cat "$ORCHESTRATE" "$(dirname "$ORCHESTRATE")/lib/"*.sh > "$ALL_SRC" 2>/dev/null
trap 'rm -f "$ALL_SRC"' EXIT

# Test result tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0


# Logging functions
log_test() {
    echo -e "${YELLOW}[TEST]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

log_info() {
    echo -e "[INFO] $1"
}

# Test helper
run_test() {
    local test_name="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    log_test "$test_name"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Unit Tests: Version Detection
# ═══════════════════════════════════════════════════════════════════════════════

test_version_detection() {
    run_test "Version detection functions exist"

    if grep -q "detect_claude_code_version" "$ALL_SRC"; then
        log_pass "detect_claude_code_version function found"
    else
        log_fail "detect_claude_code_version function not found"
        return 1
    fi

    if grep -q "version_compare" "$ALL_SRC"; then
        log_pass "version_compare function found"
    else
        log_fail "version_compare function not found"
        return 1
    fi
}

test_feature_flags() {
    run_test "Feature flags defined"

    local flags=(
        "SUPPORTS_TASK_MANAGEMENT"
        "SUPPORTS_FORK_CONTEXT"
        "SUPPORTS_BASH_WILDCARDS"
        "SUPPORTS_AGENT_FIELD"
    )

    for flag in "${flags[@]}"; do
        if grep -q "$flag" "$ALL_SRC"; then
            log_pass "Feature flag $flag found"
        else
            log_fail "Feature flag $flag not found"
            return 1
        fi
    done
}

# ═══════════════════════════════════════════════════════════════════════════════
# Unit Tests: Fork Context
# ═══════════════════════════════════════════════════════════════════════════════

test_fork_context_support() {
    run_test "Fork context support in spawn_agent"

    if grep -q "use_fork" "$ALL_SRC"; then
        log_pass "Fork context parameter found in spawn_agent"
    else
        log_fail "Fork context parameter not found"
        return 1
    fi

    if grep -q "SUPPORTS_FORK_CONTEXT" "$ALL_SRC"; then
        log_pass "Fork context feature flag check found"
    else
        log_fail "Fork context feature flag check not found"
        return 1
    fi
}

test_fork_markers() {
    run_test "Fork marker creation"

    if grep -q "fork_marker" "$ALL_SRC"; then
        log_pass "Fork marker creation logic found"
    else
        log_fail "Fork marker creation logic not found"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Unit Tests: Hook System
# ═══════════════════════════════════════════════════════════════════════════════

test_hook_scripts_exist() {
    run_test "New hook scripts exist"

    local hooks=(
        "task-dependency-validator.sh"
        "provider-routing-validator.sh"
        "task-completion-checkpoint.sh"
    )

    for hook in "${hooks[@]}"; do
        local hook_path="${PROJECT_ROOT}/hooks/${hook}"
        if [[ -f "$hook_path" && -x "$hook_path" ]]; then
            log_pass "Hook script $hook exists and is executable"
        else
            log_fail "Hook script $hook missing or not executable"
            return 1
        fi
    done
}

test_hooks_json_updated() {
    run_test "hooks.json contains new patterns"

    local hooks_json="${PROJECT_ROOT}/.claude-plugin/hooks.json"

    if [[ ! -f "$hooks_json" ]]; then
        log_fail "hooks.json not found"
        return 1
    fi

    if grep -q "TaskCreate" "$hooks_json"; then
        log_pass "TaskCreate hook matcher found"
    else
        log_fail "TaskCreate hook matcher not found"
        return 1
    fi

    if grep -q "TaskUpdate" "$hooks_json"; then
        log_pass "TaskUpdate hook matcher found"
    else
        log_fail "TaskUpdate hook matcher not found"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Integration Tests: Flow Skills
# ═══════════════════════════════════════════════════════════════════════════════

test_flow_skill_frontmatter() {
    run_test "Flow skills have v2.1.12+ frontmatter"

    local flow_skills=(
        "flow-discover.md"
        "flow-define.md"
        "flow-develop.md"
        "flow-deliver.md"
    )

    for skill in "${flow_skills[@]}"; do
        local skill_path="${PROJECT_ROOT}/.claude/skills/${skill}"

        if [[ ! -f "$skill_path" ]]; then
            log_fail "Skill $skill not found"
            return 1
        fi

        # Check for agent field
        if grep -q "^agent:" "$skill_path"; then
            log_pass "Skill $skill has agent field"
        else
            log_fail "Skill $skill missing agent field"
            return 1
        fi

        # Check for context field
        if grep -q "^context:" "$skill_path"; then
            log_pass "Skill $skill has context field"
        else
            log_info "Skill $skill missing context field (optional)"
        fi

        # Check for task_management field
        if grep -q "^task_management:" "$skill_path"; then
            log_pass "Skill $skill has task_management field"
        else
            log_info "Skill $skill missing task_management field (optional)"
        fi
    done
}

# ═══════════════════════════════════════════════════════════════════════════════
# Backward Compatibility Tests
# ═══════════════════════════════════════════════════════════════════════════════

test_backward_compatibility() {
    run_test "Backward compatibility checks"

    # Check that version detection doesn't break if Claude CLI is missing
    if grep -q "detect_claude_code_version.*2>/dev/null.*|| true" "$ALL_SRC"; then
        log_pass "Version detection has fallback for missing Claude CLI"
    else
        log_fail "Version detection missing fallback"
        return 1
    fi

    # Check that task management feature flag is declared
    if grep -q 'SUPPORTS_TASK_MANAGEMENT=' "$ALL_SRC"; then
        log_pass "Task management feature flag declared"
    else
        log_fail "Task management feature flag missing"
        return 1
    fi
}

test_existing_functionality() {
    run_test "Existing orchestrate.sh functions still work"

    local critical_functions=(
        "spawn_agent"
        "get_agent_command"
        "init_session"
    )

    for func in "${critical_functions[@]}"; do
        if grep -q "^${func}()\|^${func} ()" "$ALL_SRC"; then
            log_pass "Critical function $func still exists"
        else
            log_fail "Critical function $func missing or renamed"
            return 1
        fi
    done
}

# ═══════════════════════════════════════════════════════════════════════════════
# Main Test Execution
# ═══════════════════════════════════════════════════════════════════════════════

echo "=================================================="
echo "Claude Octopus v2.1.12+ Integration Test Suite"
echo "=================================================="
echo ""

log_info "Starting test suite..."
echo ""

# Unit Tests
echo "--- Unit Tests: Version Detection ---"
test_version_detection
test_feature_flags
echo ""

echo "--- Unit Tests: Fork Context ---"
test_fork_context_support
test_fork_markers
echo ""

echo "--- Unit Tests: Hook System ---"
test_hook_scripts_exist
test_hooks_json_updated
echo ""

# Integration Tests
echo "--- Integration Tests: Flow Skills ---"
test_flow_skill_frontmatter
echo ""

# Backward Compatibility Tests
echo "--- Backward Compatibility Tests ---"
test_backward_compatibility
test_existing_functionality
echo ""

# Summary
echo "=================================================="
echo "Test Results"
test_summary
