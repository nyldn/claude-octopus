#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Event monitor HUD (oco-8gw)"

# shellcheck disable=SC1091
source "$PROJECT_ROOT/scripts/lib/event-monitor.sh"

FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT

_dispatch_end='{"timestamp":"2026-06-15T01:00:00Z","event":"dispatch.end","attributes":{"command":"codex","outcome":"ok","exit_code":"0"}}'
_provider_status='{"timestamp":"2026-06-15T01:00:01Z","event":"provider.status","attributes":{"provider":"gemini","status":"degraded"}}'

test_format_parses_event() {
    test_case "octo_hud_format_line renders event name + key attributes"
    local out
    out="$(octo_hud_format_line "$_dispatch_end")"
    if [[ "$out" == *dispatch.end* && "$out" == *codex* && "$out" == *outcome=ok* ]]; then
        test_pass
    else test_fail "unexpected format: $out"; fi
}

test_format_provider_status() {
    test_case "octo_hud_format_line surfaces provider + status"
    local out
    out="$(octo_hud_format_line "$_provider_status")"
    if [[ "$out" == *provider=gemini* && "$out" == *status=degraded* ]]; then
        test_pass
    else test_fail "unexpected: $out"; fi
}

test_malformed_skipped() {
    test_case "malformed / blank input is skipped without error"
    local rc1=0 rc2=0 rc3=0
    octo_hud_format_line "not json at all" >/dev/null 2>&1 || rc1=$?
    octo_hud_format_line "" >/dev/null 2>&1 || rc2=$?
    octo_hud_format_line "{}" >/dev/null 2>&1 || rc3=$?
    # All should return non-zero (nothing rendered) and not crash the caller.
    if [[ "$rc1" -ne 0 && "$rc2" -ne 0 && "$rc3" -ne 0 ]]; then test_pass
    else test_fail "expected non-zero for malformed (got $rc1/$rc2/$rc3)"; fi
}

test_degrades_when_not_tty() {
    test_case "octo_hud_run is a no-op when stdout is not a TTY"
    local f="$FIXTURE/ev.jsonl"; printf '%s\n' "$_dispatch_end" > "$f"
    # stdout is captured (a pipe, not a TTY) → expect no output, clean exit.
    local out rc
    out="$(octo_hud_run "$f" 2>/dev/null)"; rc=$?
    if [[ -z "$out" && "$rc" -eq 0 ]]; then test_pass
    else test_fail "expected no output + rc=0 in non-TTY (rc=$rc, out='${out:0:40}')"; fi
}

test_format_parses_event
test_format_provider_status
test_malformed_skipped
test_degrades_when_not_tty

test_summary
