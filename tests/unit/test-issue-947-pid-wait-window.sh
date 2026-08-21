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
# value was ever consulted.
#
# A second version tried to prove the >1200 cap by having spawn_agent race a
# shared counter file against the outer loop (spawn_agent polling for a
# threshold tick count while the loop's shadowed `awk` wrote to the same
# file). That passed on Linux CI but failed on macOS CI (0s, empty pid) —
# two independently forked processes polling one file for a threshold is
# exactly the kind of cross-platform timing race this rewrite avoids.
#
# This version has no second process and no threshold race at all: the
# loop's own `sleep 0.1` — called exactly once per iteration, immediately
# before `((attempts++))` — is shadowed to a no-op that just ticks a counter
# file instead of waiting, so the loop spins to its true conclusion almost
# instantly. `spawn_agent` is a single background process that outlives that
# entire spin (a real, generously long sleep) and never writes a PID, so the
# loop is guaranteed to run until `attempts` naturally reaches `max_attempts`
# rather than exiting early via the pid-found or wrapper-died branches. The
# number of ticks left behind is then an exact, deterministic record of
# max_attempts: 5600 if the derived value from a 100s dynamic timeout was
# used, 1200 if the code regressed to the old hardcoded default.
unset OCTOPUS_SPAWN_PID_WAIT_ATTEMPTS 2>/dev/null || true
compute_dynamic_timeout() { echo 100; }   # derives (100*5+60)*10 = 5600 attempts
tick_file=$(mktemp "$TEST_TMP_DIR/sleep-ticks.XXXXXX")
: >"$tick_file"
sleep_pid_file=$(mktemp "$TEST_TMP_DIR/agent-sleep-pid.XXXXXX")
sleep() { printf 'x' >>"$tick_file"; }   # no real delay; each call just ticks the counter
spawn_agent() {
    # Outlives the loop's spin; never writes a PID. This is a ceiling, not a
    # target: the test's own runtime is bounded by how long the loop's 5600
    # iterations actually take (awk+kill overhead per iteration — a few
    # seconds locally, but CI runners vary), and spawn_agent_capture_pid
    # kills this early via the reaping below the moment the loop finishes.
    # It only needs to outlast whatever that takes; a short duration risks
    # the loop being cut off mid-spin on a slower runner, undercounting
    # tick_count and failing the assertion below for a reason that has
    # nothing to do with the code under test — so it errs generously long
    # rather than being tuned tightly to an environment-dependent number.
    #
    # `command sleep` (not `wait`ed on by spawn_agent_capture_pid's own
    # error-path kill, which only reaches this function's own wrapper PID,
    # not its child) would otherwise leak a real orphaned sleep process for
    # the rest of its duration once the loop gives up — backgrounding it
    # here and recording its own PID lets the test reap it explicitly below
    # instead.
    command sleep 600 &
    echo $! >"$sleep_pid_file"
    wait
}
pid=$(spawn_agent_capture_pid codex prompt counted-task implementer tangle 2>/dev/null) || true
unset -f compute_dynamic_timeout sleep spawn_agent
tick_count=$(wc -c <"$tick_file" 2>/dev/null || echo 0)
if [[ -f "$sleep_pid_file" ]]; then
    kill "$(cat "$sleep_pid_file")" 2>/dev/null || true
fi
rm -f "$tick_file" "$sleep_pid_file"
if [[ -z "$pid" && "$tick_count" -eq 5600 ]]; then
    test_pass
else
    test_fail "expected an empty pid and exactly 5600 polling attempts (the derived window; 1200 would mean the old hardcoded default is still in effect), got pid='${pid:-empty}' tick_count=$tick_count"
fi

test_case "preflight_candidates in spawn.sh stays in lockstep with dispatch.sh's summarizer chain length"
# #948 review: preflight_candidates=5 (used above) hardcodes the assumption
# that summarize_then_dispatch's candidate chain in dispatch.sh is "optional
# OCTOPUS_OVERSIZE_SUMMARIZER + 4 fixed candidates" = worst case 5. Nothing
# ties the two files together — if dispatch.sh's fixed list grows, this
# constant silently under-counts again, quietly reintroducing the exact
# #947 abandonment bug this PR fixes, with no test failure to flag the
# drift. This fails the moment that happens instead of staying silent.
spawn_preflight_candidates=$(grep -m1 'local preflight_candidates=' "$PROJECT_ROOT/scripts/lib/spawn.sh" | grep -o '[0-9]\+') || spawn_preflight_candidates=""
dispatch_fixed_line=$(grep -m1 'candidates+=("agy" "codex-mini" "claude-sonnet" "codex")' "$PROJECT_ROOT/scripts/lib/dispatch.sh") || dispatch_fixed_line=""
dispatch_fixed_count=$(grep -o '"[^"]*"' <<<"$dispatch_fixed_line" | wc -l | tr -d ' ') || dispatch_fixed_count=0
# +1 for the optional OCTOPUS_OVERSIZE_SUMMARIZER slot prepended ahead of the fixed chain.
dispatch_worst_case=$((dispatch_fixed_count + 1))
if [[ -n "$dispatch_fixed_line" && -n "$spawn_preflight_candidates" && "$spawn_preflight_candidates" == "$dispatch_worst_case" ]]; then
    test_pass
else
    test_fail "spawn.sh's preflight_candidates (${spawn_preflight_candidates:-not found}) no longer matches dispatch.sh's worst-case summarizer chain length ($dispatch_worst_case, from $dispatch_fixed_count fixed candidates + 1 optional, fixed-candidate line found: $([[ -n "$dispatch_fixed_line" ]] && echo yes || echo no)) — update _octopus_spawn_pid_wait_default_attempts's preflight_candidates in scripts/lib/spawn.sh to match"
fi

test_case "fallback 360s/candidate estimate in spawn.sh stays in lockstep with heartbeat.sh's complex-case formula"
# #948 review: the 360s fallback used when heartbeat.sh isn't sourced (an
# optional dep of spawn.sh, e.g. a test harness loading only this file)
# approximates compute_dynamic_timeout's worst-case "complex" task-type
# formula: 300 + leak_safe_boost, boost=60. Nothing ties the two files
# together the way the lockstep test above does for preflight_candidates —
# if heartbeat.sh's constants change, this fallback silently goes stale
# with no failing test to flag it.
heartbeat_complex_base=$(grep -F -A1 'full|premium|complex)' "$PROJECT_ROOT/scripts/lib/heartbeat.sh" | grep -o '[0-9]\+ + leak_safe_boost' | grep -o '^[0-9]\+') || heartbeat_complex_base=""
heartbeat_leak_safe_boost=$(grep -m1 'leak_safe_boost=60' "$PROJECT_ROOT/scripts/lib/heartbeat.sh" | grep -o '[0-9]\+') || heartbeat_leak_safe_boost=""
spawn_fallback_secs=$(grep -m1 'local preflight_secs=' "$PROJECT_ROOT/scripts/lib/spawn.sh" | grep -o '[0-9]\+') || spawn_fallback_secs=""
if [[ -n "$heartbeat_complex_base" && -n "$heartbeat_leak_safe_boost" ]]; then
    heartbeat_worst_case=$((heartbeat_complex_base + heartbeat_leak_safe_boost))
else
    heartbeat_worst_case=""
fi
if [[ -n "$heartbeat_worst_case" && -n "$spawn_fallback_secs" && "$spawn_fallback_secs" == "$heartbeat_worst_case" ]]; then
    test_pass
else
    test_fail "spawn.sh's 360s fallback (${spawn_fallback_secs:-not found}) no longer matches heartbeat.sh's worst-case complex-task formula (${heartbeat_worst_case:-not found}, from base=${heartbeat_complex_base:-not found} + boost=${heartbeat_leak_safe_boost:-not found}) — update _octopus_spawn_pid_wait_default_attempts's fallback in scripts/lib/spawn.sh to match"
fi

test_summary
