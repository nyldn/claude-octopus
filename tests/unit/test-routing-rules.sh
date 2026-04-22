#!/bin/bash
# tests/unit/test-routing-rules.sh
# Tests agent routing rules (v8.19.0)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Agent Routing Rules"

# Combined search target (functions decomposed to lib/ in v9.7.7+)
ALL_SRC=$(mktemp)
cat "$PROJECT_ROOT/scripts/orchestrate.sh" "$PROJECT_ROOT/scripts/lib/"*.sh > "$ALL_SRC" 2>/dev/null

test_load_routing_rules_function_exists() {
    test_case "load_routing_rules function exists"

    if grep -q "load_routing_rules()" "$ALL_SRC"; then
        test_pass
    else
        test_fail "load_routing_rules function not found"
    fi
}

test_match_routing_rule_function_exists() {
    test_case "match_routing_rule function exists"

    if grep -q "match_routing_rule()" "$ALL_SRC"; then
        test_pass
    else
        test_fail "match_routing_rule function not found"
    fi
}

test_routing_first_match_wins() {
    test_case "Routing uses first-match-wins evaluation"

    local func_body
    func_body=$(sed -n '/^match_routing_rule()/,/^}/p' "$ALL_SRC")

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
    func_body=$(sed -n '/^match_routing_rule()/,/^}/p' "$ALL_SRC")

    if echo "$func_body" | grep -q "return 1"; then
        test_pass
    else
        test_fail "No-match return 1 not found"
    fi
}

test_routing_graceful_no_file() {
    test_case "Missing routing rules file handled gracefully"

    local func_body
    func_body=$(sed -n '/^load_routing_rules()/,/^}/p' "$ALL_SRC")

    if echo "$func_body" | grep -q "return 1"; then
        test_pass
    else
        test_fail "Missing file not handled gracefully"
    fi
}

test_routing_in_spawn_agent() {
    test_case "Routing rules checked in spawn_agent"

    if grep -A 60 "spawn_agent()" "$ALL_SRC" | grep -q "match_routing_rule"; then
        test_pass
    else
        test_fail "Routing rules not checked in spawn_agent"
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
test_routing_first_match_wins
test_routing_no_match_returns_1
test_routing_graceful_no_file
test_routing_in_spawn_agent
test_dry_run_with_routing

rm -f "$ALL_SRC"
test_summary
