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

    if command -v python3 >/dev/null 2>&1; then
        python3 - "$OCTO_EVENT_LOG" <<'PY' || { test_fail "event JSON did not parse"; return; }
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    row = json.loads(fh.readline())

assert row["event"] == "provider.status"
assert row["source"] == "unit-test"
assert row["session_id"] == "session-1"
assert row["attributes"]["provider"] == "qwen"
assert row["attributes"]["status"] == "degraded"
PY
    else
        grep -q '"event":"provider.status"' "$OCTO_EVENT_LOG" || { test_fail "event name missing"; return; }
    fi
    test_pass
}

test_stale_lock_recovery() {
    test_case "event locks recover a dead stale owner without stealing a live lock"
    local target="$FIXTURE/stale-event" lockdir="$FIXTURE/stale-event.lock"
    mkdir -p "$lockdir"
    printf '99999999\n' > "$lockdir/pid"
    printf '%s\n' "$(( $(date +%s) - 60 ))" > "$lockdir/ts"
    if ! OCTO_EVENT_LOCK_STALE_SECS=1 _octo_event_lock "$target"; then
        test_fail "dead stale lock was not reclaimed"
        return
    fi
    _octo_event_unlock "$target"

    mkdir -p "$lockdir"
    printf '%s\n' "$$" > "$lockdir/pid"
    printf '%s\n' "$(( $(date +%s) - 60 ))" > "$lockdir/ts"
    if OCTO_EVENT_LOCK_STALE_SECS=1 _octo_event_lock "$target"; then
        _octo_event_unlock "$target"
        test_fail "live stale-looking lock was stolen"
        return
    fi
    rm -f "$lockdir/pid" "$lockdir/ts"
    rmdir "$lockdir"
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
    local p
    for p in $(seq 1 12); do
        ( for i in $(seq 1 60); do octo_event_emit "stress.test" proc="$p" seq="$i"; done ) &
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
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$OCTO_EVENT_LOG" <<'PY' || { test_fail "found torn/invalid JSON line under concurrency"; return; }
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    for line in fh:
        if line.strip():
            json.loads(line)
PY
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

test_json_escaping_round_trips() {
    test_case "attribute values survive JSON escaping (fast path + control chars)"
    local log="$TEST_TMP_DIR/escaping.jsonl"
    rm -f "$log" "$log.lock"
    OCTO_EVENT_LOG="$log" octo_event_emit "escape.test" \
        plain="hello world" \
        quote='he said "hi"' \
        backslash='a\b' \
        tabbed="$(printf 'a\tb')" \
        unicode="café"

    if ! python3 -c "
import json,sys
line = open('$log').readline()
rec = json.loads(line)
a = rec['attributes']
assert a['plain'] == 'hello world', a['plain']
assert a['quote'] == 'he said \"hi\"', a['quote']
assert a['backslash'] == 'a\\\\b', a['backslash']
assert a['tabbed'] == 'a\tb', repr(a['tabbed'])
assert a['unicode'] == 'café', a['unicode']
" 2>"$TEST_TMP_DIR/escaping.err"; then
        test_fail "escaped attributes did not round-trip: $(cat "$TEST_TMP_DIR/escaping.err")"
        return
    fi
    test_pass
}

test_review_finding_events() {
    test_case "review.finding emits once per structured finding and never twice (oco-aek)"
    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/scripts/lib/review.sh" 2>/dev/null || true
    if ! declare -f review_emit_finding_events >/dev/null 2>&1; then
        test_fail "review_emit_finding_events is not defined"
        return
    fi
    local log="$TEST_TMP_DIR/review-findings-events.jsonl"
    local ff="$TEST_TMP_DIR/rf.json"
    rm -f "$log" "$log.lock" "$ff" "$ff.events-emitted"
    cat > "$ff" <<'JSON'
{"findings":[{"severity":"normal","file":"a.sh","line":12,"title":"Missing null check","category":"logic","confidence":0.9,"detail":"secret detail"},
             {"severity":"nit","file":"b.sh","line":3,"title":"Style","category":"style","confidence":0.4,"detail":"x"}]}
JSON
    OCTO_EVENT_LOG="$log" review_emit_finding_events "$ff"
    # render_terminal_report also runs on the inline-comment fallback path, so a
    # second pass over the same findings file must not double-count.
    OCTO_EVENT_LOG="$log" review_emit_finding_events "$ff"

    local n
    n=$(grep -c '"event":"review.finding"' "$log" 2>/dev/null | tr -d ' ')
    if [[ "$n" != "2" ]]; then
        test_fail "expected 2 review.finding events, got ${n:-0}"
        return
    fi
    if grep -q 'secret detail' "$log" 2>/dev/null; then
        test_fail "finding detail text leaked into the event stream"
        return
    fi
    test_pass
}

test_provider_selected_event_wired() {
    test_case "spawn.sh emits provider.selected after the circuit check (oco-aek)"
    grep -q 'octo_event_emit "provider.selected"' "$PROJECT_ROOT/scripts/lib/spawn.sh" \
        && test_pass || test_fail "spawn.sh missing provider.selected emit"
}

test_no_log_when_disabled
test_emit_jsonl_event
test_stale_lock_recovery
test_auto_log_path
test_trim_event_log
test_invalid_event_rejected
test_check_providers_event_hook
test_concurrent_emit_no_clobber
test_dispatch_lifecycle_events
test_orchestrate_enables_telemetry_by_default

test_json_escaping_round_trips
test_review_finding_events
test_circuit_breaker_events
test_provider_selected_event_wired

test_summary
