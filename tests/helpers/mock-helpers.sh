#!/bin/bash
# tests/helpers/mock-helpers.sh
# Mock infrastructure for Claude Octopus CLI testing
# Provides utilities for mocking codex and gemini responses

set -euo pipefail

# Source test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-framework.sh"

#==============================================================================
# Mock Configuration
#==============================================================================

MOCK_RESPONSE_DIR="${MOCK_RESPONSE_DIR:-$TEST_TMP_DIR/mock-responses}"
mkdir -p "$MOCK_RESPONSE_DIR"

#==============================================================================
# Basic CLI Mocking
#==============================================================================

mock_codex() {
    local response_file="$1"
    local exit_code="${2:-0}"

    mock_command "codex" "
        if [[ -f '$response_file' ]]; then
            cat '$response_file'
            exit $exit_code
        else
            echo 'Mock response file not found: $response_file' >&2
            exit 1
        fi
    "
}

mock_gemini() {
    local response_file="$1"
    local exit_code="${2:-0}"

    mock_command "gemini" "
        if [[ -f '$response_file' ]]; then
            cat '$response_file'
            exit $exit_code
        else
            echo 'Mock response file not found: $response_file' >&2
            exit 1
        fi
    "
}

#==============================================================================
# Response File Creation
#==============================================================================

create_mock_response() {
    local agent_name="$1"
    local content="$2"
    local filename="${3:-response_${agent_name}_$$.txt}"

    local response_file="$MOCK_RESPONSE_DIR/$filename"
    echo "$content" > "$response_file"
    echo "$response_file"
}

create_success_response() {
    local agent_name="$1"
    local output="$2"

    create_mock_response "$agent_name" "$output"
}

create_error_response() {
    local agent_name="$1"
    local error_message="$2"

    create_mock_response "$agent_name" "ERROR: $error_message"
}

#==============================================================================
# Quality Score Mocking
#==============================================================================

mock_with_quality() {
    local agent="$1"
    local quality_score="$2"  # 0-100
    local response="$3"

    # Create response with embedded quality marker
    local response_with_quality="$response

---QUALITY_SCORE: $quality_score---"

    local response_file=$(create_mock_response "$agent" "$response_with_quality")

    if [[ "$agent" == "codex" ]]; then
        mock_codex "$response_file" 0
    elif [[ "$agent" == "gemini" ]]; then
        mock_gemini "$response_file" 0
    else
        echo "ERROR: Unknown agent: $agent" >&2
        return 1
    fi
}

extract_quality_score() {
    local output="$1"

    if [[ "$output" =~ ---QUALITY_SCORE:\ ([0-9]+)--- ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "0"
    fi
}

#==============================================================================
# Timeout and Error Simulation
#==============================================================================

mock_timeout() {
    local agent="$1"
    local delay="${2:-10}"

    mock_command "$agent" "
        sleep $delay
        echo 'ERROR: Request timed out' >&2
        exit 124
    "
}

mock_rate_limit() {
    local agent="$1"

    local error_response="ERROR: API rate limit exceeded (429)
Please wait before retrying
Rate limit will reset in 60 seconds"

    local response_file=$(create_error_response "$agent" "$error_response")

    mock_command "$agent" "
        cat '$response_file' >&2
        exit 2
    "
}

mock_api_error() {
    local agent="$1"
    local error_code="${2:-500}"
    local error_message="${3:-Internal Server Error}"

    local response_file=$(create_error_response "$agent" "HTTP $error_code: $error_message")

    mock_command "$agent" "
        cat '$response_file' >&2
        exit 1
    "
}

mock_auth_error() {
    local agent="$1"

    local error_response="ERROR: Authentication failed
API key not found or invalid
Please check your configuration"

    local response_file=$(create_error_response "$agent" "$error_response")

    mock_command "$agent" "
        cat '$response_file' >&2
        exit 3
    "
}

#==============================================================================
# Conditional Mocking (Stateful Behavior)
#==============================================================================

mock_with_retry() {
    local agent="$1"
    local fail_times="$2"
    local success_response="$3"
    local error_response="${4:-ERROR: Temporary failure}"

    local state_file="$TEST_TMP_DIR/mock_${agent}_retry_state"
    echo "0" > "$state_file"

    local success_file=$(create_success_response "$agent" "$success_response")
    local error_file=$(create_error_response "$agent" "$error_response")

    mock_command "$agent" "
        count=\$(cat '$state_file')
        count=\$((count + 1))
        echo \"\$count\" > '$state_file'

        if [[ \"\$count\" -le $fail_times ]]; then
            cat '$error_file' >&2
            exit 1
        else
            cat '$success_file'
            exit 0
        fi
    "
}

mock_alternating() {
    local agent1="$1"
    local agent2="$2"
    local response1="$3"
    local response2="$4"

    local response_file1=$(create_success_response "$agent1" "$response1")
    local response_file2=$(create_success_response "$agent2" "$response2")

    mock_codex "$response_file1" 0
    mock_gemini "$response_file2" 0
}

#==============================================================================
# Multi-Agent Mocking (for Crossfire workflows)
#==============================================================================

mock_grapple_workflow() {
    local round1_response="$1"
    local round2_response="$2"
    local round3_response="$3"

    local state_file="$TEST_TMP_DIR/mock_grapple_round"
    echo "0" > "$state_file"

    local r1=$(create_mock_response "grapple" "$round1_response")
    local r2=$(create_mock_response "grapple" "$round2_response")
    local r3=$(create_mock_response "grapple" "$round3_response")

    # Mock both codex and gemini to simulate multi-agent debate
    for agent in codex gemini; do
        mock_command "$agent" "
            round=\$(cat '$state_file')
            round=\$((round + 1))
            echo \"\$round\" > '$state_file'

            case \$round in
                1) cat '$r1' ;;
                2) cat '$r2' ;;
                3) cat '$r3' ;;
                *) cat '$r3' ;;
            esac
            exit 0
        "
    done
}

mock_squeeze_workflow() {
    local blue_team_response="$1"
    local red_team_response="$2"
    local remediation_response="$3"
    local validation_response="$4"

    local state_file="$TEST_TMP_DIR/mock_squeeze_phase"
    echo "0" > "$state_file"

    local blue=$(create_mock_response "squeeze" "$blue_team_response")
    local red=$(create_mock_response "squeeze" "$red_team_response")
    local remediate=$(create_mock_response "squeeze" "$remediation_response")
    local validate=$(create_mock_response "squeeze" "$validation_response")

    for agent in codex gemini; do
        mock_command "$agent" "
            phase=\$(cat '$state_file')
            phase=\$((phase + 1))
            echo \"\$phase\" > '$state_file'

            case \$phase in
                1) cat '$blue' ;;
                2) cat '$red' ;;
                3) cat '$remediate' ;;
                4) cat '$validate' ;;
                *) cat '$validate' ;;
            esac
            exit 0
        "
    done
}

#==============================================================================
# Context and Session Mocking
#==============================================================================

mock_with_context() {
    local agent="$1"
    local previous_context="$2"
    local response="$3"

    # Create response that references previous context
    local contextual_response="Based on previous analysis: $previous_context

$response"

    local response_file=$(create_mock_response "$agent" "$contextual_response")

    if [[ "$agent" == "codex" ]]; then
        mock_codex "$response_file" 0
    else
        mock_gemini "$response_file" 0
    fi
}

create_mock_workspace() {
    local workspace_dir="$TEST_TMP_DIR/workspace"
    mkdir -p "$workspace_dir"

    # Create typical workspace structure
    mkdir -p "$workspace_dir/phase1-probe"
    mkdir -p "$workspace_dir/phase2-grasp"
    mkdir -p "$workspace_dir/phase3-tangle"
    mkdir -p "$workspace_dir/phase4-ink"

    echo "$workspace_dir"
}

add_context_to_workspace() {
    local workspace="$1"
    local phase="$2"
    local content="$3"

    local context_file="$workspace/phase${phase}-*/context.md"
    mkdir -p "$(dirname "$context_file")"
    echo "$content" > "$context_file"
}

#==============================================================================
# Provider Detection Mocking
#==============================================================================

mock_provider_available() {
    local provider="$1"
    local available="${2:-true}"

    if [[ "$available" == "true" ]]; then
        mock_command "$provider" "echo 'Provider available'; exit 0"
    else
        mock_command "$provider" "echo 'Provider not available' >&2; exit 127"
    fi
}

mock_multiple_providers() {
    local codex_available="${1:-true}"
    local gemini_available="${2:-true}"

    mock_provider_available "codex" "$codex_available"
    mock_provider_available "gemini" "$gemini_available"
}

#==============================================================================
# Assertion Helpers for Mock Verification
#==============================================================================

assert_agent_called_with_prompt() {
    local agent="$1"
    local expected_prompt_substring="$2"

    local calls_log="$TEST_TMP_DIR/mock_${agent}_calls.log"

    if [[ ! -f "$calls_log" ]]; then
        test_fail "Agent $agent was never called"
        return 1
    fi

    if grep -q "$expected_prompt_substring" "$calls_log"; then
        return 0
    else
        test_fail "Agent $agent not called with expected prompt substring: $expected_prompt_substring"
        return 1
    fi
}

assert_agents_called_in_order() {
    local agent1="$1"
    local agent2="$2"

    local calls1="$TEST_TMP_DIR/mock_${agent1}_calls.log"
    local calls2="$TEST_TMP_DIR/mock_${agent2}_calls.log"

    if [[ ! -f "$calls1" || ! -f "$calls2" ]]; then
        test_fail "One or both agents were not called"
        return 1
    fi

    # Get timestamps
    local time1=$(head -n1 "$calls1" | cut -d' ' -f1)
    local time2=$(head -n1 "$calls2" | cut -d' ' -f1)

    if [[ "$time1" -lt "$time2" ]]; then
        return 0
    else
        test_fail "Agents not called in expected order: $agent1 should be before $agent2"
        return 1
    fi
}

assert_parallel_execution() {
    local agent1="$1"
    local agent2="$2"
    local max_time_diff="${3:-2}"  # seconds

    local calls1="$TEST_TMP_DIR/mock_${agent1}_calls.log"
    local calls2="$TEST_TMP_DIR/mock_${agent2}_calls.log"

    if [[ ! -f "$calls1" || ! -f "$calls2" ]]; then
        test_fail "One or both agents were not called"
        return 1
    fi

    local time1=$(head -n1 "$calls1" | cut -d' ' -f1)
    local time2=$(head -n1 "$calls2" | cut -d' ' -f1)
    local time_diff=$((time2 - time1))
    time_diff=${time_diff#-}  # abs value

    if [[ "$time_diff" -le "$max_time_diff" ]]; then
        return 0
    else
        test_fail "Agents not executed in parallel (time diff: ${time_diff}s > ${max_time_diff}s)"
        return 1
    fi
}

#==============================================================================
# Fixture Generation Helpers
#==============================================================================

generate_probe_response() {
    local topic="$1"

    cat <<EOF
# Probe Analysis: $topic

## Key Questions
1. What are the core requirements?
2. What are the constraints?
3. What are the success criteria?

## Research Findings
- Finding 1: Important aspect of $topic
- Finding 2: Critical constraint to consider
- Finding 3: Success metric to track

## Recommendations
Proceed with grasp phase to define detailed requirements.
EOF
}

generate_grasp_response() {
    local requirements="$1"

    cat <<EOF
# Grasp: Detailed Requirements

## Functional Requirements
1. Requirement 1: $requirements
2. Requirement 2: Additional functionality
3. Requirement 3: Edge case handling

## Non-Functional Requirements
- Performance: < 100ms response time
- Scalability: Handle 1000 concurrent users
- Security: Authentication required

## Acceptance Criteria
- [ ] All functional requirements met
- [ ] Non-functional requirements validated
- [ ] Edge cases handled
EOF
}

generate_tangle_response() {
    local quality="${1:-95}"

    cat <<EOF
# Tangle: Implementation

## Solution Architecture
- Component A: Handles core logic
- Component B: Manages data
- Component C: Provides interface

## Implementation Details
\`\`\`python
def solution():
    # Implementation here
    return "Complete"
\`\`\`

## Quality Assessment
Quality Score: $quality/100
- Code clarity: Excellent
- Test coverage: Comprehensive
- Performance: Optimal

---QUALITY_SCORE: $quality---
EOF
}

generate_ink_response() {
    local refinements="$1"

    cat <<EOF
# Ink: Refinement and Optimization

## Refinements Applied
1. $refinements
2. Performance optimization
3. Error handling improvement

## Final Implementation
\`\`\`python
def optimized_solution():
    # Refined implementation
    return "Optimized"
\`\`\`

## Validation
All tests passing. Ready for deployment.
EOF
}

#==============================================================================
# Export Functions
#==============================================================================

export -f mock_codex mock_gemini
export -f create_mock_response create_success_response create_error_response
export -f mock_with_quality extract_quality_score
export -f mock_timeout mock_rate_limit mock_api_error mock_auth_error
export -f mock_with_retry mock_alternating
export -f mock_grapple_workflow mock_squeeze_workflow
export -f mock_with_context create_mock_workspace add_context_to_workspace
export -f mock_provider_available mock_multiple_providers
export -f assert_agent_called_with_prompt assert_agents_called_in_order assert_parallel_execution
export -f generate_probe_response generate_grasp_response generate_tangle_response generate_ink_response
