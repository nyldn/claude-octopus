#!/usr/bin/env bash
# Regression checks for the YAML workflow runtime (scripts/lib/yaml-workflow.sh).
#
# Covers the v9.52.x embrace-flow defects:
#   1. Phase quality-gate thresholds parsed as empty (awk fallback missed the
#      nested quality_gate.threshold key) and the last phase bled into the
#      document-level quality_gates: block.
#   2. prompt_template blocks silently discarded when yq is not installed.
#   3. execute_workflow_phase/run_yaml_workflow stdout polluted by banners,
#      corrupting the synthesis-path handoff between phases.
#   4. Sequential (parallel: false) agents never awaited before synthesis.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
YAML_LIB="$PROJECT_ROOT/scripts/lib/yaml-workflow.sh"
EMBRACE_YAML="$PROJECT_ROOT/config/workflows/embrace.yaml"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"

set +e

test_suite "yaml workflow runtime"

test_case "yaml-workflow.sh has valid bash syntax"
if bash -n "$YAML_LIB" 2>/dev/null; then
    test_pass
else
    test_fail "syntax error in yaml-workflow.sh"
fi

log() { :; }

# shellcheck source=/dev/null
source "$YAML_LIB"

# Force the awk fallback paths even when yq is installed on the host: the
# machines this bug bit had no yq, and the fallback must stand on its own.
# Shadow `command` so `command -v yq` fails inside the sourced functions
command() {
    if [[ "$1" == "-v" && "$2" == "yq" ]]; then
        return 1
    fi
    builtin command "$@"
}

test_case "awk fallback parses per-phase quality gate thresholds"
# Bash 3.2 floor (macOS /bin/bash 3.2.57) has no associative arrays: the
# subscript is evaluated arithmetically and the suite aborts with
# `probe: unbound variable` before reaching any runtime assertion.
threshold_failures=""
for pair in "probe=0.5" "grasp=0.75" "tangle=0.75" "ink=0.80"; do
    phase="${pair%%=*}"
    want="${pair#*=}"
    got=$(yaml_get_phase_config "$EMBRACE_YAML" "$phase" "threshold") || got="(empty)"
    if [[ "$got" != "$want" ]]; then
        threshold_failures+=" $phase=$got(want $want)"
    fi
done
if [[ -z "$threshold_failures" ]]; then
    test_pass
else
    test_fail "wrong thresholds:$threshold_failures"
fi

test_case "missing field returns non-zero so callers can default"
if yaml_get_phase_config "$EMBRACE_YAML" "probe" "no_such_field" >/dev/null; then
    test_fail "expected non-zero exit for missing field"
else
    test_pass
fi

test_case "awk fallback extracts prompt_template block scalars"
tpl=$(yaml_get_agent_prompt "$EMBRACE_YAML" "grasp" "claude")
if [[ "$tpl" == *"{{probe_synthesis}}"* && "$tpl" == *"consensus definition"* ]]; then
    test_pass
else
    test_fail "grasp/claude template missing expected content: $(printf '%s' "$tpl" | head -c 120)"
fi

test_case "prompt_template extraction scoped to requested phase+provider"
tpl_probe_codex=$(yaml_get_agent_prompt "$EMBRACE_YAML" "probe" "codex")
if [[ "$tpl_probe_codex" == *"technical implementation perspective"* \
      && "$tpl_probe_codex" != *"{{probe_synthesis}}"* ]]; then
    test_pass
else
    test_fail "probe/codex template wrong or bled across blocks"
fi

# ── execute_workflow_phase behavior (stubbed spawns) ─────────────────────────

TEST_TMP_DIR="/tmp/octopus-tests-$$"
trap 'rm -rf "$TEST_TMP_DIR"' EXIT INT TERM
RESULTS_DIR="$TEST_TMP_DIR/results"
WORKSPACE_DIR="$TEST_TMP_DIR/workspace"
PLUGIN_DIR="$PROJECT_ROOT"
mkdir -p "$RESULTS_DIR" "$WORKSPACE_DIR/.octo/agents"

CYAN="" GREEN="" MAGENTA="" NC="" _BOX_TOP="" _BOX_BOT=""
OCTOPUS_CONVERGENCE_ENABLED=false
TIMEOUT=30
OCTOPUS_YAML_DONE_WAIT=3

SPAWN_LOG="$TEST_TMP_DIR/spawn.log"
: > "$SPAWN_LOG"

# Stub the spawn/bridge/support surface used by execute_workflow_phase
fleet_dispatch_begin() { :; }
fleet_dispatch_end() { :; }
bridge_update_current_phase() { :; }
bridge_inject_gate_task() { :; }
bridge_generate_phase_summary() { :; }
bridge_evaluate_gate() { return 0; }
bridge_mark_task_complete() { echo "bridge-complete:$1:$2" >> "$SPAWN_LOG"; }
refresh_provider_stats() { :; }
verify_result_integrity() { return 0; }
deduplicate_results() { :; }
_ucfirst() { echo "$1"; }

# Each stubbed spawn writes its result + done marker after a short delay from
# a background process, and echoes that background PID (mirroring the real
# spawn contract). Sequential agents must be awaited for the file to exist at
# synthesis time.
spawn_agent_capture_pid() {
    local agent_type="$1" task_id="$3"
    echo "spawn:$agent_type:$task_id" >> "$SPAWN_LOG"
    (
        sleep 1
        echo "output of $agent_type for $task_id" > "$RESULTS_DIR/${agent_type}-${task_id}.md"
        echo "0" > "$WORKSPACE_DIR/.octo/agents/${task_id}.done"
    ) &
    echo $!
}
spawn_agent() { spawn_agent_capture_pid "$@" >/dev/null; }

TEST_YAML="$TEST_TMP_DIR/mini.yaml"
cat > "$TEST_YAML" <<'EOF'
name: mini
description: "mini workflow"
version: "1.0.0"

phases:
  - name: alpha
    alias: alpha
    description: "Alpha phase"
    emoji: "A"
    agents:
      - provider: claude
        role: "Parallel worker"
        parallel: true
        prompt_template: |
          Parallel: {{prompt}}
      - provider: claude
        role: "Sequential finisher"
        parallel: false
        prompt_template: |
          Sequential: {{prompt}}
    quality_gate:
      threshold: 1.0

quality_gates:
  consensus:
    threshold: 0.75
EOF

test_case "phase stdout carries only the synthesis file path"
phase_stdout=$(execute_workflow_phase "$TEST_YAML" "alpha" "test prompt" "" "tg1" 2>/dev/null)
phase_rc=$?
if [[ $phase_rc -eq 0 && "$phase_stdout" == "$RESULTS_DIR/alpha-synthesis-tg1.md" && -f "$phase_stdout" ]]; then
    test_pass
else
    test_fail "rc=$phase_rc stdout='$phase_stdout'"
fi

test_case "sequential agent output present in phase synthesis"
if grep -q "Sequential finisher\|alpha-tg1-1" "$RESULTS_DIR/alpha-synthesis-tg1.md" 2>/dev/null \
   || grep -q "for alpha-tg1-1" "$RESULTS_DIR/alpha-synthesis-tg1.md" 2>/dev/null; then
    test_pass
else
    test_fail "synthesis missing sequential agent output: $(cat "$RESULTS_DIR/alpha-synthesis-tg1.md" 2>/dev/null | head -c 200)"
fi

test_case "completions recorded in bridge ledger"
if grep -q "bridge-complete:alpha-tg1-0:completed" "$SPAWN_LOG" \
   && grep -q "bridge-complete:alpha-tg1-1:completed" "$SPAWN_LOG"; then
    test_pass
else
    test_fail "bridge_mark_task_complete not called for all tasks: $(grep bridge-complete "$SPAWN_LOG" | tr '\n' ' ')"
fi

test_case "phase fails its gate when no results are produced"
spawn_agent_capture_pid() {
    ( : ) &
    echo $!
}
spawn_agent() { spawn_agent_capture_pid "$@" >/dev/null; }
if execute_workflow_phase "$TEST_YAML" "alpha" "test prompt" "" "tg2" >/dev/null 2>&1; then
    test_fail "expected non-zero exit when zero results produced"
else
    test_pass
fi

test_summary
