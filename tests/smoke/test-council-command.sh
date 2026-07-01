#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Council Command Smoke"

test_council_help_shows_budget_flag() {
    test_case "council --help shows max-cost flag"

    local output
    output="$(OCTOPUS_PROJECT_DIR="$PROJECT_ROOT" bash "$PROJECT_ROOT/scripts/orchestrate.sh" council --help 2>&1 || true)"

    if echo "$output" | grep -q -- "--max-cost"; then
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

    OCTOPUS_PROJECT_DIR="$PROJECT_ROOT" bash "$PROJECT_ROOT/scripts/orchestrate.sh" council --dry-run --output-dir "$tmp_dir" "Should we use Redis?" >/dev/null

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

    OCTOPUS_COUNCIL_FIXTURE=critical-veto \
        OCTOPUS_PROJECT_DIR="$PROJECT_ROOT" bash "$PROJECT_ROOT/scripts/orchestrate.sh" council --dry-run --output-dir "$tmp_dir" "Ship this without tests" >/dev/null

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
