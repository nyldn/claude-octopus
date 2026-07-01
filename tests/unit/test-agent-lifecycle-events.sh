#!/usr/bin/env bash
# Regression coverage for agent lifecycle events and optional observer hook.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"

log() { :; }
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/events.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/spawn.sh"

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
sleep 5
HOOK
chmod +x "$TMP_DIR/slow-hook.sh"

test_case "lifecycle hook timeout prevents observer hangs"
export OCTOPUS_AGENT_LIFECYCLE_HOOK="$TMP_DIR/slow-hook.sh"
export OCTOPUS_AGENT_LIFECYCLE_HOOK_TIMEOUT=1
start=$(date +%s)
_octopus_agent_lifecycle_event "spawned" "codex" "task-slow-hook" "developer" "tangle" "555" "$RESULTS_DIR/codex-slow-hook.md" "" "running"
elapsed=$(( $(date +%s) - start ))
if [[ "$elapsed" -lt 4 ]]; then
  test_pass
else
  test_fail "hook timeout did not return promptly"
fi
unset OCTOPUS_AGENT_LIFECYCLE_HOOK_TIMEOUT


cat > "$TMP_DIR/slow-fallback-hook.sh" <<'HOOK'
#!/usr/bin/env bash
sleep 5
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
export OCTOPUS_AGENT_LIFECYCLE_HOOK_TIMEOUT=1
saved_path="$PATH"
start=$(date +%s)
PATH="$no_timeout_bin"
_octopus_agent_lifecycle_event "spawned" "codex" "task-fallback-timeout" "developer" "tangle" "556" "$RESULTS_DIR/codex-fallback-timeout.md" "" "running"
PATH="$saved_path"
elapsed=$(( $(date +%s) - start ))
if [[ "$elapsed" -lt 4 ]]; then
  test_pass
else
  test_fail "built-in timeout fallback did not return promptly"
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
