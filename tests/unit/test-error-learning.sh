#!/bin/bash
# tests/unit/test-error-learning.sh
# Tests error learning loop (v8.19.0)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Error Learning Loop"

test_record_error_function_exists() {
    test_case "record_error function exists in orchestrate.sh"

    if grep -q "record_error()" "$PROJECT_ROOT/scripts/orchestrate.sh"; then
        test_pass
    else
        test_fail "record_error function not found"
    fi
}

test_search_similar_errors_function_exists() {
    test_case "search_similar_errors function exists in orchestrate.sh"

    if grep -q "search_similar_errors()" "$PROJECT_ROOT/scripts/orchestrate.sh"; then
        test_pass
    else
        test_fail "search_similar_errors function not found"
    fi
}

test_flag_repeat_error_function_exists() {
    test_case "flag_repeat_error function exists in orchestrate.sh"

    if grep -q "flag_repeat_error()" "$PROJECT_ROOT/scripts/orchestrate.sh"; then
        test_pass
    else
        test_fail "flag_repeat_error function not found"
    fi
}

test_error_format() {
    test_case "Error format includes required fields"

    local func_body
    func_body=$(sed -n '/^record_error()/,/^}/p' "$PROJECT_ROOT/scripts/orchestrate.sh")

    if echo "$func_body" | grep -q "### ERROR |" && \
       echo "$func_body" | grep -q "Task:" && \
       echo "$func_body" | grep -q "Error:" && \
       echo "$func_body" | grep -q "Root Cause:" && \
       echo "$func_body" | grep -q "Prevention:"; then
        test_pass
    else
        test_fail "Error format missing required fields"
    fi
}

test_error_cap_100() {
    test_case "Error log capped at 100 entries"

    local func_body
    func_body=$(sed -n '/^record_error()/,/^}/p' "$PROJECT_ROOT/scripts/orchestrate.sh")

    if echo "$func_body" | grep -q "100"; then
        test_pass
    else
        test_fail "100 entry cap not found"
    fi
}

test_error_recording_in_spawn_agent() {
    test_case "record_error called in spawn_agent failure path"

    if grep -B 2 -A 2 "record_error.*spawn_agent" "$PROJECT_ROOT/scripts/orchestrate.sh" | grep -q "record_error"; then
        test_pass
    else
        test_fail "record_error not called in spawn_agent failure"
    fi
}

test_error_context_in_retries() {
    test_case "Error context injected into retry prompts"

    if grep -A 60 "retry_failed_subtasks()" "$PROJECT_ROOT/scripts/orchestrate.sh" | grep -q "search_similar_errors\|RETRY CONTEXT"; then
        test_pass
    else
        test_fail "Error context not injected into retries"
    fi
}

test_repeat_detection() {
    test_case "Repeat error detection triggers structured decision"

    local func_body
    func_body=$(sed -n '/^flag_repeat_error()/,/^}/p' "$PROJECT_ROOT/scripts/orchestrate.sh")

    if echo "$func_body" | grep -q "write_structured_decision" && echo "$func_body" | grep -q "ge 2"; then
        test_pass
    else
        test_fail "Repeat detection not properly implemented"
    fi
}

test_dry_run_with_error_learning() {
    test_case "Dry-run works with error learning code"

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
test_record_error_function_exists
test_search_similar_errors_function_exists
test_flag_repeat_error_function_exists
test_error_format
test_error_cap_100
test_error_recording_in_spawn_agent
test_error_context_in_retries
test_repeat_detection
test_dry_run_with_error_learning

test_summary
