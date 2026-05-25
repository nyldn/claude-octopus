#!/usr/bin/env bash
# tests/smoke/test-preflight-json.sh
# Smoke tests for scripts/helpers/preflight.sh --json mode.
# Validates: exit code 0, valid JSON, required keys, embedded versions object structure.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "preflight.sh --json"

PREFLIGHT="$PROJECT_ROOT/scripts/helpers/preflight.sh"

# Helper: assert that the captured JSON has a top-level key. Uses pure grep on
# the rendered JSON to avoid relying on jq or multi-line python -c invocations
# (the latter trip on Windows python wrappers).
_has_key() {
    local out="$1" key="$2"
    echo "$out" | grep -qE "\"${key}\"[[:space:]]*:"
}

test_preflight_exists() {
    test_case "preflight.sh exists"
    [[ -f "$PREFLIGHT" ]] && test_pass || test_fail "preflight.sh not found at $PREFLIGHT"
}

test_json_mode_exits_zero() {
    test_case "--json mode exits 0"
    bash "$PREFLIGHT" --json &>/dev/null
    if [[ $? -eq 0 ]]; then
        test_pass
    else
        test_fail "--json mode exited non-zero"
    fi
}

test_json_mode_emits_valid_json() {
    test_case "--json mode emits parseable JSON"
    local out
    out=$(bash "$PREFLIGHT" --json 2>/dev/null)
    if echo "$out" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
        test_pass
    else
        test_fail "Output is not valid JSON: ${out:0:300}"
    fi
}

test_json_required_keys() {
    test_case "--json output has required top-level keys"
    local out
    out=$(bash "$PREFLIGHT" --json 2>/dev/null)
    local missing=""
    for k in providers_ready providers_degraded results versions; do
        _has_key "$out" "$k" || missing="$missing $k"
    done
    if [[ -z "$missing" ]]; then
        test_pass
    else
        test_fail "Missing keys:${missing}"
    fi
}

test_json_versions_has_floor_field() {
    test_case "--json versions sub-object exposes any_below_floor"
    local out
    out=$(bash "$PREFLIGHT" --json 2>/dev/null)
    # any_below_floor should appear after "versions"
    if echo "$out" | grep -q "any_below_floor"; then
        test_pass
    else
        test_fail "any_below_floor not found in output"
    fi
}

test_json_results_entries_well_formed() {
    test_case "--json results entries have name+status fields"
    local out
    out=$(bash "$PREFLIGHT" --json 2>/dev/null)
    # Every entry in the results array should contain both name and status
    local entry_count name_count status_count
    entry_count=$(echo "$out" | grep -cE '^\s*\{"name": ".*", "status": ".*"\}')
    if [[ $entry_count -gt 0 ]]; then
        test_pass
    else
        test_fail "No well-formed name+status entries found"
    fi
}

test_exit_code_mode_returns_zero() {
    test_case "--exit-code mode always exits 0"
    bash "$PREFLIGHT" --exit-code
    if [[ $? -eq 0 ]]; then
        test_pass
    else
        test_fail "--exit-code mode returned non-zero"
    fi
}

test_preflight_exists
test_json_mode_exits_zero
test_json_mode_emits_valid_json
test_json_required_keys
test_json_versions_has_floor_field
test_json_results_entries_well_formed
test_exit_code_mode_returns_zero

test_summary
