#!/bin/bash
# tests/unit/test-response-mode.sh
# Tests response mode auto-tuning (v8.18.0)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Response Mode Auto-Tuning"

# Define function inline for unit testing
OCTOPUS_RESPONSE_MODE="auto"

detect_response_mode() {
    local prompt="$1"
    local task_type="${2:-}"
    local prompt_lower
    prompt_lower=$(echo "$prompt" | tr '[:upper:]' '[:lower:]')

    if [[ "$OCTOPUS_RESPONSE_MODE" != "auto" ]]; then
        echo "$OCTOPUS_RESPONSE_MODE"
        return
    fi

    if echo "$prompt_lower" | grep -qwE "quick|fast|simple|brief|short"; then
        echo "direct"
        return
    fi
    if echo "$prompt_lower" | grep -qwE "thorough|comprehensive|complete|detailed|in-depth|exhaustive"; then
        echo "full"
        return
    fi

    case "${task_type}" in
        crossfire-*)
            echo "full"
            return
            ;;
        image-*)
            echo "lightweight"
            return
            ;;
        diamond-*)
            echo "standard"
            return
            ;;
    esac

    local word_count
    word_count=$(echo "$prompt" | wc -w | tr -d ' ')

    if [[ $word_count -lt 10 ]]; then
        echo "direct"
        return
    fi
    if [[ $word_count -gt 80 ]]; then
        echo "full"
        return
    fi

    local tech_score=0
    local tech_keywords="api database schema migration authentication authorization security performance optimization architecture microservice docker kubernetes terraform infrastructure pipeline deployment integration webhook endpoint middleware"

    for keyword in $tech_keywords; do
        if echo "$prompt_lower" | grep -qw "$keyword"; then
            ((tech_score++)) || true
        fi
    done

    if [[ $tech_score -ge 3 ]]; then
        echo "full"
    elif [[ $tech_score -ge 1 ]]; then
        echo "standard"
    else
        echo "standard"
    fi
}

# ── Tests ──

test_quick_signal() {
    test_case "User signal 'quick' returns direct mode"

    local mode
    mode=$(detect_response_mode "quick review of this file")

    if [[ "$mode" == "direct" ]]; then
        test_pass
    else
        test_fail "Expected 'direct', got '$mode'"
    fi
}

test_fast_signal() {
    test_case "User signal 'fast' returns direct mode"

    local mode
    mode=$(detect_response_mode "fast check on the API endpoint")

    if [[ "$mode" == "direct" ]]; then
        test_pass
    else
        test_fail "Expected 'direct', got '$mode'"
    fi
}

test_thorough_signal() {
    test_case "User signal 'thorough' returns full mode"

    local mode
    mode=$(detect_response_mode "thorough analysis of the authentication system")

    if [[ "$mode" == "full" ]]; then
        test_pass
    else
        test_fail "Expected 'full', got '$mode'"
    fi
}

test_comprehensive_signal() {
    test_case "User signal 'comprehensive' returns full mode"

    local mode
    mode=$(detect_response_mode "comprehensive review of all security measures")

    if [[ "$mode" == "full" ]]; then
        test_pass
    else
        test_fail "Expected 'full', got '$mode'"
    fi
}

test_short_prompt_direct() {
    test_case "Short prompt (<10 words) returns direct mode"

    local mode
    mode=$(detect_response_mode "fix the bug")

    if [[ "$mode" == "direct" ]]; then
        test_pass
    else
        test_fail "Expected 'direct', got '$mode'"
    fi
}

test_long_prompt_full() {
    test_case "Long prompt (>80 words) returns full mode"

    # Generate a prompt with > 80 words
    local long_prompt="Please analyze the following system architecture and provide recommendations for improving the performance scalability and reliability of the distributed microservices platform including the API gateway service mesh configuration database sharding strategy cache invalidation approach message queue topology load balancing algorithm circuit breaker patterns rate limiting implementation retry policies timeout configurations health check endpoints monitoring dashboards alerting rules logging aggregation trace sampling strategies deployment pipeline optimizations blue green deployment canary release progressive rollout feature flag management configuration management secrets rotation certificate renewal DNS failover CDN configuration and edge computing placement strategy for our multi-region deployment"

    local mode
    mode=$(detect_response_mode "$long_prompt")

    if [[ "$mode" == "full" ]]; then
        test_pass
    else
        test_fail "Expected 'full', got '$mode'"
    fi
}

test_crossfire_task_type() {
    test_case "Task type crossfire-* returns full mode"

    local mode
    mode=$(detect_response_mode "some task" "crossfire-debate")

    if [[ "$mode" == "full" ]]; then
        test_pass
    else
        test_fail "Expected 'full', got '$mode'"
    fi
}

test_image_task_type() {
    test_case "Task type image-* returns lightweight mode"

    local mode
    mode=$(detect_response_mode "analyze this screenshot" "image-analysis")

    if [[ "$mode" == "lightweight" ]]; then
        test_pass
    else
        test_fail "Expected 'lightweight', got '$mode'"
    fi
}

test_env_var_override() {
    test_case "OCTOPUS_RESPONSE_MODE env var overrides auto-detection"

    local saved="$OCTOPUS_RESPONSE_MODE"
    OCTOPUS_RESPONSE_MODE="full"

    local mode
    mode=$(detect_response_mode "quick fix")

    OCTOPUS_RESPONSE_MODE="$saved"

    if [[ "$mode" == "full" ]]; then
        test_pass
    else
        test_fail "Expected 'full' (override), got '$mode'"
    fi
}

test_tech_keywords_standard() {
    test_case "Technical keyword triggers standard or full mode"

    local mode
    mode=$(detect_response_mode "review the database schema for the API endpoint and check the security configuration")

    if [[ "$mode" == "standard" || "$mode" == "full" ]]; then
        test_pass
    else
        test_fail "Expected 'standard' or 'full', got '$mode'"
    fi
}

test_generic_prompt_standard() {
    test_case "Generic medium-length prompt returns standard"

    local mode
    mode=$(detect_response_mode "please look at the login page and tell me what you think about the design choices and user experience flow")

    if [[ "$mode" == "standard" ]]; then
        test_pass
    else
        test_fail "Expected 'standard', got '$mode'"
    fi
}

test_dry_run_no_crash() {
    test_case "Dry-run probe works with response mode code"

    local output
    output=$("$PROJECT_ROOT/scripts/orchestrate.sh" -n probe "test" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        test_pass
    else
        test_fail "Dry-run failed: $exit_code"
    fi
}

# Run all tests
test_quick_signal
test_fast_signal
test_thorough_signal
test_comprehensive_signal
test_short_prompt_direct
test_long_prompt_full
test_crossfire_task_type
test_image_task_type
test_env_var_override
test_tech_keywords_standard
test_generic_prompt_standard
test_dry_run_no_crash

test_summary
