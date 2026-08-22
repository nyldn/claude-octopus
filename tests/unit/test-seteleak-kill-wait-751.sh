#!/usr/bin/env bash
# tests/unit/test-seteleak-kill-wait-751.sh
# Regression coverage for #751: bare `kill`/`wait`/`pkill` on an
# already-reaped PID returns non-zero and, under `set -eo pipefail`
# (orchestrate.sh:6), aborts the enclosing function immediately after
# the signal/reap work already succeeded — same defect class as #738/#739.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "set -e status leaks on bare kill/wait/pkill (#751)"

# Sanity check: prove the general failure mode is real, independent of any
# specific file, before asserting the five sites are guarded against it.
test_bare_kill_wait_aborts_under_sete() {
    test_case "bare kill on an already-reaped PID aborts a set -e function before it completes"

    local out
    out=$(bash -c '
        set -e
        ( sleep 0.05 ) & m=$!
        wait "$m"
        kill "$m" 2>/dev/null
        echo REACHED-END
    ' 2>/dev/null || true)

    assert_not_contains "$out" "REACHED-END" \
        "expected the unguarded reproduction to abort before REACHED-END (proves the defect is real)" || return
    test_pass
}

test_guarded_kill_wait_survives_sete() {
    test_case "the || true guard pattern used in the fix prevents the abort"

    local out
    out=$(bash -c '
        set -e
        ( sleep 0.05 ) & m=$!
        wait "$m" 2>/dev/null || true
        kill "$m" 2>/dev/null || true
        echo REACHED-END
    ')

    assert_contains "$out" "REACHED-END" \
        "expected the guarded reproduction to reach the end under set -e" || return
    test_pass
}

# workflows.sh:692-693 — synthesis monitor kill/wait guard (probe_discover()).
# probe_discover() has too much external state (provider dispatch, run
# artifacts) to exercise directly in a unit test; assert statically that the
# specific lines carry the guard, same as the sibling assertions below.
test_workflows_synthesis_monitor_guarded() {
    test_case "workflows.sh: synthesis_monitor_pid kill/wait guarded with || true"

    local file="$PROJECT_ROOT/scripts/lib/workflows.sh"
    local snippet
    snippet=$(grep -A2 'kill "\$synthesis_monitor_pid"' "$file")

    assert_contains "$snippet" 'kill "$synthesis_monitor_pid" 2>/dev/null || true' \
        "kill on synthesis_monitor_pid must be guarded" || return
    assert_contains "$snippet" 'wait "$synthesis_monitor_pid" 2>/dev/null || true' \
        "wait on synthesis_monitor_pid must be guarded" || return
    test_pass
}

# heartbeat.sh:197/200 — run_with_timeout()'s TERM-then-KILL escalation.
# This one is directly callable and lets us reproduce the exact race from
# the issue: the wrapped command finishes before the monitor's first signal
# fires, so kill -TERM targets an already-dead PID and must not skip the
# pkill/KILL escalation lines that follow it in the same subshell.
test_heartbeat_run_with_timeout_survives_early_exit_race() {
    test_case "heartbeat.sh: run_with_timeout completes cleanup when the target exits before the monitor's first signal"

    local out
    out=$(
        bash -c '
            set -eo pipefail
            source "'"$PROJECT_ROOT"'/scripts/lib/heartbeat.sh"
            fast_ok() { return 0; }
            # timeout_secs=1 with an instantly-returning command guarantees
            # the monitor subshell fires kill -TERM against a PID that is
            # already gone by the time it runs. Capture via `|| rc=$?`
            # (not a bare call) so *this test harness* does not itself
            # trip set -e on a non-zero return — same idiom as the fix.
            rc=0
            run_with_timeout 1 fast_ok || rc=$?
            echo "RC=$rc"
            echo REACHED-END
        ' 2>&1
    ) || true

    assert_contains "$out" "REACHED-END" \
        "run_with_timeout must not abort under set -e when the monitor's kill -TERM races an exited target" || return
    assert_contains "$out" "RC=0" \
        "run_with_timeout must still report the wrapped command's real exit code" || return
    test_pass
}

test_heartbeat_kill_lines_guarded() {
    test_case "heartbeat.sh: monitor's kill -TERM/-KILL lines guarded with || true"

    local file="$PROJECT_ROOT/scripts/lib/heartbeat.sh"
    local snippet
    if ! snippet=$(grep -m1 -A12 -B2 'kill -TERM "\$cmd_pid"' "$file"); then
        test_fail "could not locate the cmd_pid TERM/KILL cleanup block in heartbeat.sh"
        return
    fi

    assert_contains "$snippet" 'kill -TERM "$cmd_pid" 2>/dev/null || true' \
        "kill -TERM on cmd_pid must be guarded" || return
    assert_contains "$snippet" 'pkill -TERM -P "$cmd_pid" 2>/dev/null || true' \
        "pkill -TERM on cmd_pid children must be guarded" || return
    assert_contains "$snippet" 'kill -KILL "$cmd_pid" 2>/dev/null || true' \
        "kill -KILL on cmd_pid must be guarded" || return
    assert_contains "$snippet" 'pkill -KILL -P "$cmd_pid" 2>/dev/null || true' \
        "pkill -KILL on cmd_pid children must be guarded" || return
    test_pass
}

# cursor-agent.sh:55-56 — _cursor_agent_run_with_timeout()'s fallback path.
# Unlike the other four sites, `wait "$cmd_pid"` here feeds `exit_code=$?`:
# a blind `|| true` would silently zero out the real exit code, so the fix
# uses `exit_code=0; wait ... || exit_code=$?` instead. Assert both halves:
# no abort under set -e, and the captured code is still correct.
test_cursor_agent_preserves_exit_code_and_survives_sete() {
    test_case "cursor-agent.sh: fallback wait preserves the wrapped command's exit code without aborting under set -e"

    local out
    out=$(
        bash -c '
            set -eo pipefail
            source "'"$PROJECT_ROOT"'/scripts/lib/cursor-agent.sh"
            fails_with_7() { return 7; }
            # Force the in-process fallback (skip gtimeout/timeout) by
            # emptying PATH so neither resolves; everything the fallback
            # itself needs is a builtin, a shell function, or an absolute
            # path (/bin/sleep, /bin/rm), matching the code path the fix targets.
            # Capture via `|| rc=$?` so this test harness does not itself
            # trip set -e on the (expected, non-zero) return value.
            rc=0
            PATH="" _cursor_agent_run_with_timeout 0.2 fails_with_7 </dev/null || rc=$?
            echo "RC=$rc"
            echo REACHED-END
        ' 2>&1
    ) || true

    assert_contains "$out" "REACHED-END" \
        "_cursor_agent_run_with_timeout must not abort under set -e" || return
    assert_contains "$out" "RC=7" \
        "_cursor_agent_run_with_timeout must still return the wrapped command's real exit code (7), not silently become 0 (proves exit_code=0; wait ... || exit_code=\$? preserves the value, unlike a blind || true)" || return
    test_pass
}

test_bare_kill_wait_aborts_under_sete
test_guarded_kill_wait_survives_sete
test_workflows_synthesis_monitor_guarded
test_heartbeat_run_with_timeout_survives_early_exit_race
test_heartbeat_kill_lines_guarded
test_cursor_agent_preserves_exit_code_and_survives_sete

test_summary
