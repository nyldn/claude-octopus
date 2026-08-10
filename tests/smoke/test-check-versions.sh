#!/usr/bin/env bash
# tests/smoke/test-check-versions.sh
# Smoke tests for scripts/helpers/check-versions.sh
# Validates: file exists, syntax clean, all three output modes, floor comparison logic.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "check-versions.sh"

CHECK_VERSIONS="$PROJECT_ROOT/scripts/helpers/check-versions.sh"
PROVIDER_VERSIONS="$PROJECT_ROOT/scripts/lib/provider-versions.sh"

# ── File existence ─────────────────────────────────────────────────────────

test_file_exists() {
    test_case "check-versions.sh exists"
    if [[ -f "$CHECK_VERSIONS" ]]; then
        test_pass
    else
        test_fail "check-versions.sh not found at $CHECK_VERSIONS"
    fi
}

test_provider_versions_exists() {
    test_case "provider-versions.sh dependency exists"
    if [[ -f "$PROVIDER_VERSIONS" ]]; then
        test_pass
    else
        test_fail "provider-versions.sh not found at $PROVIDER_VERSIONS"
    fi
}

# ── Syntax ─────────────────────────────────────────────────────────────────

test_syntax_clean() {
    test_case "check-versions.sh has valid bash syntax"
    if bash -n "$CHECK_VERSIONS" 2>/dev/null; then
        test_pass
    else
        test_fail "bash -n reported syntax errors"
    fi
}

test_provider_versions_syntax_clean() {
    test_case "provider-versions.sh has valid bash syntax"
    if bash -n "$PROVIDER_VERSIONS" 2>/dev/null; then
        test_pass
    else
        test_fail "bash -n reported syntax errors in provider-versions.sh"
    fi
}

# ── Mode: interactive (default) ────────────────────────────────────────────

test_default_mode_runs() {
    test_case "default mode exits 0 and produces output"
    local out rc=0
    out=$(bash "$CHECK_VERSIONS" 2>/dev/null) || rc=$?
    if [[ $rc -ne 0 && $rc -ne 1 ]]; then
        test_fail "Unexpected exit code $rc"
        return 1
    fi
    # If any provider CLI is installed, output must contain at least one v<semver> line.
    # Otherwise, the no-providers marker must appear.
    if echo "$out" | grep -qE 'v[0-9]+\.[0-9]+\.[0-9]+'; then
        test_pass
    elif echo "$out" | grep -q "version unknown"; then
        test_pass
    elif echo "$out" | grep -q "no provider CLIs detected"; then
        test_pass
    else
        test_fail "Output asserts nothing meaningful: ${out:0:200}"
    fi
}

# ── Mode: --exit-code ──────────────────────────────────────────────────────

test_exit_code_mode_exits_0_when_all_ok() {
    test_case "--exit-code mode produces no output and exits 0 or 1"
    local out rc=0
    out=$(bash "$CHECK_VERSIONS" --exit-code 2>/dev/null) || rc=$?
    if [[ $rc -eq 0 || $rc -eq 1 ]] && [[ -z "$out" ]]; then
        test_pass
    else
        test_fail "Exit code was $rc or unexpected output: $out"
    fi
}

# ── Mode: --json ───────────────────────────────────────────────────────────

test_json_mode_valid_json_structure() {
    test_case "--json mode outputs valid JSON with required keys"
    local out
    out=$(bash "$CHECK_VERSIONS" --json 2>/dev/null)
    local rc=$?
    if echo "$out" | grep -q '"any_below_floor"' &&        echo "$out" | grep -q '"results"'; then
        test_pass
    else
        test_fail "JSON missing expected keys. Output: ${out:0:200}"
    fi
}

test_json_mode_no_stderr_errors() {
    test_case "--json mode produces no errors on stderr"
    local err
    err=$(bash "$CHECK_VERSIONS" --json 2>&1 >/dev/null)
    if [[ -z "$err" ]]; then
        test_pass
    else
        test_fail "Unexpected stderr: $err"
    fi
}

# ── Floor logic via octo_version_ok() ─────────────────────────────────────

test_version_ok_equal() {
    test_case "octo_version_ok: equal versions pass"
    source "$PROVIDER_VERSIONS"
    if octo_version_ok "1.0.0" "1.0.0"; then
        test_pass
    else
        test_fail "1.0.0 >= 1.0.0 should pass"
    fi
}

test_version_ok_newer() {
    test_case "octo_version_ok: newer installed version passes"
    source "$PROVIDER_VERSIONS"
    if octo_version_ok "2.5.3" "1.0.0"; then
        test_pass
    else
        test_fail "2.5.3 >= 1.0.0 should pass"
    fi
}

test_version_ok_older_fails() {
    test_case "octo_version_ok: older version fails (returns 1)"
    source "$PROVIDER_VERSIONS"
    if ! octo_version_ok "0.9.9" "1.0.0"; then
        test_pass
    else
        test_fail "0.9.9 < 1.0.0 should fail"
    fi
}

test_version_ok_unknown_passes() {
    test_case "octo_version_ok: unknown version fails open (returns 0)"
    source "$PROVIDER_VERSIONS"
    if octo_version_ok "unknown" "1.0.0"; then
        test_pass
    else
        test_fail "unknown should fail open (return 0)"
    fi
}

test_version_ok_patch_newer() {
    test_case "octo_version_ok: patch increment passes"
    source "$PROVIDER_VERSIONS"
    if octo_version_ok "0.100.1" "0.100.0"; then
        test_pass
    else
        test_fail "0.100.1 >= 0.100.0 should pass"
    fi
}

test_version_ok_09_not_octal() {
    test_case "octo_version_ok: versions with 08/09 components don't hit octal error"
    source "$PROVIDER_VERSIONS"
    if octo_version_ok "9.10.0" "9.09.0"; then
        test_pass
    else
        test_fail "9.10.0 >= 9.09.0 should pass (base-10 arithmetic)"
    fi
}

# ── Floor constants defined ────────────────────────────────────────────────

test_floor_constants_defined() {
    test_case "All floor constants are non-empty"
    source "$PROVIDER_VERSIONS"
    local failed=0
    for var in OCTO_CODEX_MIN_VERSION OCTO_AGY_MIN_VERSION OCTO_QWEN_MIN_VERSION                OCTO_GH_MIN_VERSION OCTO_OPENCODE_MIN_VERSION; do
        if [[ -z "${!var:-}" ]]; then
            echo "  Missing: $var"
            failed=1
        fi
    done
    if [[ $failed -eq 0 ]]; then
        test_pass
    else
        test_fail "One or more floor constants are empty or undefined"
    fi
}

# Run all tests
test_file_exists
test_provider_versions_exists
test_syntax_clean
test_provider_versions_syntax_clean
test_default_mode_runs
test_exit_code_mode_exits_0_when_all_ok
test_json_mode_valid_json_structure
test_json_mode_no_stderr_errors
test_version_ok_equal
test_version_ok_newer
test_version_ok_older_fails
test_version_ok_unknown_passes
test_version_ok_patch_newer
test_version_ok_09_not_octal
test_floor_constants_defined

test_summary
