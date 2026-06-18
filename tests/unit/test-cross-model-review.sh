#!/bin/bash
# tests/unit/test-cross-model-review.sh
# Tests cross-model review scoring 4x10 (v8.19.0)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Cross-Model Review Scoring (4x10)"

# Combined search target (functions decomposed to lib/ in v9.7.7+)
ALL_SRC=$(mktemp)
cat "$PROJECT_ROOT/scripts/orchestrate.sh" "$PROJECT_ROOT/scripts/lib/"*.sh > "$ALL_SRC" 2>/dev/null

test_score_function_exists() {
    test_case "score_cross_model_review function exists"

    if grep -q "score_cross_model_review()" "$ALL_SRC"; then
        test_pass
    else
        test_fail "score_cross_model_review function not found"
    fi
}

test_scorecard_function_exists() {
    test_case "format_review_scorecard function exists"

    if grep -q "format_review_scorecard()" "$ALL_SRC"; then
        test_pass
    else
        test_fail "format_review_scorecard function not found"
    fi
}

test_cross_model_reviewer_function_exists() {
    test_case "get_cross_model_reviewer function exists"

    if grep -q "get_cross_model_reviewer()" "$ALL_SRC"; then
        test_pass
    else
        test_fail "get_cross_model_reviewer function not found"
    fi
}

test_review_4x10_env_var() {
    test_case "OCTOPUS_REVIEW_4X10 env var defined with default false"

    if grep -q 'OCTOPUS_REVIEW_4X10.*false' "$ALL_SRC"; then
        test_pass
    else
        test_fail "OCTOPUS_REVIEW_4X10 default not false"
    fi
}

test_explicit_score_extraction() {
    test_case "Explicit 'Security: N/10' pattern extraction"

    local func_body
    func_body=$(sed -n '/^score_cross_model_review()/,/^}/p' "$ALL_SRC")

    # v9.5: score function uses bash regex vars (_re_sec, _re_rel, etc.)
    if echo "$func_body" | grep -q '_re_sec.*ecurity.*10' && echo "$func_body" | grep -q '_re_rel.*eliability.*10'; then
        test_pass
    else
        test_fail "Explicit score extraction patterns not found"
    fi
}

test_heuristic_scoring() {
    test_case "Heuristic fallback for missing dimensions"

    local func_body
    func_body=$(sed -n '/^score_cross_model_review()/,/^}/p' "$ALL_SRC")

    if echo "$func_body" | grep -q "vulnerab\|injection\|xss" && echo "$func_body" | grep -q "crash\|unstable"; then
        test_pass
    else
        test_fail "Heuristic keyword patterns not found"
    fi
}

test_scorecard_format() {
    test_case "Scorecard has visual bar chart format"

    local func_body
    func_body=$(sed -n '/^format_review_scorecard()/,/^}/p' "$ALL_SRC")

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
    test_case "Cross-model reviewer assignment (codex->agy, agy->codex)"

    local func_body
    func_body=$(sed -n '/^get_cross_model_reviewer()/,/^}/p' "$ALL_SRC")

    # Google seat is agy (Gemini CLI sunset 2026-06-18): codex author -> agy
    # reviewer, agy author -> codex reviewer.
    if echo "$func_body" | grep -q 'codex.*agy' && echo "$func_body" | grep -q 'agy.*codex'; then
        test_pass
    else
        test_fail "Cross-model assignment not correct"
    fi
}

test_4x10_gate_in_ink_deliver() {
    test_case "4x10 gate check in ink_deliver"

    if grep -A 100 "ink_deliver()" "$ALL_SRC" | grep -q "OCTOPUS_REVIEW_4X10"; then
        test_pass
    else
        test_fail "4x10 gate not in ink_deliver"
    fi
}

test_4x10_default_off() {
    test_case "4x10 gate is off by default"

    # The env var defaults to false, so the gate should not trigger
    if grep -q 'OCTOPUS_REVIEW_4X10:-false' "$ALL_SRC" || \
       grep -q 'OCTOPUS_REVIEW_4X10.*false' "$ALL_SRC"; then
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

rm -f "$ALL_SRC"
test_summary
