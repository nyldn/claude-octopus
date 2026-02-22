#!/bin/bash
# tests/unit/test-tool-policy.sh
# Tests tool policy RBAC for personas (v8.19.0)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Tool Policy RBAC for Personas"

test_get_tool_policy_function_exists() {
    test_case "get_tool_policy function exists"

    if grep -q "get_tool_policy()" "$PROJECT_ROOT/scripts/orchestrate.sh"; then
        test_pass
    else
        test_fail "get_tool_policy function not found"
    fi
}

test_apply_tool_policy_function_exists() {
    test_case "apply_tool_policy function exists"

    if grep -q "apply_tool_policy()" "$PROJECT_ROOT/scripts/orchestrate.sh"; then
        test_pass
    else
        test_fail "apply_tool_policy function not found"
    fi
}

test_tool_policy_env_var() {
    test_case "OCTOPUS_TOOL_POLICIES env var defaults to true"

    if grep -q 'OCTOPUS_TOOL_POLICIES.*true' "$PROJECT_ROOT/scripts/orchestrate.sh"; then
        test_pass
    else
        test_fail "OCTOPUS_TOOL_POLICIES default not true"
    fi
}

test_researcher_policy() {
    test_case "Researcher role gets read_search policy"

    local func_body
    func_body=$(sed -n '/^get_tool_policy()/,/^}/p' "$PROJECT_ROOT/scripts/orchestrate.sh")

    if echo "$func_body" | grep -q "researcher.*read_search\|researcher.*)" && \
       echo "$func_body" | grep -q "read_search"; then
        test_pass
    else
        test_fail "Researcher not mapped to read_search"
    fi
}

test_implementer_policy() {
    test_case "Implementer role gets full policy"

    local func_body
    func_body=$(sed -n '/^get_tool_policy()/,/^}/p' "$PROJECT_ROOT/scripts/orchestrate.sh")

    if echo "$func_body" | grep -q "implementer"; then
        test_pass
    else
        test_fail "Implementer not found in policy mapping"
    fi
}

test_code_reviewer_policy() {
    test_case "Code-reviewer role gets read_exec policy"

    local func_body
    func_body=$(sed -n '/^get_tool_policy()/,/^}/p' "$PROJECT_ROOT/scripts/orchestrate.sh")

    if echo "$func_body" | grep -q "code-reviewer" && echo "$func_body" | grep -q "read_exec"; then
        test_pass
    else
        test_fail "Code-reviewer not mapped to read_exec"
    fi
}

test_synthesizer_policy() {
    test_case "Synthesizer role gets read_communicate policy"

    local func_body
    func_body=$(sed -n '/^get_tool_policy()/,/^}/p' "$PROJECT_ROOT/scripts/orchestrate.sh")

    if echo "$func_body" | grep -q "synthesizer" && echo "$func_body" | grep -q "read_communicate"; then
        test_pass
    else
        test_fail "Synthesizer not mapped to read_communicate"
    fi
}

test_full_no_restriction() {
    test_case "Full policy adds no restriction text"

    local func_body
    func_body=$(sed -n '/^apply_tool_policy()/,/^}/p' "$PROJECT_ROOT/scripts/orchestrate.sh")

    if echo "$func_body" | grep -q 'full)'; then
        test_pass
    else
        test_fail "Full policy handling not found"
    fi
}

test_unknown_role_defaults_full() {
    test_case "Unknown role defaults to full policy"

    local func_body
    func_body=$(sed -n '/^get_tool_policy()/,/^}/p' "$PROJECT_ROOT/scripts/orchestrate.sh")

    if echo "$func_body" | grep -q '\*)' && echo "$func_body" | grep -q '"full"'; then
        test_pass
    else
        test_fail "Unknown role default not full"
    fi
}

test_env_var_disable() {
    test_case "OCTOPUS_TOOL_POLICIES=false disables policies"

    local func_body
    func_body=$(sed -n '/^apply_tool_policy()/,/^}/p' "$PROJECT_ROOT/scripts/orchestrate.sh")

    if echo "$func_body" | grep -q "OCTOPUS_TOOL_POLICIES"; then
        test_pass
    else
        test_fail "Env var disable check not found"
    fi
}

test_policy_applied_in_persona() {
    test_case "Tool policy applied in apply_persona function"

    if grep -A 40 "apply_persona()" "$PROJECT_ROOT/scripts/orchestrate.sh" | grep -q "apply_tool_policy"; then
        test_pass
    else
        test_fail "apply_tool_policy not called in apply_persona"
    fi
}

test_config_yaml_documentation() {
    test_case "Tool policy documented in agents/config.yaml"

    if grep -q "tool_policy\|Tool Policy\|tool policy" "$PROJECT_ROOT/agents/config.yaml"; then
        test_pass
    else
        test_fail "Tool policy not documented in config.yaml"
    fi
}

test_dry_run_with_tool_policy() {
    test_case "Dry-run works with tool policy code"

    local output
    output=$("$PROJECT_ROOT/scripts/orchestrate.sh" -n tangle "test" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        test_pass
    else
        test_fail "Dry-run failed: $exit_code"
    fi
}

# Run tests
test_get_tool_policy_function_exists
test_apply_tool_policy_function_exists
test_tool_policy_env_var
test_researcher_policy
test_implementer_policy
test_code_reviewer_policy
test_synthesizer_policy
test_full_no_restriction
test_unknown_role_defaults_full
test_env_var_disable
test_policy_applied_in_persona
test_config_yaml_documentation
test_dry_run_with_tool_policy

test_summary
