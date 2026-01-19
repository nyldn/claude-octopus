#!/bin/bash
# tests/unit/test-knowledge-routing.sh
# Tests knowledge worker routing and intent detection (v6.0)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$SCRIPT_DIR/../helpers/mock-helpers.sh"

test_suite "Knowledge Worker Routing (v6.0)"

test_empathize_command() {
    test_case "empathize command executes in dry-run mode"

    local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" empathize -n "synthesize user interview findings" 2>&1)
    local exit_code=$?

    assert_success "$exit_code" "empathize should succeed in dry-run"
    if echo "$output" | grep -qi "empathize\|ux.*research"; then
        test_pass
    else
        test_fail "Should show empathize workflow indicator: $output"
    fi
}

test_advise_command() {
    test_case "advise command executes in dry-run mode"

    local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" advise -n "analyze market entry strategy" 2>&1)
    local exit_code=$?

    assert_success "$exit_code" "advise should succeed in dry-run"
    if echo "$output" | grep -qi "advise\|strategy\|consult"; then
        test_pass
    else
        test_fail "Should show advise workflow indicator: $output"
    fi
}

test_synthesize_command() {
    test_case "synthesize command executes in dry-run mode"

    local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" synthesize -n "literature review on machine learning" 2>&1)
    local exit_code=$?

    assert_success "$exit_code" "synthesize should succeed in dry-run"
    if echo "$output" | grep -qi "synthesize\|literature\|research"; then
        test_pass
    else
        test_fail "Should show synthesize workflow indicator: $output"
    fi
}

test_knowledge_toggle() {
    test_case "knowledge-toggle command works"

    local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" knowledge-toggle 2>&1)
    local exit_code=$?

    assert_success "$exit_code" "knowledge-toggle should succeed"
    if echo "$output" | grep -qi "knowledge.*mode\|on\|off"; then
        test_pass
    else
        test_fail "Should show mode toggle: $output"
    fi
}

test_intent_detection_ux_research() {
    test_case "Detects UX research intent correctly"

    local prompts=(
        "synthesize user interview findings"
        "create user personas from research"
        "journey map for onboarding flow"
        "analyze usability test results"
    )

    for prompt in "${prompts[@]}"; do
        local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" auto -n "$prompt" 2>&1)
        if echo "$output" | grep -qi "empathize\|ux.*research\|knowledge.*empathize"; then
            continue
        else
            test_fail "Should detect UX research intent for: $prompt"
            return 1
        fi
    done

    test_pass
}

test_intent_detection_strategy() {
    test_case "Detects strategy consulting intent correctly"

    local prompts=(
        "competitive analysis for our product"
        "SWOT analysis for market expansion"
        "business case for new feature"
        "market intelligence report"
    )

    for prompt in "${prompts[@]}"; do
        local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" auto -n "$prompt" 2>&1)
        if echo "$output" | grep -qi "advise\|strategy\|knowledge.*advise"; then
            continue
        else
            test_fail "Should detect strategy intent for: $prompt"
            return 1
        fi
    done

    test_pass
}

test_intent_detection_literature() {
    test_case "Detects literature review intent correctly"

    local prompts=(
        "literature review on distributed systems"
        "research synthesis on AI safety"
        "systematic review of caching strategies"
        "identify research gaps in authentication"
    )

    for prompt in "${prompts[@]}"; do
        local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" auto -n "$prompt" 2>&1)
        if echo "$output" | grep -qi "synthesize\|literature\|knowledge.*synthesize"; then
            continue
        else
            test_fail "Should detect literature review intent for: $prompt"
            return 1
        fi
    done

    test_pass
}

test_new_intent_choices() {
    test_case "New intent choices 11-13 map correctly"

    local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" help --full 2>&1)

    if echo "$output" | grep -qi "strategy.*consulting\|11"; then
        if echo "$output" | grep -qi "empathize\|advise\|synthesize"; then
            test_pass
        else
            test_fail "Should show knowledge worker commands in help"
        fi
    else
        test_fail "Should document new intent choices"
    fi
}

test_command_aliases() {
    test_case "Command aliases work (empathy, consult, lit-review)"

    local aliases=(
        "empathy:empathize"
        "ux-research:empathize"
        "consult:advise"
        "strategy:advise"
        "lit-review:synthesize"
        "synthesis:synthesize"
    )

    for alias_pair in "${aliases[@]}"; do
        local alias="${alias_pair%%:*}"
        local expected="${alias_pair##*:}"

        local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" "$alias" -n "test prompt" 2>&1)
        local exit_code=$?

        if [[ $exit_code -ne 0 ]]; then
            test_fail "Alias $alias should work (expected $expected)"
            return 1
        fi
    done

    test_pass
}

test_status_shows_mode() {
    test_case "status command shows Knowledge Work Mode"

    local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" status 2>&1)

    if echo "$output" | grep -qi "mode.*knowledge\|mode.*development\|knowledge-toggle"; then
        test_pass
    else
        test_fail "Status should show current mode: $output"
    fi
}

test_dev_command() {
    test_case "dev command switches to Dev Work mode"

    local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" dev 2>&1)
    local exit_code=$?

    assert_success "$exit_code" "dev command should succeed"
    if echo "$output" | grep -qi "dev.*work.*mode\|development.*mode"; then
        test_pass
    else
        test_fail "Should show Dev Work mode activation: $output"
    fi
}

test_mode_symmetry() {
    test_case "/co:dev and /co:km off should be equivalent"

    # First, enable knowledge mode
    "$PROJECT_ROOT/scripts/orchestrate.sh" knowledge-mode on >/dev/null 2>&1

    # Test dev command output
    local dev_output=$("$PROJECT_ROOT/scripts/orchestrate.sh" dev 2>&1)

    # Re-enable knowledge mode
    "$PROJECT_ROOT/scripts/orchestrate.sh" knowledge-mode on >/dev/null 2>&1

    # Test km off output
    local km_off_output=$("$PROJECT_ROOT/scripts/orchestrate.sh" knowledge-mode off 2>&1)

    # Both should indicate switching to Dev mode
    if echo "$dev_output" | grep -qi "dev.*work.*mode\|development.*mode"; then
        if echo "$km_off_output" | grep -qi "dev.*work.*mode\|development.*mode"; then
            test_pass
        else
            test_fail "/co:km off should show Dev mode: $km_off_output"
        fi
    else
        test_fail "/co:dev should show Dev mode: $dev_output"
    fi
}

# Run all tests
test_empathize_command
test_advise_command
test_synthesize_command
test_knowledge_toggle
test_intent_detection_ux_research
test_intent_detection_strategy
test_intent_detection_literature
test_new_intent_choices
test_command_aliases
test_status_shows_mode
test_dev_command
test_mode_symmetry

test_summary
