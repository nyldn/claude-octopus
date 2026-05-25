#!/usr/bin/env bash
# tests/smoke/test-ollama-models.sh
# Smoke tests for scripts/helpers/check-ollama-models.sh
# Uses OCTO_OLLAMA_API_URL=file:///tmp/... to mock the Ollama API.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "check-ollama-models.sh"

# Disable errexit for tests — we capture exit codes explicitly and expect non-zero.
set +e

CHECK_SCRIPT="$PROJECT_ROOT/scripts/helpers/check-ollama-models.sh"
PROVIDER_VERSIONS="$PROJECT_ROOT/scripts/lib/provider-versions.sh"

# Fixture directory
FIXTURE_DIR=$(mktemp -d 2>/dev/null) || FIXTURE_DIR="/tmp/octo-ollama-tests-$$"
mkdir -p "$FIXTURE_DIR"

# Build a fixture with 1 fresh model, 1 stale model
build_mixed_fixture() {
    python3 - "$1" <<'PYEOF'
import sys, json, datetime
now = datetime.datetime.now(datetime.timezone.utc)
fresh = now.strftime('%Y-%m-%dT%H:%M:%S.000Z')
stale = (now - datetime.timedelta(days=45)).strftime('%Y-%m-%dT%H:%M:%S.000Z')
data = {"models": [
    {"name": "fresh-model:latest", "modified_at": fresh},
    {"name": "stale-model:latest", "modified_at": stale},
]}
with open(sys.argv[1], "w") as f:
    json.dump(data, f)
PYEOF
}

build_all_fresh_fixture() {
    python3 - "$1" <<'PYEOF'
import sys, json, datetime
now = datetime.datetime.now(datetime.timezone.utc)
fresh = now.strftime('%Y-%m-%dT%H:%M:%S.000Z')
data = {"models": [
    {"name": "model-a:latest", "modified_at": fresh},
    {"name": "model-b:latest", "modified_at": fresh},
]}
with open(sys.argv[1], "w") as f:
    json.dump(data, f)
PYEOF
}

build_empty_fixture() {
    echo '{"models": []}' > "$1"
}

# ── File existence ─────────────────────────────────────────────────────────

test_file_exists() {
    test_case "check-ollama-models.sh exists"
    [[ -f "$CHECK_SCRIPT" ]] && test_pass || test_fail "Script not found at $CHECK_SCRIPT"
}

test_provider_versions_has_helper() {
    test_case "provider-versions.sh defines octo_ollama_model_age_ok"
    if grep -q "octo_ollama_model_age_ok()" "$PROVIDER_VERSIONS"; then
        test_pass
    else
        test_fail "octo_ollama_model_age_ok not found in provider-versions.sh"
    fi
}

# ── Syntax ─────────────────────────────────────────────────────────────────

test_syntax_clean() {
    test_case "check-ollama-models.sh syntax is valid"
    bash -n "$CHECK_SCRIPT" 2>/dev/null && test_pass || test_fail "Bash syntax error"
}

# ── Mixed fresh + stale ────────────────────────────────────────────────────

test_mixed_human_output() {
    test_case "Mixed fixture: human output lists both models"
    local fixture="$FIXTURE_DIR/mixed.json"
    build_mixed_fixture "$fixture"
    local out
    out=$(OCTO_OLLAMA_API_URL="file://$fixture" bash "$CHECK_SCRIPT" 2>&1 || true)
    if echo "$out" | grep -q "fresh-model" && echo "$out" | grep -q "stale-model"; then
        test_pass
    else
        test_fail "Expected both models in output. Got: $out"
    fi
}

test_mixed_count_stale_returns_one() {
    test_case "Mixed fixture: --count-stale returns 1"
    local fixture="$FIXTURE_DIR/mixed.json"
    build_mixed_fixture "$fixture"
    local count
    count=$(OCTO_OLLAMA_API_URL="file://$fixture" bash "$CHECK_SCRIPT" --count-stale 2>/dev/null)
    [[ "$count" == "1" ]] && test_pass || test_fail "Expected 1, got '$count'"
}

test_mixed_exit_code_is_one() {
    test_case "Mixed fixture: --exit-code returns 1"
    local fixture="$FIXTURE_DIR/mixed.json"
    build_mixed_fixture "$fixture"
    OCTO_OLLAMA_API_URL="file://$fixture" bash "$CHECK_SCRIPT" --exit-code 2>/dev/null
    local rc=$?
    [[ "$rc" -eq 1 ]] && test_pass || test_fail "Expected exit 1, got $rc"
}

test_mixed_json_valid() {
    test_case "Mixed fixture: --json produces valid JSON"
    local fixture="$FIXTURE_DIR/mixed.json"
    build_mixed_fixture "$fixture"
    local out
    out=$(OCTO_OLLAMA_API_URL="file://$fixture" bash "$CHECK_SCRIPT" --json 2>/dev/null)
    if echo "$out" | python3 -m json.tool >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Invalid JSON: $out"
    fi
}

test_mixed_json_has_stale_field() {
    test_case "Mixed fixture: --json includes stale=1"
    local fixture="$FIXTURE_DIR/mixed.json"
    build_mixed_fixture "$fixture"
    local stale_val
    stale_val=$(OCTO_OLLAMA_API_URL="file://$fixture" bash "$CHECK_SCRIPT" --json 2>/dev/null \
        | python3 -c "import json,sys; print(json.load(sys.stdin)['stale'])" 2>/dev/null)
    [[ "$stale_val" == "1" ]] && test_pass || test_fail "Expected stale=1, got '$stale_val'"
}

# ── All fresh ──────────────────────────────────────────────────────────────

test_all_fresh_count_zero() {
    test_case "All-fresh fixture: --count-stale returns 0"
    local fixture="$FIXTURE_DIR/all-fresh.json"
    build_all_fresh_fixture "$fixture"
    local count
    count=$(OCTO_OLLAMA_API_URL="file://$fixture" bash "$CHECK_SCRIPT" --count-stale 2>/dev/null)
    [[ "$count" == "0" ]] && test_pass || test_fail "Expected 0, got '$count'"
}

test_all_fresh_exit_zero() {
    test_case "All-fresh fixture: --exit-code returns 0"
    local fixture="$FIXTURE_DIR/all-fresh.json"
    build_all_fresh_fixture "$fixture"
    OCTO_OLLAMA_API_URL="file://$fixture" bash "$CHECK_SCRIPT" --exit-code 2>/dev/null
    local rc=$?
    [[ "$rc" -eq 0 ]] && test_pass || test_fail "Expected exit 0, got $rc"
}

# ── Empty / unreachable ────────────────────────────────────────────────────

test_empty_fixture_count_zero() {
    test_case "Empty models array: --count-stale returns 0"
    local fixture="$FIXTURE_DIR/empty.json"
    build_empty_fixture "$fixture"
    local count
    count=$(OCTO_OLLAMA_API_URL="file://$fixture" bash "$CHECK_SCRIPT" --count-stale 2>/dev/null)
    [[ "$count" == "0" ]] && test_pass || test_fail "Expected 0, got '$count'"
}

test_unreachable_server_exit_zero() {
    test_case "Unreachable server: exits 0 (fail open)"
    OCTO_OLLAMA_API_URL="http://localhost:65530" bash "$CHECK_SCRIPT" --exit-code 2>/dev/null
    local rc=$?
    [[ "$rc" -eq 0 ]] && test_pass || test_fail "Expected exit 0, got $rc"
}

test_unreachable_count_stale_zero() {
    test_case "Unreachable server: --count-stale returns 0"
    local count
    count=$(OCTO_OLLAMA_API_URL="http://localhost:65530" bash "$CHECK_SCRIPT" --count-stale 2>/dev/null)
    [[ "$count" == "0" ]] && test_pass || test_fail "Expected 0, got '$count'"
}

# ── Comparator unit tests ──────────────────────────────────────────────────

test_age_ok_unknown_date_passes() {
    test_case "octo_ollama_model_age_ok fails open on empty input"
    # shellcheck source=/dev/null
    source "$PROVIDER_VERSIONS"
    octo_ollama_model_age_ok "" && test_pass || test_fail "Should fail open on empty"
}

test_age_ok_garbage_date_passes() {
    test_case "octo_ollama_model_age_ok fails open on garbage input"
    source "$PROVIDER_VERSIONS"
    octo_ollama_model_age_ok "not-a-date" && test_pass || test_fail "Should fail open on garbage"
}

test_age_ok_fresh_passes() {
    test_case "octo_ollama_model_age_ok passes for fresh model"
    source "$PROVIDER_VERSIONS"
    local fresh
    fresh=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    octo_ollama_model_age_ok "$fresh" && test_pass || test_fail "Fresh model should pass"
}

# ── Run all tests ──────────────────────────────────────────────────────────

test_file_exists
test_provider_versions_has_helper
test_syntax_clean
test_mixed_human_output
test_mixed_count_stale_returns_one
test_mixed_exit_code_is_one
test_mixed_json_valid
test_mixed_json_has_stale_field
test_all_fresh_count_zero
test_all_fresh_exit_zero
test_empty_fixture_count_zero
test_unreachable_server_exit_zero
test_unreachable_count_stale_zero
test_age_ok_unknown_date_passes
test_age_ok_garbage_date_passes
test_age_ok_fresh_passes

# Cleanup
rm -rf "$FIXTURE_DIR" 2>/dev/null

test_summary