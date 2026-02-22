#!/bin/bash
# tests/unit/test-cross-model-review.sh
# Tests cross-model review scoring 4x10 (v8.19.0)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Cross-Model Review Scoring (4x10)"

test_score_function_exists() {
    test_case "score_cross_model_review function exists"

    if grep -q "score_cross_model_review()" "$PROJECT_ROOT/scripts/orchestrate.sh"; then
        test_pass
    else
        test_fail "score_cross_model_review function not found"
    fi
}

test_scorecard_function_exists() {
    test_case "format_review_scorecard function exists"

    if grep -q "format_review_scorecard()" "$PROJECT_ROOT/scripts/orchestrate.sh"; then
        test_pass
    else
        test_fail "format_review_scorecard function not found"
    fi
}

test_cross_model_reviewer_function_exists() {
    test_case "get_cross_model_reviewer function exists"

    if grep -q "get_cross_model_reviewer()" "$PROJECT_ROOT/scripts/orchestrate.sh"; then
        test_pass
    else
        test_fail "get_cross_model_reviewer function not found"
    fi
}

test_review_4x10_env_var() {
    test_case "OCTOPUS_REVIEW_4X10 env var defined with default false"

    if grep -q 'OCTOPUS_REVIEW_4X10.*false' "$PROJECT_ROOT/scripts/orchestrate.sh"; then
        test_pass
    else
        test_fail "OCTOPUS_REVIEW_4X10 default not false"
    fi
}

test_explicit_score_extraction() {
    test_case "Explicit 'Security: N/10' pattern extraction"

    local func_body
    func_body=$(sed -n '/^score_cross_model_review()/,/^}/p' "$PROJECT_ROOT/scripts/orchestrate.sh")

    if echo "$func_body" | grep -q 'security.*10' && echo "$func_body" | grep -q 'reliability.*10'; then
        test_pass
    else
        test_fail "Explicit score extraction patterns not found"
    fi
}

test_heuristic_scoring() {
    test_case "Heuristic fallback for missing dimensions"

    local func_body
    func_body=$(sed -n '/^score_cross_model_review()/,/^}/p' "$PROJECT_ROOT/scripts/orchestrate.sh")

    if echo "$func_body" | grep -q "vulnerab\|injection\|xss" && echo "$func_body" | grep -q "crash\|unstable"; then
        test_pass
    else
        test_fail "Heuristic keyword patterns not found"
    fi
}

test_scorecard_format() {
    test_case "Scorecard has visual bar chart format"

    local func_body
    func_body=$(sed -n '/^format_review_scorecard()/,/^}/p' "$PROJECT_ROOT/scripts/orchestrate.sh")

    if echo "$func_body" | grep -q "Security:" && \
       echo "$func_body" | grep -q "Reliability:" && \
       echo "$func_body" | grep -q "Performance:" && \
       echo "$func_body" | grep -q "Accessibility:"; then
        test_pass
    else
        test_fail "Scorecard dimensions not all present"
    fi
}

test_cross_model_assignment() {
    test_case "Cross-model reviewer assignment (codex→gemini, gemini→codex)"

    local func_body
    func_body=$(sed -n '/^get_cross_model_reviewer()/,/^}/p' "$PROJECT_ROOT/scripts/orchestrate.sh")

    if echo "$func_body" | grep -q 'codex.*gemini' && echo "$func_body" | grep -q 'gemini.*codex'; then
        test_pass
    else
        test_fail "Cross-model assignment not correct"
    fi
}

test_4x10_gate_in_ink_deliver() {
    test_case "4x10 gate check in ink_deliver"

    if grep -A 100 "ink_deliver()" "$PROJECT_ROOT/scripts/orchestrate.sh" | grep -q "OCTOPUS_REVIEW_4X10"; then
        test_pass
    else
        test_fail "4x10 gate not in ink_deliver"
    fi
}

test_4x10_default_off() {
    test_case "4x10 gate is off by default"

    # The env var defaults to false, so the gate should not trigger
    if grep -q 'OCTOPUS_REVIEW_4X10:-false' "$PROJECT_ROOT/scripts/orchestrate.sh" || \
       grep -q 'OCTOPUS_REVIEW_4X10.*false' "$PROJECT_ROOT/scripts/orchestrate.sh"; then
        test_pass
    else
        test_fail "4x10 gate default is not false"
    fi
}

test_dry_run_with_review_scoring() {
    test_case "Dry-run works with cross-model review code"

    local output
    output=$("$PROJECT_ROOT/scripts/orchestrate.sh" -n ink "test" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        test_pass
    else
        test_fail "Dry-run failed: $exit_code"
    fi
}

# Run tests
test_score_function_exists
test_scorecard_function_exists
test_cross_model_reviewer_function_exists
test_review_4x10_env_var
test_explicit_score_extraction
test_heuristic_scoring
test_scorecard_format
test_cross_model_assignment
test_4x10_gate_in_ink_deliver
test_4x10_default_off
test_dry_run_with_review_scoring

test_summary
