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

# ── end-to-end wiring: spawn_agent_capture_pid actually uses the derived
# default (not just computing and discarding it), exercised at a small, fast
# timescale so the suite stays quick ──────────────────────────────────────

test_case "an explicit OCTOPUS_SPAWN_PID_WAIT_ATTEMPTS override still takes priority over the derived default"
compute_dynamic_timeout() { echo 900; }  # would derive a huge default if it were consulted
spawn_agent() { sleep 0.2; printf '%s\n' 555555; }
export "OCTOPUS_SPAWN_PID_WAIT_ATTEMPTS=20"
pid=$(spawn_agent_capture_pid codex prompt override-task implementer tangle)
unset OCTOPUS_SPAWN_PID_WAIT_ATTEMPTS
unset -f compute_dynamic_timeout
if [[ "$pid" == "555555" ]]; then
    test_pass
else
    test_fail "expected explicit override to still take priority, got: ${pid:-empty}"
fi

test_case "spawn_agent_capture_pid actually uses the derived default window, not just OCTOPUS_SPAWN_PID_WAIT_ATTEMPTS"
# No explicit OCTOPUS_SPAWN_PID_WAIT_ATTEMPTS override here: this exercises the
# real default-derivation path end to end, scaled down (compute_dynamic_timeout
# stubbed to 6s instead of a realistic 180-900s) so the test finishes fast:
# (6*5+60)*10 = 900 attempts, a ~90s ceiling that a 0.5s delayed PID clears
# almost immediately.
unset OCTOPUS_SPAWN_PID_WAIT_ATTEMPTS 2>/dev/null || true
compute_dynamic_timeout() { echo 6; }
spawn_agent() { sleep 0.5; printf '%s\n' 666666; }
pid=$(spawn_agent_capture_pid codex prompt default-task implementer tangle 2>/dev/null)
unset -f compute_dynamic_timeout
if [[ "$pid" == "666666" ]]; then
    test_pass
else
    test_fail "expected the derived default window to capture a delayed provider PID, got: ${pid:-empty}"
fi

test_summary
