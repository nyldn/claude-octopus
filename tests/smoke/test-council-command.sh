#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Council Command Smoke"

_is_macos_empty_orchestrate_output() {
    [[ "$(uname)" == "Darwin" && -z "${1:-}" ]]
}

test_council_help_shows_budget_flag() {
    test_case "council --help shows max-cost flag"

    local output
    output="$(OCTOPUS_PROJECT_DIR="$PROJECT_ROOT" bash "$PROJECT_ROOT/scripts/orchestrate.sh" council --help 2>&1 || true)"

    if _is_macos_empty_orchestrate_output "$output"; then
        test_skip "orchestrate help returned empty output on macOS CI shell; command smoke is covered on ubuntu"
        return 0
    elif echo "$output" | grep -q -- "--max-cost"; then
        test_pass
    else
        test_fail "help output missing --max-cost: $output"
        return 1
    fi
}

test_council_dry_run_via_orchestrate_writes_summary() {
    test_case "council dry-run via orchestrate writes summary JSON"

    local tmp_dir
    tmp_dir="$(mktemp -d "$TEST_TMP_DIR/council-smoke.XXXXXX")"

    local run_output exit_code=0
    run_output=$(OCTOPUS_PROJECT_DIR="$PROJECT_ROOT" bash "$PROJECT_ROOT/scripts/orchestrate.sh" council --dry-run --output-dir "$tmp_dir" "Should we use Redis?" 2>&1) || exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        if _is_macos_empty_orchestrate_output "$run_output"; then
            test_skip "orchestrate dry-run returned empty output on macOS CI shell; command smoke is covered on ubuntu"
            return 0
        fi
        test_fail "council dry-run failed with exit $exit_code: $run_output"
        return 1
    fi

    local summary
    summary="$(find "$tmp_dir" -name summary.json -type f | head -1)"
    [[ -n "$summary" ]] || { test_fail "summary.json not written"; return 1; }

    if jq -e '.command == "council" and .status == "dry-run" and .depth == "standard"' "$summary" >/dev/null; then
        test_pass
    else
        test_fail "summary JSON contract mismatch"
        return 1
    fi
}

test_council_fixture_is_test_only_and_recorded() {
    test_case "council fixture env is recorded in summary"

    local tmp_dir
    tmp_dir="$(mktemp -d "$TEST_TMP_DIR/council-fixture.XXXXXX")"

    local run_output exit_code=0
    run_output=$(OCTOPUS_COUNCIL_FIXTURE=critical-veto \
        OCTOPUS_PROJECT_DIR="$PROJECT_ROOT" bash "$PROJECT_ROOT/scripts/orchestrate.sh" council --dry-run --output-dir "$tmp_dir" "Ship this without tests" 2>&1) || exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        if _is_macos_empty_orchestrate_output "$run_output"; then
            test_skip "orchestrate fixture dry-run returned empty output on macOS CI shell; command smoke is covered on ubuntu"
            return 0
        fi
        test_fail "council fixture dry-run failed with exit $exit_code: $run_output"
        return 1
    fi

    local summary
    summary="$(find "$tmp_dir" -name summary.json -type f | head -1)"
    [[ -n "$summary" ]] || { test_fail "summary.json not written"; return 1; }

    if jq -e '.fixture == "critical-veto" and .veto.triggered == true and .veto.severity == "critical"' "$summary" >/dev/null; then
        test_pass
    else
        test_fail "fixture mode or veto path not recorded"
        return 1
    fi
}

test_council_help_shows_budget_flag
test_council_dry_run_via_orchestrate_writes_summary
test_council_fixture_is_test_only_and_recorded
test_summary
