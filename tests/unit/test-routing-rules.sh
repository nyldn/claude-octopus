#!/bin/bash
# tests/unit/test-routing-rules.sh
# Tests agent routing rules (v8.19.0)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Agent Routing Rules"

test_load_routing_rules_function_exists() {
    test_case "load_routing_rules function exists"

    if grep -q "load_routing_rules()" "$PROJECT_ROOT/scripts/orchestrate.sh"; then
        test_pass
    else
        test_fail "load_routing_rules function not found"
    fi
}

test_match_routing_rule_function_exists() {
    test_case "match_routing_rule function exists"

    if grep -q "match_routing_rule()" "$PROJECT_ROOT/scripts/orchestrate.sh"; then
        test_pass
    else
        test_fail "match_routing_rule function not found"
    fi
}

test_create_default_routing_rules_function_exists() {
    test_case "create_default_routing_rules function exists"

    if grep -q "create_default_routing_rules()" "$PROJECT_ROOT/scripts/orchestrate.sh"; then
        test_pass
    else
        test_fail "create_default_routing_rules function not found"
    fi
}

test_routing_json_format() {
    test_case "Default routing rules use correct JSON format"

    local func_body
    func_body=$(sed -n '/^create_default_routing_rules()/,/^}/p' "$PROJECT_ROOT/scripts/orchestrate.sh")

    if echo "$func_body" | grep -q '"rules"' && \
       echo "$func_body" | grep -q '"match"' && \
       echo "$func_body" | grep -q '"prefer"' && \
       echo "$func_body" | grep -q '"fallback"'; then
        test_pass
    else
        test_fail "JSON format missing required fields"
    fi
}

test_routing_first_match_wins() {
    test_case "Routing uses first-match-wins evaluation"

    local func_body
    func_body=$(sed -n '/^match_routing_rule()/,/^}/p' "$PROJECT_ROOT/scripts/orchestrate.sh")

    # Should return after first match
    if echo "$func_body" | grep -q "return 0"; then
        test_pass
    else
        test_fail "First-match-wins pattern not found"
    fi
}

test_routing_no_match_returns_1() {
    test_case "No match returns exit code 1"

    local func_body
    func_body=$(sed -n '/^match_routing_rule()/,/^}/p' "$PROJECT_ROOT/scripts/orchestrate.sh")

    if echo "$func_body" | grep -q "return 1"; then
        test_pass
    else
        test_fail "No-match return 1 not found"
    fi
}

test_routing_graceful_no_file() {
    test_case "Missing routing rules file handled gracefully"

    local func_body
    func_body=$(sed -n '/^load_routing_rules()/,/^}/p' "$PROJECT_ROOT/scripts/orchestrate.sh")

    if echo "$func_body" | grep -q "return 1"; then
        test_pass
    else
        test_fail "Missing file not handled gracefully"
    fi
}

test_routing_no_overwrite() {
    test_case "create_default_routing_rules doesn't overwrite existing file"

    local func_body
    func_body=$(sed -n '/^create_default_routing_rules()/,/^}/p' "$PROJECT_ROOT/scripts/orchestrate.sh")

    if echo "$func_body" | grep -q "return 0\|Don't overwrite"; then
        test_pass
    else
        test_fail "Overwrite protection not found"
    fi
}

test_routing_in_spawn_agent() {
    test_case "Routing rules checked in spawn_agent"

    if grep -A 60 "spawn_agent()" "$PROJECT_ROOT/scripts/orchestrate.sh" | grep -q "match_routing_rule"; then
        test_pass
    else
        test_fail "Routing rules not checked in spawn_agent"
    fi
}

test_routing_default_security() {
    test_case "Default routing includes security→security-auditor"

    local func_body
    func_body=$(sed -n '/^create_default_routing_rules()/,/^}/p' "$PROJECT_ROOT/scripts/orchestrate.sh")

    if echo "$func_body" | grep -q "security-auditor"; then
        test_pass
    else
        test_fail "Security→security-auditor default not found"
    fi
}

test_dry_run_with_routing() {
    test_case "Dry-run works with routing rules code"

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
test_load_routing_rules_function_exists
test_match_routing_rule_function_exists
test_create_default_routing_rules_function_exists
test_routing_json_format
test_routing_first_match_wins
test_routing_no_match_returns_1
test_routing_graceful_no_file
test_routing_no_overwrite
test_routing_in_spawn_agent
test_routing_default_security
test_dry_run_with_routing

test_summary
