#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Caller process-group preservation"
log() { :; }
source "$PROJECT_ROOT/scripts/lib/heartbeat.sh"

timeout_bin=""
if command -v gtimeout >/dev/null 2>&1; then
    timeout_bin=gtimeout
elif command -v timeout >/dev/null 2>&1; then
    timeout_bin=timeout
fi

test_case "run_with_timeout preserves caller process group when requested"
if [[ -n "$timeout_bin" ]]; then
    parent_pgid="$(ps -o pgid= -p $$ | tr -d ' ')"
    child_pgid="$(OCTOPUS_PRESERVE_CALLER_PROCESS_GROUP=true run_with_timeout 5 sh -c 'ps -o pgid= -p $$ | tr -d " "')"
    if [[ "$child_pgid" == "$parent_pgid" ]]; then
        test_pass
    else
        test_fail "expected child PGID $parent_pgid, got $child_pgid"
    fi
else
    test_skip "GNU timeout/gtimeout not available on this platform"
fi

test_case "preserve mode cleans up timed-out descendants"
if [[ -n "$timeout_bin" ]]; then
    tmpdir="$TEST_TMP_DIR/preserve-timeout"
    mkdir -p "$tmpdir"
    pidfile="$tmpdir/child.pid"
    if (
        export "OCTOPUS_PRESERVE_CALLER_PROCESS_GROUP=true"
        run_with_timeout 1 sh -c 'sleep 30 & echo "$!" > "$1"; wait' sh "$pidfile" >/dev/null 2>&1
    ); then
        status=0
    else
        status=$?
    fi
    child_pid="$(cat "$pidfile" 2>/dev/null || true)"
    sleep 0.3
    child_stat="$(ps -o stat= -p "$child_pid" 2>/dev/null | tr -d "[:space:]" || true)"
    if [[ -n "$child_stat" && "$child_stat" != Z* ]]; then
        kill -KILL "$child_pid" 2>/dev/null || true
        test_fail "descendant survived preserve-mode timeout: $child_pid (stat=$child_stat)"
    elif [[ "$status" -eq 124 || "$status" -eq 143 || "$status" -eq 137 ]]; then
        test_pass
    else
        test_fail "unexpected timeout status: $status"
    fi
else
    test_skip "GNU timeout/gtimeout not available on this platform"
fi

test_case "production and tests prefer gtimeout before timeout"
if grep -q '_run_with_timeout_preserving_process_group gtimeout' "$PROJECT_ROOT/scripts/lib/heartbeat.sh" \
   && grep -q '_run_with_timeout_preserving_process_group timeout' "$PROJECT_ROOT/scripts/lib/heartbeat.sh" \
   && grep -q 'command -v gtimeout' "$0" \
   && grep -q 'command -v timeout' "$0"; then
    test_pass
else
    test_fail "gtimeout/timeout preserve-mode paths are not covered"
fi

test_summary
