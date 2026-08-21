#!/usr/bin/env bash
# Regression for #947: spawn_agent_capture_pid's PID-wait window must be
# derived from the same per-candidate timeout the summarizer preflight chain
# (dispatch.sh's summarize_then_dispatch -> agent-sync.sh's run_agent_sync ->
# heartbeat.sh's compute_dynamic_timeout) actually uses, including the
# OCTOPUS_AGENT_TIMEOUT override that chain honors. Before this fix the
# window was a fixed 1200-attempt/120s default that a single oversized-prompt
# summarization call could already exceed (standard dynamic timeout with the
# leak-safe boost is 180s), and that OCTOPUS_AGENT_TIMEOUT made worse instead
# of better: raising the inner summarizer budget to help a slow provider
# guaranteed the outer window abandoned its seat first.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "PID-wait window derivation (#947)"

# Load only the helpers under test so the fixture controls spawn_agent,
# compute_dynamic_timeout, and log — mirrors tests/unit/test-spawn-agent-capture-pid.sh.
eval "$(sed -n '/^_octopus_prune_task_id_reservations() {/,/^}/p' "$PROJECT_ROOT/scripts/lib/spawn.sh")"
eval "$(sed -n '/^_octopus_next_spawn_task_id() {/,/^}/p' "$PROJECT_ROOT/scripts/lib/spawn.sh")"
eval "$(sed -n '/^_octopus_spawn_pid_wait_default_attempts() {/,/^}/p' "$PROJECT_ROOT/scripts/lib/spawn.sh")"
eval "$(sed -n '/^spawn_agent_capture_pid() {/,/^}/p' "$PROJECT_ROOT/scripts/lib/spawn.sh")"

export WORKSPACE_DIR="$TEST_TMP_DIR"
log() { :; }

# ── static guards: the exact buggy fixed-window shape must be gone ──────────

test_case "PID-wait window is no longer a bare hardcoded 1200 default"
if grep -q 'OCTOPUS_SPAWN_PID_WAIT_ATTEMPTS:-1200' "$PROJECT_ROOT/scripts/lib/spawn.sh"; then
    test_fail "spawn.sh still hardcodes the fixed 120s (1200-attempt) window that #947 outran"
else
    test_pass
fi

test_case "spawn_agent_capture_pid derives its default window via the named helper"
if grep -q '_octopus_spawn_pid_wait_default_attempts' "$PROJECT_ROOT/scripts/lib/spawn.sh"; then
    test_pass
else
    test_fail "expected spawn_agent_capture_pid to derive its default window via a named helper"
fi

# ── pure formula tests: no timing involved ───────────────────────────────────

test_case "falls back to a fixed 360s/candidate estimate when heartbeat.sh isn't sourced"
unset -f compute_dynamic_timeout 2>/dev/null || true
result=$(_octopus_spawn_pid_wait_default_attempts)
# (360s * 5 worst-case candidates + 60s margin) * 10 attempts/sec = 18600
if [[ "$result" == "18600" ]]; then
    test_pass
else
    test_fail "expected 18600 attempts (360s/candidate fallback), got: $result"
fi

test_case "scales with compute_dynamic_timeout's budget the same way OCTOPUS_AGENT_TIMEOUT does"
# This is the exact reported scenario: OCTOPUS_AGENT_TIMEOUT=900 makes
# compute_dynamic_timeout return 900 unconditionally (its env override is
# checked before task_type), regardless of what task_type spawn_agent_capture_pid
# would otherwise have guessed.
compute_dynamic_timeout() { echo 900; }
result=$(_octopus_spawn_pid_wait_default_attempts)
# (900 * 5 + 60) * 10 = 45600
if [[ "$result" == "45600" ]]; then
    test_pass
else
    test_fail "expected 45600 attempts for a 900s dynamic timeout, got: $result"
fi
unset -f compute_dynamic_timeout

test_case "derived window exceeds the old fixed 1200-attempt default once a single candidate alone would have outrun it"
# Regression scenario from the report: a "standard" dynamic timeout with the
# leak-safe boost (lib/heartbeat.sh: 120+60=180s) already exceeds the old
# fixed 120s window on the FIRST summarizer candidate alone.
compute_dynamic_timeout() { echo 180; }
result=$(_octopus_spawn_pid_wait_default_attempts)
if [[ "$result" -gt 1200 ]]; then
    test_pass
else
    test_fail "expected derived window > 1200 (old fixed default) for a 180s candidate budget, got: $result"
fi
unset -f compute_dynamic_timeout

test_case "never derives a window smaller than the historical 1200-attempt default"
compute_dynamic_timeout() { echo 0; }
result=$(_octopus_spawn_pid_wait_default_attempts)
if [[ "$result" == "1200" ]]; then
    test_pass
else
    test_fail "expected floor of 1200 attempts for a 0s dynamic timeout, got: $result"
fi
unset -f compute_dynamic_timeout

test_case "ignores a non-numeric compute_dynamic_timeout result instead of breaking arithmetic"
compute_dynamic_timeout() { echo "not-a-number"; }
result=$(_octopus_spawn_pid_wait_default_attempts)
if [[ "$result" == "18600" ]]; then
    test_pass
else
    test_fail "expected the 360s/candidate fallback for a non-numeric result, got: $result"
fi
unset -f compute_dynamic_timeout

test_case "treats a leading-zero OCTOPUS_AGENT_TIMEOUT override as decimal, not octal"
# compute_dynamic_timeout echoes OCTOPUS_AGENT_TIMEOUT back verbatim when it's
# set (lib/heartbeat.sh), so a zero-padded override like "0900" reaches this
# function unmodified. Bash arithmetic treats a leading 0 as an octal prefix;
# "0900" contains an invalid octal digit (9) and would abort the arithmetic
# entirely without the 10# base-10 forcing, silently collapsing the derived
# window back down to the 1200-attempt floor it exists to move past.
compute_dynamic_timeout() { echo "0900"; }
result=$(_octopus_spawn_pid_wait_default_attempts)
if [[ "$result" == "45600" ]]; then
    test_pass
else
    test_fail "expected 45600 attempts (decimal 900s/candidate), got: $result"
fi
unset -f compute_dynamic_timeout

test_case "treats a leading-zero value with only valid-octal digits as decimal, not octal"
# A subtler variant of the above: "0600" is syntactically valid octal (all
# digits 0-6), so this one wouldn't error — it would silently compute the
# WRONG (smaller) window instead of failing loudly. Octal 0600 = decimal 384;
# if this regresses to plain arithmetic, attempts would come out as (384*5+60)*10
# = 19800 instead of the correct decimal (600*5+60)*10 = 30600.
compute_dynamic_timeout() { echo "0600"; }
result=$(_octopus_spawn_pid_wait_default_attempts)
if [[ "$result" == "30600" ]]; then
    test_pass
else
    test_fail "expected 30600 attempts (decimal 600s/candidate), got: $result (octal misparse gives 19800)"
fi
unset -f compute_dynamic_timeout

# ── end-to-end wiring: spawn_agent_capture_pid actually uses the derived
# default (not just computing and discarding it), exercised at a small, fast
# timescale so the suite stays quick ──────────────────────────────────────

test_case "an explicit OCTOPUS_SPAWN_PID_WAIT_ATTEMPTS override still takes priority over the derived default"
compute_dynamic_timeout() { echo 900; }  # would derive a huge default if it were consulted
spawn_agent() { sleep 0.2; printf '%s\n' 555555; }
export "OCTOPUS_SPAWN_PID_WAIT_ATTEMPTS=20"
pid=$(spawn_agent_capture_pid codex prompt override-task implementer tangle) || true
unset OCTOPUS_SPAWN_PID_WAIT_ATTEMPTS
unset -f compute_dynamic_timeout
if [[ "$pid" == "555555" ]]; then
    test_pass
else
    test_fail "expected explicit override to still take priority, got: ${pid:-empty}"
fi

test_case "spawn_agent_capture_pid actually uses the derived default window, not just OCTOPUS_SPAWN_PID_WAIT_ATTEMPTS"
# No explicit OCTOPUS_SPAWN_PID_WAIT_ATTEMPTS override here: this must fail
# if spawn_agent_capture_pid ignores the derived value and keeps the old
# hardcoded 1200-attempt/120s default. A prior version of this test stubbed
# compute_dynamic_timeout to 6s, which derives (6*5+60)*10 = 900 attempts —
# below the 1200 floor, so it silently floors back UP to 1200, the exact old
# default. That made the test pass identically whether or not the derived
# value was ever consulted. Here the stub (100s) derives (100*5+60)*10 = 5600
# attempts, clearly above 1200, and the simulated PID is timed to land only
# after 1500 real polling attempts (past where the old 1200-attempt cap would
# already have given up) but comfortably under the derived 5600-attempt cap.
#
# A wall-clock delay would need ~1500 * 0.1s = 150s at real speed, and scaling
# the loop's `sleep 0.1` down by a fixed factor turned out not to be portable:
# each iteration also forks `awk` and `kill -0`, whose process-spawn overhead
# dominates the loop's actual per-iteration cost (measured ~4ms/iteration in
# CI, independent of the sleep argument), so a fixed sleep-scaling factor
# doesn't reliably land the PID's arrival between the two attempt thresholds
# on every runner. Instead, `awk` — already called exactly once per loop
# iteration to check the PID file — is shadowed to also tick a counter file,
# giving an exact, timing-independent count of real loop iterations; the
# spawn_agent stub polls that same counter and only responds once it crosses
# the threshold, so the test is portable across however fast or slow a given
# CI runner executes each iteration.
unset OCTOPUS_SPAWN_PID_WAIT_ATTEMPTS 2>/dev/null || true
compute_dynamic_timeout() { echo 100; }
counter_file=$(mktemp "$TEST_TMP_DIR/attempt-counter.XXXXXX")
: >"$counter_file"
sleep() { :; }   # collapse the wait; only the *count* of attempts matters here
awk() { printf 'x' >>"$counter_file"; command awk "$@"; }
attempt_threshold=1500   # > the old 1200-attempt cap, < the derived 5600-attempt cap
spawn_agent() {
    local count=0
    while [[ "$count" -lt "$attempt_threshold" ]]; do
        command sleep 0.005   # `command` bypasses this test's no-op sleep shadow
        count=$(wc -c <"$counter_file" 2>/dev/null || echo 0)
    done
    printf '%s\n' 777777
}
pid=$(spawn_agent_capture_pid codex prompt counted-task implementer tangle 2>/dev/null) || true
unset -f compute_dynamic_timeout sleep awk spawn_agent
rm -f "$counter_file"
if [[ "$pid" == "777777" ]]; then
    test_pass
else
    test_fail "expected the derived (>1200-attempt) window to capture a PID that lands after $attempt_threshold polling attempts (past the old 1200-attempt/120s cap), got: ${pid:-empty}"
fi

test_summary
