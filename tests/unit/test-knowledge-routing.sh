#!/bin/bash
# tests/unit/test-knowledge-routing.sh
# Tests knowledge worker routing and intent detection (v6.0)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$SCRIPT_DIR/../helpers/mock-helpers.sh"
source "$PROJECT_ROOT/scripts/lib/routing.sh"

export HOME="$TEST_TMP_DIR/home"
export WORKSPACE_DIR="$TEST_TMP_DIR/workspace"
export OCTOPUS_SKIP_PROVIDER_PROBES=true
mkdir -p "$HOME" "$WORKSPACE_DIR"

test_suite "Knowledge Worker Routing (v6.0)"

output_matches() {
    local output="$1"
    local pattern="$2"
    grep -qi -- "$pattern" <<< "$output"
}

test_empathize_command() {
    test_case "empathize command executes in dry-run mode"

    local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" -n empathize "synthesize user interview findings" 2>&1)
    local exit_code=$?

    assert_success "$exit_code" "empathize should succeed in dry-run"
    if output_matches "$output" "empathize\|ux.*research"; then
        test_pass
    else
        test_fail "Should show empathize workflow indicator: $output"
    fi
}

test_advise_command() {
    test_case "advise command executes in dry-run mode"

    local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" -n advise "analyze market entry strategy" 2>&1)
    local exit_code=$?

    assert_success "$exit_code" "advise should succeed in dry-run"
    if output_matches "$output" "advise\|strategy\|consult"; then
        test_pass
    else
        test_fail "Should show advise workflow indicator: $output"
    fi
}

test_synthesize_command() {
    test_case "synthesize command executes in dry-run mode"

    local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" -n synthesize "literature review on machine learning" 2>&1)
    local exit_code=$?

    assert_success "$exit_code" "synthesize should succeed in dry-run"
    if output_matches "$output" "synthesize\|literature\|research"; then
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
    if output_matches "$output" "knowledge.*mode\|on\|off"; then
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
        if [[ "$(classify_task "$prompt")" != "knowledge-empathize" ]]; then
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
        if [[ "$(classify_task "$prompt")" != "knowledge-advise" ]]; then
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
        if [[ "$(classify_task "$prompt")" != "knowledge-synthesize" ]]; then
            test_fail "Should detect literature review intent for: $prompt"
            return 1
        fi
    done

    test_pass
}

test_new_intent_choices() {
    test_case "New intent choices 11-13 map correctly"

    local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" help --full 2>&1)

    if output_matches "$output" "strategy.*consulting\|11"; then
        if output_matches "$output" "empathize\|advise\|synthesize"; then
            test_pass
        else
            test_fail "Should show knowledge worker commands in help"
        fi
    else
        test_fail "Should document new intent choices"
    fi
}

test_command_aliases() {
    test_case "Knowledge command aliases share their canonical dispatch arms"

    if grep -Fq '    empathize|empathy|ux-research)' "$PROJECT_ROOT/scripts/orchestrate.sh" &&
       grep -Fq '    advise|consult|strategy)' "$PROJECT_ROOT/scripts/orchestrate.sh" &&
       grep -Fq '    synthesize|synthesis|lit-review)' "$PROJECT_ROOT/scripts/orchestrate.sh"; then
        test_pass
    else
        test_fail "A knowledge command alias is detached from its canonical dispatch arm"
    fi
}

test_status_shows_mode() {
    test_case "status command shows current mode"

    local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" status 2>&1)

    # Status output shows "Mode:" line with one of: Development, Knowledge, Auto-Detect
    if output_matches "$output" "Mode:.*Development\|Mode:.*Knowledge\|Mode:.*Auto-Detect"; then
        test_pass
    else
        test_fail "Status should show current mode"
    fi
}

test_dev_command() {
    test_case "dev command activates Dev mode"

    local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" dev 2>&1)
    local exit_code=$?

    assert_success "$exit_code" "dev command should succeed"
    if output_matches "$output" "Dev Mode"; then
        test_pass
    else
        test_fail "Should show Dev Mode activation"
    fi
}

test_mode_symmetry() {
    test_case "/octo:dev and /octo:km off both result in Dev mode"

    # First, enable knowledge mode
    "$PROJECT_ROOT/scripts/orchestrate.sh" knowledge-mode on >/dev/null 2>&1

    # Test dev command output
    local dev_output=$("$PROJECT_ROOT/scripts/orchestrate.sh" dev 2>&1)

    # Re-enable knowledge mode
    "$PROJECT_ROOT/scripts/orchestrate.sh" knowledge-mode on >/dev/null 2>&1

    # Test km off output
    local km_off_output=$("$PROJECT_ROOT/scripts/orchestrate.sh" knowledge-mode off 2>&1)

    # Both should indicate Dev mode
    if output_matches "$dev_output" "Dev Mode"; then
        if output_matches "$km_off_output" "Dev Mode"; then
            test_pass
        else
            test_fail "/octo:km off should show Dev Mode: $km_off_output"
        fi
    else
        test_fail "/octo:dev should show Dev Mode: $dev_output"
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
