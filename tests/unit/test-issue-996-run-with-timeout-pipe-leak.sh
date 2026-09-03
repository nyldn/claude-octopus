#!/usr/bin/env bash
# tests/unit/test-issue-996-run-with-timeout-pipe-leak.sh
# Regression test for #996: the in-process fallback of run_with_timeout must not
# let its watchdog's orphaned `sleep` hold the caller's stdout. spawn_agent pipes
# run_with_timeout into `tee`; a held pipe never sees EOF, so the whole review
# blocks for the FULL timeout even though the command already produced output.
# The shell-function path (perplexity_execute, openrouter_execute) always takes
# this fallback, regardless of whether gtimeout/timeout is installed.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
log() { :; }
source "$PROJECT_ROOT/scripts/lib/heartbeat.sh"

test_suite "run_with_timeout pipe leak (#996)"

test_case "shell-function dispatch does not leave a downstream pipe blocked"
# A shell function forces the in-process fallback. The probe sleeps briefly so the
# watchdog subshell has certainly spawned its own `sleep` child before the command
# returns — that is the fault window; killing the watchdog then orphans that sleep.
# Timeout is 6s: if the orphan is holding the caller's pipe, `tee` stays blocked
# until 6s; the fix lets the pipeline finish about when the probe does (~1s). The
# poll ceiling (3.5s) sits between the two, and any orphan self-terminates by 6s.
outfile="$TEST_TMP_DIR/pipe-996.out"
donefile="$TEST_TMP_DIR/pipe-996.done"
rm -f "$outfile" "$donefile"
_octo_996_probe() { sleep 1; printf 'PROBE_OUTPUT\n'; }
( printf '' | run_with_timeout 6 _octo_996_probe | tee "$outfile" >/dev/null; echo done > "$donefile" ) &
pipeline_pid=$!

# Bounded poll (no fixed long wait): break the instant the pipeline completes, so
# a slow runner cannot flake it. Ceiling (3s) sits between near-instant (fixed)
# and the 5s block (bug), so the two outcomes are unambiguous.
completed=false
for _ in $(seq 1 35); do
    if [[ -f "$donefile" ]]; then completed=true; break; fi
    sleep 0.1
done

if [[ "$completed" == "true" ]] && [[ "$(cat "$outfile" 2>/dev/null)" == "PROBE_OUTPUT" ]]; then
    test_pass
else
    test_fail "pipeline still blocked after 3.5s — watchdog sleep is holding the caller's stdout (#996)"
fi

# Best-effort cleanup of the pipeline; any orphaned watchdog sleep self-clears.
kill "$pipeline_pid" 2>/dev/null || true
wait "$pipeline_pid" 2>/dev/null || true

test_summary
