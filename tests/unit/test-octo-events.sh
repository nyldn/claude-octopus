#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Octopus event stream helpers"

# shellcheck disable=SC1091
source "$PROJECT_ROOT/scripts/lib/events.sh"

FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT

test_no_log_when_disabled() {
    test_case "octo_event_emit is a no-op when OCTO_EVENT_LOG is unset"
    unset OCTO_EVENT_LOG
    octo_event_emit "provider.status" provider=qwen status=degraded
    if [[ -z "$(find "$FIXTURE" -mindepth 1 -print -quit)" ]]; then test_pass
    else test_fail "event log created files while disabled"; fi
}

test_emit_jsonl_event() {
    test_case "octo_event_emit writes JSONL with string attributes"
    export OCTO_EVENT_LOG="$FIXTURE/events.jsonl"
    export OCTO_EVENT_SOURCE="unit-test"
    export OCTOPUS_SESSION_ID="session-1"
    octo_event_emit "provider.status" provider=qwen status=degraded detail='quote " and slash \'

    if [[ ! -s "$OCTO_EVENT_LOG" ]]; then
        test_fail "event log was not written"
        return
    fi

    if command -v jq >/dev/null 2>&1; then
        jq -e 'select(
            .event == "provider.status" and
            .source == "unit-test" and
            .session_id == "session-1" and
            .attributes.provider == "qwen" and
            .attributes.status == "degraded"
        )' < "$OCTO_EVENT_LOG" >/dev/null || { test_fail "event JSON did not parse"; return; }
    else
        grep -q '"event":"provider.status"' "$OCTO_EVENT_LOG" || { test_fail "event name missing"; return; }
    fi
    test_pass
}

test_auto_log_path() {
    test_case "OCTO_EVENT_LOG=auto writes under WORKSPACE_DIR/.octo"
    export WORKSPACE_DIR="$FIXTURE/workspace"
    export OCTO_EVENT_LOG="auto"
    octo_event_emit "octo.audit" result=pass
    if [[ -s "$WORKSPACE_DIR/.octo/events.jsonl" ]]; then test_pass
    else test_fail "auto event log was not written"; fi
}

test_trim_event_log() {
    test_case "octo_event_emit trims to OCTO_EVENT_MAX_LINES"
    export OCTO_EVENT_LOG="$FIXTURE/trim.jsonl"
    export OCTO_EVENT_MAX_LINES=2
    octo_event_emit "octo.test" n=1
    octo_event_emit "octo.test" n=2
    octo_event_emit "octo.test" n=3
    local lines
    lines="$(wc -l < "$OCTO_EVENT_LOG" | tr -d ' ')"
    unset OCTO_EVENT_MAX_LINES
    if [[ "$lines" == "2" ]]; then test_pass
    else test_fail "expected 2 lines after trim, got $lines"; fi
}

test_invalid_event_rejected() {
    test_case "octo_event_emit rejects invalid event names"
    export OCTO_EVENT_LOG="$FIXTURE/invalid.jsonl"
    if ! octo_event_emit "provider status" provider=qwen; then test_pass
    else test_fail "invalid event name accepted"; fi
}

test_json_encoding_avoids_windows_python_alias() {
    test_case "JSON encoding does not probe a Windows Store python3 alias"
    local fake_bin="$FIXTURE/fake-python-bin"
    local marker="$FIXTURE/python3-was-invoked"
    mkdir -p "$fake_bin"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        ": > \"$marker\"" \
        'exit 99' > "$fake_bin/python3"
    chmod +x "$fake_bin/python3"

    local encoded
    encoded=$(PATH="$fake_bin:$PATH" _octo_json_string 'quote " and slash \\')
    if [[ ! -e "$marker" ]] && printf '%s\n' "$encoded" | jq -e . >/dev/null 2>&1; then
        test_pass
    else
        test_fail "event JSON encoding invoked the python3 App Execution Alias"
    fi
}

test_event_encoding_avoids_per_field_shell_forks() {
    test_case "octo_event_emit avoids Windows-hot-path command substitutions"
    if grep -Eq '\$\((_octo_json_string|octo_event_log_path|dirname)' "$PROJECT_ROOT/scripts/lib/events.sh"; then
        test_fail "event serialization still forks helpers on its Windows hot path"
    else
        test_pass
    fi
}

test_stale_event_lock_recovered() {
    test_case "octo_event_emit automatically reclaims an abandoned event lock"
    export OCTO_EVENT_LOG="$FIXTURE/stale-lock-events.jsonl"
    local lockdir="${OCTO_EVENT_LOG}.lock"
    mkdir -p "$lockdir"
    touch -d '5 minutes ago' "$lockdir"

    OCTO_EVENT_LOCK_STALE_SECONDS=1 octo_event_emit "lock.recovered" result=pass
    if [[ ! -d "$lockdir" ]] && grep -q '"event":"lock.recovered"' "$OCTO_EVENT_LOG"; then
        test_pass
    else
        test_fail "stale event lock remained after emit"
    fi
}

test_check_providers_event_hook() {
    test_case "check-providers emits provider.status events when enabled"
    export OCTO_EVENT_LOG="$FIXTURE/providers.jsonl"
    bash "$PROJECT_ROOT/scripts/helpers/check-providers.sh" >/dev/null
    if grep -q '"event":"provider.status"' "$OCTO_EVENT_LOG" && \
       grep -q '"provider"' "$OCTO_EVENT_LOG"; then
        test_pass
    else
        test_fail "provider.status event not found"
    fi
}

test_concurrent_emit_no_clobber() {
    test_case "concurrent emits never tear lines or get clobbered by trim (oco-7dk)"
    export OCTO_EVENT_LOG="$FIXTURE/concurrent.jsonl"
    export OCTO_EVENT_MAX_LINES=50
    : > "$OCTO_EVENT_LOG"
    local workers=12 iterations=60
    case "$(uname -s 2>/dev/null || true)" in
        MINGW*|MSYS*|CYGWIN*) workers=4; iterations=20 ;;
    esac
    local p
    for p in $(seq 1 "$workers"); do
        ( for i in $(seq 1 "$iterations"); do octo_event_emit "stress.test" proc="$p" seq="$i"; done ) &
    done
    wait
    unset OCTO_EVENT_MAX_LINES

    local lines
    lines="$(wc -l < "$OCTO_EVENT_LOG" | tr -d ' ')"
    if [[ "$lines" -gt 50 ]]; then
        test_fail "trim under concurrency left $lines lines (> 50 cap)"
        return
    fi

    # Every surviving line must be a complete, valid record — a torn line proves
    # an append was clobbered mid-write by a concurrent trim.
    if command -v jq >/dev/null 2>&1; then
        jq -e . < "$OCTO_EVENT_LOG" >/dev/null 2>&1 \
            || { test_fail "found torn/invalid JSON line under concurrency"; return; }
    else
        local bad
        bad="$(grep -cvE '^\{.*\}$' "$OCTO_EVENT_LOG" || true)"
        [[ "$bad" == "0" ]] || { test_fail "$bad torn lines under concurrency"; return; }
    fi
    test_pass
}

test_dispatch_lifecycle_events() {
    test_case "run_with_timeout emits dispatch.start/end/timeout lifecycle events"
    export OCTO_EVENT_LOG="$FIXTURE/lifecycle.jsonl"
    : > "$OCTO_EVENT_LOG"
    (
        log() { :; }  # heartbeat.sh logs on timeout; stub it for the unit test
        # shellcheck disable=SC1091
        source "$PROJECT_ROOT/scripts/lib/heartbeat.sh"
        run_with_timeout 5 true >/dev/null 2>&1 || true
        run_with_timeout 1 sleep 5 >/dev/null 2>&1 || true
    )
    if grep -q '"event":"dispatch.start"' "$OCTO_EVENT_LOG" && \
       grep -q '"event":"dispatch.end"' "$OCTO_EVENT_LOG" && \
       grep -q '"event":"dispatch.timeout"' "$OCTO_EVENT_LOG"; then
        test_pass
    else
        test_fail "missing one of dispatch.start/end/timeout in $(grep -oE '"event":"[^"]*"' "$OCTO_EVENT_LOG" | tr '\n' ' ')"
    fi
}

test_orchestrate_enables_telemetry_by_default() {
    test_case "orchestrate.sh enables OCTO_EVENT_LOG by default with an opt-out (oco-7db)"
    local orch="$PROJECT_ROOT/scripts/orchestrate.sh"
    if grep -q 'export OCTO_EVENT_LOG=.*RESULTS_DIR.*events.jsonl' "$orch" && \
       grep -q 'OCTO_EVENT_LOG.* == .off.' "$orch"; then
        test_pass
    else
        test_fail "orchestrate.sh must default OCTO_EVENT_LOG to RESULTS_DIR/events.jsonl and honor OCTO_EVENT_LOG=off"
    fi
}

test_circuit_breaker_events() {
    test_case "circuit-breaker open/closed/half-open lifecycle events emit (oco-aek)"
    local home="$FIXTURE/cb-home"; mkdir -p "$home"
    local log="$FIXTURE/cb.jsonl"
    (
        export HOME="$home" WORKSPACE_DIR="$home" OCTO_EVENT_LOG="$log"
        # shellcheck disable=SC1091
        source "$PROJECT_ROOT/scripts/lib/events.sh"
        # shellcheck disable=SC1091
        source "$PROJECT_ROOT/scripts/provider-router.sh" 2>/dev/null
        mkdir -p "$_PROVIDER_STATE_DIR"
        for _ in 1 2 3; do record_provider_failure cbtest "rate limit exceeded 429" >/dev/null 2>&1; done
        record_provider_success cbtest >/dev/null 2>&1
        echo "$(( $(date +%s) - 9999 ))" > "$_PROVIDER_STATE_DIR/cbtest.cooldown"
        is_provider_available cbtest >/dev/null 2>&1
    )
    if grep -q '"event":"circuit-breaker.open"' "$log" 2>/dev/null && \
       grep -q '"event":"circuit-breaker.closed"' "$log" 2>/dev/null && \
       grep -q '"event":"circuit-breaker.half-open"' "$log" 2>/dev/null; then
        test_pass
    else
        test_fail "missing circuit-breaker events: $(grep -oE '"event":"circuit-breaker[^"]*"' "$log" 2>/dev/null | tr '\n' ' ')"
    fi
}

test_provider_selected_event_wired() {
    test_case "spawn.sh emits provider.selected after the circuit check (oco-aek)"
    grep -q 'octo_event_emit "provider.selected"' "$PROJECT_ROOT/scripts/lib/spawn.sh" \
        && test_pass || test_fail "spawn.sh missing provider.selected emit"
}

test_no_log_when_disabled
test_emit_jsonl_event
test_auto_log_path
test_trim_event_log
test_invalid_event_rejected
test_json_encoding_avoids_windows_python_alias
test_event_encoding_avoids_per_field_shell_forks
test_stale_event_lock_recovered
test_check_providers_event_hook
test_concurrent_emit_no_clobber
test_dispatch_lifecycle_events
test_orchestrate_enables_telemetry_by_default

test_circuit_breaker_events
test_provider_selected_event_wired

test_summary
