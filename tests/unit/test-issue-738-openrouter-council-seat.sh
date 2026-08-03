#!/usr/bin/env bash
# tests/unit/test-issue-738-openrouter-council-seat.sh
# Regression tests for issue #738 / PR #739, requested as a follow-up during
# review of #739 (three bugs, all in the council -> OpenRouter seat path):
#   1. run_with_timeout()'s in-process fallback (scripts/lib/heartbeat.sh)
#      ran kill/wait on the timeout monitor unguarded. Under set -eo pipefail
#      (orchestrate.sh), a monitor that returns non-zero from kill or wait —
#      because it had already exited on its own — aborted the function after
#      the wrapped command had already succeeded, losing its captured output.
#   2. council_detect_providers() (scripts/lib/council.sh) probed `command -v
#      openrouter`, but OpenRouter is an API-key provider with no CLI binary —
#      dispatch goes through the shell function openrouter_execute. The seat
#      was always reported "missing" regardless of OPENROUTER_API_KEY.
#   3. openrouter_execute() (scripts/lib/perplexity.sh) always resolved its
#      model from the hardcoded task-type table, ignoring
#      OCTOPUS_OPENROUTER_MODEL / providers.json, so the seat silently ran a
#      different model than the one the council roster advertised.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Issue #738: OpenRouter council seat (probe, wait, model resolution)"

TEST_TMP_DIR="/tmp/octopus-tests-$$"
trap 'rm -rf "$TEST_TMP_DIR"' EXIT
mkdir -p "$TEST_TMP_DIR"

# ═══════════════════════════════════════════════════════════════════════════
# Bug 1: kill/wait on an already-gone monitor process must not abort a
# set -e script. This is the maintainer's own reproduction from the #739
# review (verified to fail on the pre-fix code: unguarded `wait` alone
# aborts, and separately an unguarded `kill` alone aborts).
# ═══════════════════════════════════════════════════════════════════════════

test_case "kill/wait on an already-reaped monitor does not abort under set -e"
# Illustrative repro of the underlying bash behavior (the maintainer's own
# reproduction from the #739 review, lifted verbatim) — it carries its own
# || true guards, so it passes on both sides of the fix and is not itself a
# heartbeat.sh regression detector. The next test (source-anchored) is: it is
# verified to fail against the pre-#739 heartbeat.sh and pass against the fix.
out=$(bash -c '
    set -eo pipefail
    ( sleep 0.05 ) &
    m=$!
    wait "$m" 2>/dev/null || true   # reaps the monitor, simulating it having already exited
    kill "$m" 2>/dev/null || true   # now-guarded: kill on an already-reaped pid
    wait "$m" 2>/dev/null || true   # now-guarded: wait on an already-reaped pid
    echo "REACHED-END"
')
if [[ "$out" == "REACHED-END" ]]; then
    test_pass
else
    test_fail "expected REACHED-END, got: '$out' (set -e aborted before reaching the end)"
fi

test_case "heartbeat.sh guards both the monitor kill and the monitor wait with || true"
HB="$PROJECT_ROOT/scripts/lib/heartbeat.sh"
if grep -qE 'kill "\$monitor_pid" 2>/dev/null \|\| true' "$HB" && \
   grep -qE 'wait "\$monitor_pid" 2>/dev/null \|\| true' "$HB"; then
    test_pass
else
    test_fail "monitor cleanup in heartbeat.sh is missing the || true guard on kill and/or wait (#738 regression)"
fi

test_case "run_with_timeout's in-process fallback still returns the captured output of a fast function command"
out=$(bash -c '
    source "'"$PROJECT_ROOT"'/scripts/lib/heartbeat.sh" 2>/dev/null || exit 2
    quick_ok() { echo "seat-output"; return 0; }
    export -f quick_ok
    _cmd_is_function=true
    run_with_timeout 5 quick_ok
' 2>/dev/null)
if [[ "$out" == "seat-output" ]]; then
    test_pass
else
    test_fail "expected seat-output, got: '$out'"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Bug 2: council_detect_providers() must probe OPENROUTER_API_KEY, not
# `command -v openrouter` (no such binary ships with the plugin).
# ═══════════════════════════════════════════════════════════════════════════

load_council_lib() {
    local lib="$PROJECT_ROOT/scripts/lib/council.sh"
    [[ -f "$lib" ]] || { test_fail "Missing $lib"; return 1; }
    # shellcheck disable=SC1090
    source "$lib"
}

# Restrict PATH to a directory holding only what these two assertions need
# (jq; bash builtins need no PATH entry at all), so a real `openrouter`
# executable on the host/CI machine's PATH can never make this test prove
# less than it claims.
JQ_BIN="$(command -v jq)"
NO_OPENROUTER_BIN_DIR="$TEST_TMP_DIR/no-openrouter-bin"
mkdir -p "$NO_OPENROUTER_BIN_DIR"
ln -sf "$JQ_BIN" "$NO_OPENROUTER_BIN_DIR/jq"

test_case "council_detect_providers reports openrouter available on OPENROUTER_API_KEY alone (no binary on PATH)"
load_council_lib || true
(
    export "PATH=${NO_OPENROUTER_BIN_DIR}"
    unset OCTOPUS_COUNCIL_PROVIDER_FIXTURE
    export "OPENROUTER_API_KEY=test-key-not-real"
    COUNCIL_PROVIDERS="openrouter"
    council_detect_providers
    status="$(jq -r '.openrouter // "missing"' <<< "$COUNCIL_PROVIDER_STATUS_JSON")"
    [[ "$status" == "available" ]]
) && test_pass || test_fail "expected openrouter:available with OPENROUTER_API_KEY set and no binary on PATH"

test_case "council_detect_providers reports openrouter missing when OPENROUTER_API_KEY is unset"
(
    export "PATH=${NO_OPENROUTER_BIN_DIR}"
    unset OCTOPUS_COUNCIL_PROVIDER_FIXTURE
    unset OPENROUTER_API_KEY 2>/dev/null || true
    COUNCIL_PROVIDERS="openrouter"
    council_detect_providers
    status="$(jq -r '.openrouter // "missing"' <<< "$COUNCIL_PROVIDER_STATUS_JSON")"
    [[ "$status" == "missing" ]]
) && test_pass || test_fail "expected openrouter:missing with no OPENROUTER_API_KEY"

# ═══════════════════════════════════════════════════════════════════════════
# Bug 3: openrouter_execute() must prefer the configured model
# (OCTOPUS_OPENROUTER_MODEL, then resolve_octopus_model) over the hardcoded
# task-type table, so the roster's advertised model is what actually runs.
# ═══════════════════════════════════════════════════════════════════════════

MODEL_ARGS_FILE="$TEST_TMP_DIR/openrouter-model-args.txt"

run_openrouter_execute() {
    local scenario="$1"
    bash -c '
        log() { :; }
        source "'"$PROJECT_ROOT"'/scripts/lib/perplexity.sh" 2>/dev/null
        # Each scenario must validate its own precedence branch, not whatever
        # this process happened to inherit from the ambient environment.
        unset OCTOPUS_OPENROUTER_MODEL
        unset -f resolve_octopus_model 2>/dev/null || true
        openrouter_execute_model() { printf "%s\n" "$1" > "'"$MODEL_ARGS_FILE"'"; echo "ok"; }
        case "$1" in
            *resolver*) resolve_octopus_model() { echo "resolver-model"; } ;;
        esac
        case "$1" in
            *env*) export "OCTOPUS_OPENROUTER_MODEL=env-pinned-model" ;;
        esac
        # get_openrouter_model lives in providers.sh (not sourced here); stub it
        # to isolate this test to openrouter_execute'"'"'s own fallback ordering.
        get_openrouter_model() { echo "table-fallback-model"; }
        openrouter_execute "test prompt" "general" 2 "" >/dev/null
    ' _ "$scenario"
}

test_case "openrouter_execute honours OCTOPUS_OPENROUTER_MODEL over resolve_octopus_model and the task-type table"
rm -f "$MODEL_ARGS_FILE"
run_openrouter_execute "env-and-resolver"
out="$(cat "$MODEL_ARGS_FILE" 2>/dev/null || true)"
if [[ "$out" == "env-pinned-model" ]]; then
    test_pass
else
    test_fail "expected env-pinned-model, got '$out'"
fi

test_case "openrouter_execute falls back to resolve_octopus_model when OCTOPUS_OPENROUTER_MODEL is unset"
rm -f "$MODEL_ARGS_FILE"
run_openrouter_execute "resolver"
out="$(cat "$MODEL_ARGS_FILE" 2>/dev/null || true)"
if [[ "$out" == "resolver-model" ]]; then
    test_pass
else
    test_fail "expected resolver-model, got '$out'"
fi

test_case "openrouter_execute falls back to the task-type table when neither env nor resolver is available"
rm -f "$MODEL_ARGS_FILE"
run_openrouter_execute "plain"
out="$(cat "$MODEL_ARGS_FILE" 2>/dev/null || true)"
if [[ "$out" == "table-fallback-model" ]]; then
    test_pass
else
    test_fail "expected table-fallback-model, got '$out'"
fi

test_summary
