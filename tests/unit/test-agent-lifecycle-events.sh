#!/usr/bin/env bash
# Regression coverage for agent lifecycle events and optional observer hook.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"

log() { :; }
octo_provider_identity_from_agent_type() { printf '%s\n' "${1%%-*}"; }
get_agent_model() { printf '%s\n' "fixture-model"; }
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/events.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/spawn.sh"

MONOTONIC_PYTHON=$(command -v python3)
monotonic_millis() {
  "$MONOTONIC_PYTHON" -c 'import time; print(time.monotonic_ns() // 1000000)'
}

test_suite "agent lifecycle events"

TEST_TMP_DIR="/tmp/octopus-tests-$$"
mkdir -p "$TEST_TMP_DIR"
trap 'rm -rf "$TEST_TMP_DIR"' EXIT INT TERM
TMP_DIR="$TEST_TMP_DIR"

RESULTS_DIR="$TMP_DIR/results"
WORKSPACE_DIR="$TMP_DIR/workspace"
OCTO_EVENT_LOG="$TMP_DIR/events.jsonl"
mkdir -p "$RESULTS_DIR" "$WORKSPACE_DIR"

cat > "$TMP_DIR/hook.sh" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
{
  printf 'argv=%s\n' "$1"
  printf 'event=%s\n' "$OCTOPUS_AGENT_HOOK_EVENT"
  printf 'event_name=%s\n' "$OCTOPUS_AGENT_EVENT_NAME"
  printf 'provider=%s\n' "$OCTOPUS_AGENT_PROVIDER"
  printf 'agent=%s\n' "$OCTOPUS_AGENT_TYPE"
  printf 'task=%s\n' "$OCTOPUS_AGENT_TASK_ID"
  printf 'role=%s\n' "$OCTOPUS_AGENT_ROLE"
  printf 'phase=%s\n' "$OCTOPUS_AGENT_PHASE"
  printf 'pid=%s\n' "$OCTOPUS_AGENT_PID"
  printf 'result=%s\n' "$OCTOPUS_AGENT_RESULT_FILE"
  printf 'results_dir=%s\n' "$OCTOPUS_AGENT_RESULTS_DIR"
  printf 'workspace=%s\n' "$OCTOPUS_AGENT_WORKSPACE_DIR"
  printf 'exit=%s\n' "$OCTOPUS_AGENT_EXIT_CODE"
  printf 'status=%s\n' "$OCTOPUS_AGENT_STATUS"
  printf 'root=%s\n' "$OCTOPUS_AGENT_ROOT_SESSION_ID"
  printf 'parent=%s\n' "$OCTOPUS_AGENT_PARENT_SESSION_ID"
} >> "$HOOK_CAPTURE"
echo noisy stdout
echo noisy stderr >&2
HOOK
chmod +x "$TMP_DIR/hook.sh"

cat > "$TMP_DIR/fail-hook.sh" <<'HOOK'
#!/usr/bin/env bash
echo failing hook
exit 42
HOOK
chmod +x "$TMP_DIR/fail-hook.sh"

test_case "lifecycle event writes OCTO_EVENT_LOG and optional hook metadata"
export OCTOPUS_AGENT_LIFECYCLE_HOOK="$TMP_DIR/hook.sh"
export OCTOPUS_AGENT_LIFECYCLE_HOOK_LOG="$TMP_DIR/hook.log"
export HOOK_CAPTURE="$TMP_DIR/capture.txt"
export CRABFLEET_ROOT_SESSION_ID="IS-ROOT"
export CRABFLEET_PARENT_SESSION_ID="IS-PARENT"
stdout="$(_octopus_agent_lifecycle_event "spawned" "codex-standard" "task-1" "developer" "tangle" "12345" "$RESULTS_DIR/codex-task-1.md" "" "running")"
if [[ -z "$stdout" ]] && \
   grep -q '"event":"agent.spawned"' "$OCTO_EVENT_LOG" && \
   grep -q '"agent_type":"codex-standard"' "$OCTO_EVENT_LOG" && \
   grep -q '"provider":"codex"' "$OCTO_EVENT_LOG" && \
   grep -q '^argv=spawned$' "$HOOK_CAPTURE" && \
   grep -q '^event_name=agent.spawned$' "$HOOK_CAPTURE" && \
   grep -q '^provider=codex$' "$HOOK_CAPTURE" && \
   grep -q '^root=IS-ROOT$' "$HOOK_CAPTURE" && \
   grep -q '^parent=IS-PARENT$' "$HOOK_CAPTURE" && \
   grep -q 'noisy stdout' "$TMP_DIR/hook.log" && \
   grep -q 'noisy stderr' "$TMP_DIR/hook.log"; then
  test_pass
else
  test_fail "event log or hook metadata/output redirection did not match expectations"
fi


test_case "empty phase is normalized consistently for event stream and hook"
: > "$OCTO_EVENT_LOG"
: > "$HOOK_CAPTURE"
_octopus_agent_lifecycle_event "spawned" "codex" "task-empty-phase" "developer" "" "444" "$RESULTS_DIR/codex-empty-phase.md" "" "running"
if grep -q '"phase":"unknown"' "$OCTO_EVENT_LOG" && grep -q '^phase=unknown$' "$HOOK_CAPTURE"; then
  test_pass
else
  test_fail "expected empty phase to normalize to unknown across event stream and hook"
fi

cat > "$TMP_DIR/slow-hook.sh" <<'HOOK'
#!/usr/bin/env bash
# Must sleep LONGER than the widened pass bound (timeout + 29s) below, or a
# broken timeout would let the hook finish naturally inside the bound and
# the test would false-pass.
sleep 60
HOOK
chmod +x "$TMP_DIR/slow-hook.sh"

test_case "built-in lifecycle timeout uses a sleep watchdog, not a wall clock"
# shellcheck disable=SC2016 # Intentionally match literal shell source.
fallback_impl=$(sed -n '/# Built-in timeout fallback:/,/wait "\$_hook_watchdog_pid"/p' "$PROJECT_ROOT/scripts/lib/spawn.sh")
if grep -Fq "sleep \"\$hook_timeout\" &" <<<"$fallback_impl" &&
   grep -Fq "kill \"\$_hook_watchdog_pid\"" <<<"$fallback_impl" &&
   grep -Fq "wait \"\$_hook_watchdog_pid\"" <<<"$fallback_impl" &&
   ! grep -Fq "\$SECONDS" <<<"$fallback_impl"; then
  test_pass
else
  test_fail "fallback must use a reaped sleep watchdog without a SECONDS deadline"
fi

test_case "lifecycle hook timeout prevents observer hangs"
export OCTOPUS_AGENT_LIFECYCLE_HOOK="$TMP_DIR/slow-hook.sh"
hook_timeout_secs=1
export OCTOPUS_AGENT_LIFECYCLE_HOOK_TIMEOUT="$hook_timeout_secs"
start_ms=$(monotonic_millis)
_octopus_agent_lifecycle_event "spawned" "codex" "task-slow-hook" "developer" "tangle" "555" "$RESULTS_DIR/codex-slow-hook.md" "" "running"
elapsed_ms=$(( $(monotonic_millis) - start_ms ))
# oco-588: measure against the configured timeout plus a generous grace
# margin instead of a fixed small bound — loaded runners have exhibited
# scheduler pauses above 10s. The hook sleeps 60s so a broken timeout still
# cannot finish naturally inside this 30s bound.
if [[ "$elapsed_ms" -lt $(( (hook_timeout_secs + 29) * 1000 )) ]]; then
  test_pass
else
  test_fail "hook timeout did not return promptly (${elapsed_ms}ms)"
fi
unset OCTOPUS_AGENT_LIFECYCLE_HOOK_TIMEOUT



test_case "lifecycle hook timeout accepts zero-padded decimal values"
export OCTOPUS_AGENT_LIFECYCLE_HOOK="$TMP_DIR/slow-hook.sh"
export OCTOPUS_AGENT_LIFECYCLE_HOOK_TIMEOUT=08
_octopus_agent_lifecycle_event "spawned" "codex" "task-zero-padded-timeout" "developer" "tangle" "557" "$RESULTS_DIR/codex-zero-padded-timeout.md" "" "running"
if grep -q '"task_id":"task-zero-padded-timeout"' "$OCTO_EVENT_LOG" && ! grep -q 'value too great for base' "$TMP_DIR/hook.log"; then
  test_pass
else
  test_fail "zero-padded hook timeout should be normalized as decimal"
fi
unset OCTOPUS_AGENT_LIFECYCLE_HOOK_TIMEOUT

cat > "$TMP_DIR/slow-fallback-hook.sh" <<'HOOK'
#!/usr/bin/env bash
# Must sleep LONGER than the widened pass bound (timeout + 29s) below — see
# slow-hook.sh above.
sleep 60
HOOK
chmod +x "$TMP_DIR/slow-fallback-hook.sh"

test_case "lifecycle hook uses built-in timeout fallback when timeout commands are unavailable"
no_timeout_bin="$TMP_DIR/no-timeout-bin"
mkdir -p "$no_timeout_bin"
ln -sf /bin/sleep "$no_timeout_bin/sleep"
ln -sf /bin/bash "$no_timeout_bin/bash"
ln -sf /bin/date "$no_timeout_bin/date"
ln -sf /usr/bin/dirname "$no_timeout_bin/dirname"
export OCTOPUS_AGENT_LIFECYCLE_HOOK="$TMP_DIR/slow-fallback-hook.sh"
hook_timeout_secs=1
export OCTOPUS_AGENT_LIFECYCLE_HOOK_TIMEOUT="$hook_timeout_secs"
saved_path="$PATH"
start_ms=$(monotonic_millis)
PATH="$no_timeout_bin"
# declare -f run_with_timeout is checked before the PATH-based `timeout`
# lookup, so PATH alone doesn't guarantee this test hits the built-in
# fallback — force it explicitly, since nothing in this file's sourcing
# defines that function today but a future refactor could.
unset -f run_with_timeout 2>/dev/null || true
_octopus_agent_lifecycle_event "spawned" "codex" "task-fallback-timeout" "developer" "tangle" "556" "$RESULTS_DIR/codex-fallback-timeout.md" "" "running"
PATH="$saved_path"
elapsed_ms=$(( $(monotonic_millis) - start_ms ))
# oco-588: same generous grace margin as the primary timeout test above —
# the built-in fallback watchdog sleeps in whole seconds, which adds its own
# rounding jitter on top of scheduler jitter.
if [[ "$elapsed_ms" -lt $(( (hook_timeout_secs + 29) * 1000 )) ]]; then
  test_pass
else
  test_fail "built-in timeout fallback did not return promptly (${elapsed_ms}ms)"
fi
unset OCTOPUS_AGENT_LIFECYCLE_HOOK_TIMEOUT

mkdir -p "$TMP_DIR/orphan-check"
cat > "$TMP_DIR/multi-child-hook.sh" <<HOOK
#!/usr/bin/env bash
# Only record a PID once kill -0 confirms it's actually running — proves
# each descendant was alive before teardown, so a fixture that failed to
# start a child (e.g. sleep missing) can't produce a vacuous pass.
sleep 60 &
child1=\$!
kill -0 "\$child1" 2>/dev/null || exit 1
echo "\$child1" > "$TMP_DIR/orphan-check/child1.pid"
sleep 60 &
child2=\$!
kill -0 "\$child2" 2>/dev/null || exit 1
echo "\$child2" > "$TMP_DIR/orphan-check/child2.pid"
wait
HOOK
chmod +x "$TMP_DIR/multi-child-hook.sh"

test_case "built-in timeout fallback reaps hook's forked children without pkill"
export OCTOPUS_AGENT_LIFECYCLE_HOOK="$TMP_DIR/multi-child-hook.sh"
export OCTOPUS_AGENT_LIFECYCLE_HOOK_TIMEOUT=1
saved_path="$PATH"
PATH="$no_timeout_bin"
unset -f run_with_timeout 2>/dev/null || true
# oco-827: the hook itself `wait`s on its own children, so a fallback that
# silently stops enforcing the timeout would let this call block until both
# sleep-60 children exit naturally — bound elapsed time so that regression
# can't hide behind an eventual, too-slow pass. Same generous grace margin
# as the sibling built-in-fallback test above.
hook_started_ms=$(monotonic_millis)
_octopus_agent_lifecycle_event "spawned" "codex" "task-orphan-check" "developer" "tangle" "558" "$RESULTS_DIR/codex-orphan-check.md" "" "running"
hook_elapsed_ms=$(( $(monotonic_millis) - hook_started_ms ))
PATH="$saved_path"
orphan_survivor=0
child_count=0
for pidfile in "$TMP_DIR/orphan-check"/child*.pid; do
  [[ -f "$pidfile" ]] || continue
  child_count=$((child_count + 1))
  child_pid="$(cat "$pidfile")"
  # kill -0 alone isn't enough: a killed process whose parent (the hook) is
  # already gone reparents to init as a zombie and still answers kill -0
  # until reaped. Check STAT instead — only a non-zombie entry means the
  # sleep is still genuinely running.
  child_stat="$(ps -o stat= -p "$child_pid" 2>/dev/null | tr -d '[:space:]')" || true
  if [[ -n "$child_stat" && "$child_stat" != Z* ]]; then
    orphan_survivor=1
  fi
done
if [[ "$hook_elapsed_ms" -lt $(( (hook_timeout_secs + 29) * 1000 )) && "$child_count" -eq 2 && "$orphan_survivor" -eq 0 ]]; then
  test_pass
else
  test_fail "fallback did not finish within the bound (${hook_elapsed_ms}ms), didn't record both children ($child_count/2), or a grandchild survived teardown"
fi
unset OCTOPUS_AGENT_LIFECYCLE_HOOK_TIMEOUT

test_case "completed lifecycle event carries exit status"
_octopus_agent_lifecycle_event "completed" "gemini-fast" "task-2" "reviewer" "review" "222" "$RESULTS_DIR/gemini-task-2.md" "124" "timeout"
if grep -q '"event":"agent.completed"' "$OCTO_EVENT_LOG" && \
   grep -q '"exit_code":"124"' "$OCTO_EVENT_LOG" && \
   grep -q '"status":"timeout"' "$OCTO_EVENT_LOG"; then
  test_pass
else
  test_fail "completed event missing exit/status attributes"
fi

test_case "hook failure is ignored"
export OCTOPUS_AGENT_LIFECYCLE_HOOK="$TMP_DIR/fail-hook.sh"
if _octopus_agent_lifecycle_event "completed" "gemini" "task-3" "reviewer" "review" "333" "$RESULTS_DIR/gemini-task-3.md" "1" "failed"; then
  test_pass
else
  test_fail "hook failure should not fail agent lifecycle"
fi

test_case "missing hook is a no-op while event stream still works"
unset OCTOPUS_AGENT_LIFECYCLE_HOOK
before=$(wc -l < "$OCTO_EVENT_LOG")
_octopus_agent_lifecycle_event "spawned" "codex" "task-4" "developer" "tangle" "444" "$RESULTS_DIR/codex-task-4.md" "" "running"
after=$(wc -l < "$OCTO_EVENT_LOG")
if [[ "$after" -eq $((before + 1)) ]]; then
  test_pass
else
  test_fail "unset hook should not suppress event stream emission"
fi

test_summary
