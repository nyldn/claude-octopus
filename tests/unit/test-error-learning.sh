#!/bin/bash
# tests/unit/test-error-learning.sh
# Tests error learning loop (v8.19.0)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Error Learning Loop"

# Combined search target (functions decomposed to lib/ in v9.7.7+)
ALL_SRC=$(mktemp)
cat "$PROJECT_ROOT/scripts/orchestrate.sh" "$PROJECT_ROOT/scripts/lib/"*.sh > "$ALL_SRC" 2>/dev/null

test_record_error_function_exists() {
    test_case "record_error function exists"

    if grep -q "record_error()" "$ALL_SRC"; then
        test_pass
    else
        test_fail "record_error function not found"
    fi
}

test_search_similar_errors_function_exists() {
    test_case "search_similar_errors function exists"

    if grep -q "search_similar_errors()" "$ALL_SRC"; then
        test_pass
    else
        test_fail "search_similar_errors function not found"
    fi
}


test_search_similar_errors_returns_single_zero() {
    test_case "search_similar_errors returns a single zero when there are no matches"

    local tmp_workspace output
    tmp_workspace=$(mktemp -d)
    mkdir -p "$tmp_workspace/.octo/errors"
    printf '%s
' "unrelated error" > "$tmp_workspace/.octo/errors/error-log.md"

    output=$(WORKSPACE_DIR="$tmp_workspace" bash -c '
        source "$1/scripts/lib/quality.sh" 2>/dev/null
        search_similar_errors "react act test"
    ' _ "$PROJECT_ROOT")

    rm -rf "$tmp_workspace"
    if [[ "$output" == "0" ]]; then
        test_pass
    else
        test_fail "expected exactly one zero, got: $(printf %q "$output")"
    fi
}
test_flag_repeat_error_function_exists() {
    test_case "flag_repeat_error function exists"

    if grep -q "flag_repeat_error()" "$ALL_SRC"; then
        test_pass
    else
        test_fail "flag_repeat_error function not found"
    fi
}

test_error_format() {
    test_case "Error format includes required fields"

    local func_body
    func_body=$(sed -n '/^record_error()/,/^}/p' "$ALL_SRC")

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
    func_body=$(sed -n '/^record_error()/,/^}/p' "$ALL_SRC")

    if echo "$func_body" | grep -q "100"; then
        test_pass
    else
        test_fail "100 entry cap not found"
    fi
}

test_error_recording_in_spawn_agent() {
    test_case "record_error called in spawn_agent failure path"

    if grep -B 2 -A 2 "record_error.*spawn_agent" "$ALL_SRC" | grep -q "record_error"; then
        test_pass
    else
        test_fail "record_error not called in spawn_agent failure"
    fi
}

test_error_context_in_retries() {
    test_case "Error context injected into retry prompts"

    local retry_body
    retry_body=$(sed -n '/^retry_failed_subtasks()/,/^}/p' "$ALL_SRC")
    if echo "$retry_body" | grep -q "search_similar_errors" && echo "$retry_body" | grep -q "RETRY CONTEXT"; then
        test_pass
    else
        test_fail "Error context not injected into retries"
    fi
}

test_repeat_detection() {
    test_case "Repeat error detection triggers structured decision"

    local func_body
    func_body=$(sed -n '/^flag_repeat_error()/,/^}/p' "$ALL_SRC")

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
test_search_similar_errors_returns_single_zero
test_flag_repeat_error_function_exists
test_error_format
test_error_cap_100
test_error_recording_in_spawn_agent
test_error_context_in_retries
test_repeat_detection
test_dry_run_with_error_learning

rm -f "$ALL_SRC"
test_summary
