#!/usr/bin/env bash
# Regression coverage for `orchestrate.sh --dry-run fan-out`. spawn_agent's
# dry-run branch prints a command preview and never a provider PID, so routing
# it through spawn_agent_capture_pid reported every agent as a failed spawn.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "fan-out dry-run"

# An isolated HOME keeps a developer's providers.json from changing the fan-out
# participants and keeps run state out of the real ~/.claude-octopus.
fanout_home="$TEST_TMP_DIR/fan-out-dry-run-home"
fanout_project="$TEST_TMP_DIR/fan-out-dry-run-project"
mkdir -p "$fanout_home"
git init -q "$fanout_project"

out="$(cd "$fanout_project" && HOME="$fanout_home" \
    bash "$PROJECT_ROOT/scripts/orchestrate.sh" -n fan-out "test prompt" </dev/null 2>&1)" && rc=0 || rc=$?
announced="$(sed -n 's/.*Fan-out: Sending prompt to \([0-9][0-9]*\) agents.*/\1/p' <<< "$out")"
previews="$(grep -c '\[DRY-RUN\] Would execute:' <<< "$out" || true)"

test_case "dry-run fan-out exits cleanly"
if [[ "$rc" -eq 0 ]]; then
    test_pass
else
    test_fail "expected exit 0; got exit=$rc, output: $out"
fi

test_case "dry-run fan-out previews every announced agent"
if [[ "$announced" =~ ^[1-9][0-9]*$ && "$previews" -eq "$announced" ]]; then
    test_pass
else
    test_fail "expected one preview per announced agent; announced=${announced:-none}, previews=$previews, output: $out"
fi

test_case "dry-run fan-out reports no failed spawn"
if [[ "$out" != *"produced no provider PID"* && "$out" != *"Fan-out: failed to spawn"* ]]; then
    test_pass
else
    test_fail "dry-run reported spawn failures: $out"
fi

test_case "dry-run fan-out does not claim agents were spawned"
if [[ "$out" != *"All agents spawned"* ]]; then
    test_pass
else
    test_fail "dry-run claimed spawned agents: $out"
fi

# A fresh bash process mirrors orchestrate.sh's `set -eo pipefail`; a subshell
# inside this `&& ... || ...` capture would silently ignore errexit.
test_case "dry-run fan-out warns on a failed preview and still previews the remaining agents"
harness="$TEST_TMP_DIR/fan-out-dry-run-harness.sh"
harness_home="$TEST_TMP_DIR/fan-out-dry-run-harness-home"
calls_log="$TEST_TMP_DIR/fan-out-dry-run-calls"
mkdir -p "$harness_home"
: > "$calls_log"
cat > "$harness" <<'HARNESS'
set -eo pipefail
calls_log="$2"
DRY_RUN=true
log() { printf '%s: %s\n' "$1" "$2"; }
source "$1"
_parallel_google_seat() { echo claude-sonnet; }
spawn_agent() { printf 'preview:%s\n' "$1" >> "$calls_log"; [[ "$1" != "codex" ]]; }
spawn_agent_capture_pid() { printf 'capture:%s\n' "$1" >> "$calls_log"; echo 1; }
fan_out "test prompt"
echo "fan_out returned"
HARNESS
harness_out="$(HOME="$harness_home" bash "$harness" "$PROJECT_ROOT/scripts/lib/parallel.sh" "$calls_log" 2>&1)" \
    && harness_rc=0 || harness_rc=$?
calls="$(<"$calls_log")"
if [[ "$harness_rc" -eq 0 \
    && "$harness_out" == *"WARN: Fan-out: failed to spawn codex"* \
    && "$harness_out" == *"fan_out returned"* \
    && "$calls" == $'preview:codex\npreview:claude-sonnet' ]]; then
    test_pass
else
    test_fail "expected a warning, both previews and no PID capture; got exit=$harness_rc, calls: $calls, output: $harness_out"
fi

test_summary
