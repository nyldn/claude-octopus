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

test_no_log_when_disabled
test_emit_jsonl_event
test_auto_log_path
test_trim_event_log
test_invalid_event_rejected
test_check_providers_event_hook
test_concurrent_emit_no_clobber
test_dispatch_lifecycle_events

test_summary
