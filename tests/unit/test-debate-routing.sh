#!/bin/bash
# tests/unit/test-debate-routing.sh
# Tests debate command routing and dry-run behavior

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Debate Command Routing"

test_debate_command_exists() {
    test_case "Debate command pattern exists in orchestrate.sh"

    local orchestrate="$PROJECT_ROOT/scripts/orchestrate.sh"

    if grep -q "debate|deliberate|consensus)" "$orchestrate"; then
        test_pass
    else
        test_fail "Debate command pattern not found"
        return 1
    fi
}

test_debate_submodule_check() {
    test_case "Debate command checks for submodule"

    local orchestrate="$PROJECT_ROOT/scripts/orchestrate.sh"

    # Should check for .dependencies/claude-skills/skills/debate.md
    if grep -q ".dependencies/claude-skills/skills/debate.md" "$orchestrate"; then
        test_pass
    else
        test_fail "Missing submodule check in debate command"
        return 1
    fi
}

test_debate_sets_environment_vars() {
    test_case "Debate command sets integration environment variables"

    local orchestrate="$PROJECT_ROOT/scripts/orchestrate.sh"

    if grep -q "CLAUDE_OCTOPUS_DEBATE_MODE" "$orchestrate" && \
       grep -q "CLAUDE_CODE_SESSION" "$orchestrate"; then
        test_pass
    else
        test_fail "Missing environment variable setup"
        return 1
    fi
}

test_debate_shows_attribution() {
    test_case "Debate command output includes wolverin0 attribution"

    local orchestrate="$PROJECT_ROOT/scripts/orchestrate.sh"

    if grep -A 20 "debate|deliberate|consensus)" "$orchestrate" | \
       grep -q "wolverin0"; then
        test_pass
    else
        test_fail "Missing attribution in command output"
        return 1
    fi
}

test_debate_command_help() {
    test_case "Debate command provides usage examples"

    local orchestrate="$PROJECT_ROOT/scripts/orchestrate.sh"

    if grep -A 30 "debate|deliberate|consensus)" "$orchestrate" | \
       grep -q "Usage examples:"; then
        test_pass
    else
        test_fail "Missing usage examples"
        return 1
    fi
}

test_debate_dry_run() {
    test_case "Debate command works in dry-run mode"

    # Check if submodule is initialized
    if [[ ! -f "$PROJECT_ROOT/.dependencies/claude-skills/skills/debate.md" ]]; then
        test_skip "Submodule not initialized"
        return 0
    fi

    # Dry-run should not fail (it shows info, doesn't execute debate)
    local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" debate 2>&1 || true)

    if echo "$output" | grep -q "AI Debate Hub"; then
        test_pass
    else
        test_fail "Dry-run output missing expected content"
        return 1
    fi
}

test_deliberate_alias() {
    test_case "Deliberate alias routes to same handler"

    local orchestrate="$PROJECT_ROOT/scripts/orchestrate.sh"

    # Should have debate|deliberate|consensus in same case statement
    if grep -q "debate|deliberate|consensus)" "$orchestrate"; then
        test_pass
    else
        test_fail "Deliberate alias not found"
        return 1
    fi
}

test_consensus_alias() {
    test_case "Consensus alias routes to same handler"

    local orchestrate="$PROJECT_ROOT/scripts/orchestrate.sh"

    # Should have debate|deliberate|consensus in same case statement
    if grep -q "debate|deliberate|consensus)" "$orchestrate"; then
        test_pass
    else
        test_fail "Consensus alias not found"
        return 1
    fi
}

test_debate_styles_documented() {
    test_case "Debate styles are documented in command output"

    local orchestrate="$PROJECT_ROOT/scripts/orchestrate.sh"

    if grep -A 40 "debate|deliberate|consensus)" "$orchestrate" | \
       grep -q "quick" && \
       grep -A 40 "debate|deliberate|consensus)" "$orchestrate" | \
       grep -q "thorough" && \
       grep -A 40 "debate|deliberate|consensus)" "$orchestrate" | \
       grep -q "adversarial"; then
        test_pass
    else
        test_fail "Missing debate style documentation"
        return 1
    fi
}

# Run all tests
test_debate_command_exists
test_debate_submodule_check
test_debate_sets_environment_vars
test_debate_shows_attribution
test_debate_command_help
test_debate_dry_run
test_deliberate_alias
test_consensus_alias
test_debate_styles_documented

test_summary
