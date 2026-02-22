#!/bin/bash
# tests/unit/test-observation-importance.sh
# Tests observation importance scoring (v8.19.0)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Observation Importance Scoring"

test_score_importance_function_exists() {
    test_case "score_importance function exists in orchestrate.sh"

    if grep -q "score_importance()" "$PROJECT_ROOT/scripts/orchestrate.sh"; then
        test_pass
    else
        test_fail "score_importance function not found"
    fi
}

test_search_observations_function_exists() {
    test_case "search_observations function exists in orchestrate.sh"

    if grep -q "search_observations()" "$PROJECT_ROOT/scripts/orchestrate.sh"; then
        test_pass
    else
        test_fail "search_observations function not found"
    fi
}

test_importance_in_decision_format() {
    test_case "Importance field added to structured decision format"

    if grep -A 50 "write_structured_decision()" "$PROJECT_ROOT/scripts/orchestrate.sh" | grep -q "Importance"; then
        test_pass
    else
        test_fail "Importance field not in write_structured_decision"
    fi
}

test_importance_auto_scoring() {
    test_case "write_structured_decision auto-scores importance"

    if grep -A 30 "write_structured_decision()" "$PROJECT_ROOT/scripts/orchestrate.sh" | grep -q "score_importance"; then
        test_pass
    else
        test_fail "Auto-scoring via score_importance not found"
    fi
}

test_importance_base_scores() {
    test_case "Base scores match spec (security-finding=8, quality-gate=7)"

    local func_body
    func_body=$(sed -n '/^score_importance()/,/^}/p' "$PROJECT_ROOT/scripts/orchestrate.sh")

    if echo "$func_body" | grep -q "security-finding.*8" && \
       echo "$func_body" | grep -q "quality-gate.*7" && \
       echo "$func_body" | grep -q "debate-synthesis.*6" && \
       echo "$func_body" | grep -q "phase-completion.*5"; then
        test_pass
    else
        test_fail "Base scores don't match spec"
    fi
}

test_importance_confidence_adjustment() {
    test_case "Confidence adjusts importance (+1 high, -1 low)"

    local func_body
    func_body=$(sed -n '/^score_importance()/,/^}/p' "$PROJECT_ROOT/scripts/orchestrate.sh")

    if echo "$func_body" | grep -q "high.*+.*1\|base_score + 1" && \
       echo "$func_body" | grep -q "low.*-.*1\|base_score - 1"; then
        test_pass
    else
        test_fail "Confidence adjustment not found"
    fi
}

test_importance_clamped() {
    test_case "Importance is clamped to 1-10"

    local func_body
    func_body=$(sed -n '/^score_importance()/,/^}/p' "$PROJECT_ROOT/scripts/orchestrate.sh")

    if echo "$func_body" | grep -q "lt 1" && echo "$func_body" | grep -q "gt 10"; then
        test_pass
    else
        test_fail "Clamping to 1-10 not found"
    fi
}

test_high_importance_in_embrace() {
    test_case "High-importance observations injected into embrace workflow"

    if grep -A 10 "cleanup_expired_checkpoints" "$PROJECT_ROOT/scripts/orchestrate.sh" | grep -q "search_observations"; then
        test_pass
    else
        test_fail "High-importance injection not found in embrace_full_workflow"
    fi
}

test_dry_run_with_importance() {
    test_case "Dry-run works with importance scoring code"

    local output
    output=$("$PROJECT_ROOT/scripts/orchestrate.sh" -n probe "test" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        test_pass
    else
        test_fail "Dry-run failed: $exit_code"
    fi
}

# Run tests
test_score_importance_function_exists
test_search_observations_function_exists
test_importance_in_decision_format
test_importance_auto_scoring
test_importance_base_scores
test_importance_confidence_adjustment
test_importance_clamped
test_high_importance_in_embrace
test_dry_run_with_importance

test_summary
