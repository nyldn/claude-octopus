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
    # grep -c (not -q) — -q exits on first match, closing the pipe before
    # echo finishes writing, which under this script's inherited
    # `set -o pipefail` (from test-framework.sh) can fail the whole
    # pipeline on a SIGPIPE write error even though the key was found.
    echo "$out" | grep -cE "\"${key}\"[[:space:]]*:" >/dev/null
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
    test_case "--json results entries expose the shared readiness schema"
    local out
    out=$(bash "$PREFLIGHT" --json 2>/dev/null)
    if echo "$out" | python3 -c 'import json,sys; data=json.load(sys.stdin); results=data.get("results", []); required={"provider","status","reason_code","check_kind","checked_at","duration_ms","remediation"}; assert results and all(required <= set(r) for r in results)' 2>/dev/null; then
        test_pass
    else
        test_fail "No well-formed shared readiness entries found"
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

test_human_guidance_matches_ready_provider_count() {
    test_case "human guidance distinguishes zero, Claude-only, single, and multi-provider readiness"
    local fixture_root="$TEST_TMP_DIR/preflight-guidance"
    local fixture_script="$fixture_root/helpers/preflight.sh"
    local output failures=""
    mkdir -p "$fixture_root/helpers" "$fixture_root/lib"
    cp "$PREFLIGHT" "$fixture_script"
    cat > "$fixture_root/lib/preflight.sh" <<'STUB'
octo_provider_readiness_all() {
    printf '%s\n' "$PREFLIGHT_FIXTURE_RESULTS"
}
STUB

    output="$(PREFLIGHT_FIXTURE_RESULTS='' bash "$fixture_script" 2>/dev/null)"
    [[ "$output" == *"No provider is ready."* ]] || failures+="zero-ready guidance missing; "

    output="$(PREFLIGHT_FIXTURE_RESULTS='{"provider":"claude","status":"available","reason_code":"ready"}' \
        bash "$fixture_script" 2>/dev/null)"
    [[ "$output" == *"Claude-only mode is available."* ]] || failures+="Claude-only guidance missing; "

    output="$(PREFLIGHT_FIXTURE_RESULTS='{"provider":"codex","status":"available","reason_code":"ready"}' \
        bash "$fixture_script" 2>/dev/null)"
    [[ "$output" == *"One provider is ready: codex."* ]] || failures+="single-provider guidance missing; "

    output="$(PREFLIGHT_FIXTURE_RESULTS=$'{"provider":"claude","status":"available","reason_code":"ready"}\n{"provider":"codex","status":"available","reason_code":"ready"}' \
        bash "$fixture_script" 2>/dev/null)"
    [[ "$output" == *"Multi-provider mode is ready."* ]] || failures+="two-provider guidance missing; "

    if [[ -z "$failures" ]]; then
        test_pass
    else
        test_fail "$failures"
    fi
}

test_missing_jq_reports_clean_error() {
    test_case "missing jq reports a clean installation error"
    local no_jq_bin="$TEST_TMP_DIR/no-jq-bin" no_jq_output no_jq_rc
    mkdir -p "$no_jq_bin"
    ln -s "$(command -v dirname)" "$no_jq_bin/dirname"
    set +e
    no_jq_output="$(PATH="$no_jq_bin" /bin/bash "$PREFLIGHT" --json 2>&1)"
    no_jq_rc=$?
    set -e
    if [[ "$no_jq_rc" -eq 1 ]] &&
       [[ "$no_jq_output" == *"requires jq. Install jq and retry."* ]] &&
       [[ "$no_jq_output" != *"command not found"* ]]; then
        test_pass
    else
        test_fail "missing-jq diagnostic was unclear: rc=$no_jq_rc output=$no_jq_output"
    fi
}

test_preflight_exists
test_json_mode_exits_zero
test_json_mode_emits_valid_json
test_json_required_keys
test_json_versions_has_floor_field
test_json_results_entries_well_formed
test_exit_code_mode_returns_zero
test_human_guidance_matches_ready_provider_count
test_missing_jq_reports_clean_error

test_summary
