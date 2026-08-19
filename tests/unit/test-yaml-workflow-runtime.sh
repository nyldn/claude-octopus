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
# Shadow `command` so `command -v yq` fails inside the sourced functions.
# Also force `command -v codex` to fail: provider-availability tests below
# rely on codex being "not installed" (compensating with OPENAI_API_KEY
# where they need it available) — a host that happens to have the real
# codex binary on PATH must not change their outcome.
command() {
    if [[ "$1" == "-v" && ( "$2" == "yq" || "$2" == "codex" ) ]]; then
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
fleet_dispatch_begin() { echo "fleet:begin" >> "$SPAWN_LOG"; }
fleet_dispatch_end() { echo "fleet:end" >> "$SPAWN_LOG"; }
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
    local agent_type="$1" agent_prompt="$2" task_id="$3"
    echo "spawn:$agent_type:$task_id" >> "$SPAWN_LOG"
    printf '%s\n' "$agent_prompt" > "$TEST_TMP_DIR/prompt-${task_id}.txt"
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

# ── same-phase sibling substitution (issue #944) ─────────────────────────────
# embrace.yaml's ink phase briefs its sequential synthesis agent with
# {{ink_codex}} / {{ink_agy}} — the outputs of the two parallel agents in the
# *same* phase, not a cross-phase variable like {{tangle_implementation}}.
# resolve_prompt_template never substituted those, so the synthesis agent
# received the literal placeholder text instead of its siblings' output.

BETA_YAML="$TEST_TMP_DIR/beta.yaml"
cat > "$BETA_YAML" <<'EOF'
name: beta-workflow
description: "same-phase sibling substitution"
version: "1.0.0"

phases:
  - name: beta
    alias: beta
    description: "Beta phase"
    emoji: "B"
    agents:
      - provider: codex
        role: "Quality review"
        parallel: true
        prompt_template: |
          Codex: {{prompt}}
      - provider: agy
        role: "Security review"
        parallel: true
        prompt_template: |
          Agy: {{prompt}}
      - provider: claude
        role: "Synthesis"
        parallel: false
        prompt_template: |
          Quality review: {{beta_codex}}
          Security review: {{beta_agy}}
    quality_gate:
      threshold: 1.0

quality_gates:
  consensus:
    threshold: 0.75
EOF

test_case "sequential agent prompt receives same-phase sibling outputs"
# Availability checks require a binary or an API key; the sandbox has
# neither codex nor agy installed, so fake the API keys to reach the spawn.
# Scoped to this subshell so it doesn't leak into later test cases.
beta_stdout=$(
    export "OPENAI_API_KEY=test-key" "ANTIGRAVITY_API_KEY=test-key"
    execute_workflow_phase "$BETA_YAML" "beta" "test prompt" "" "tg-sib" 2>/dev/null
)
beta_rc=$?
synthesis_prompt="$TEST_TMP_DIR/prompt-beta-tg-sib-2.txt"
if [[ $beta_rc -eq 0 \
      && -f "$synthesis_prompt" \
      && "$(cat "$synthesis_prompt")" == *"output of codex for beta-tg-sib-0"* \
      && "$(cat "$synthesis_prompt")" == *"output of agy for beta-tg-sib-1"* \
      && "$(cat "$synthesis_prompt")" != *"{{beta_codex}}"* \
      && "$(cat "$synthesis_prompt")" != *"{{beta_agy}}"* ]]; then
    test_pass
else
    test_fail "rc=$beta_rc prompt='$(cat "$synthesis_prompt" 2>/dev/null)'"
fi

test_case "sibling placeholder resolves by configured provider, not result-file prefix"
# claude's result-file prefix is "claude-sonnet" (agent_type), not "claude"
# (provider). A sibling placeholder like {{delta_claude}} must resolve via
# the configured provider name, or it never resolves for a claude sibling.
DELTA_YAML="$TEST_TMP_DIR/delta.yaml"
cat > "$DELTA_YAML" <<'EOF'
name: delta-workflow
description: "provider-name sibling substitution"
version: "1.0.0"

phases:
  - name: delta
    alias: delta
    description: "Delta phase"
    emoji: "D"
    agents:
      - provider: claude
        role: "First opinion"
        parallel: true
        prompt_template: |
          Claude: {{prompt}}
      - provider: codex
        role: "Synthesis"
        parallel: false
        prompt_template: |
          First opinion: {{delta_claude}}
    quality_gate:
      threshold: 1.0

quality_gates:
  consensus:
    threshold: 0.75
EOF
delta_stdout=$(
    export "OPENAI_API_KEY=test-key" "ANTIGRAVITY_API_KEY=test-key"
    execute_workflow_phase "$DELTA_YAML" "delta" "test prompt" "" "tg-provider" 2>/dev/null
)
delta_rc=$?
delta_prompt="$TEST_TMP_DIR/prompt-delta-tg-provider-1.txt"
if [[ $delta_rc -eq 0 \
      && -f "$delta_prompt" \
      && "$(cat "$delta_prompt")" == *"output of claude-sonnet for delta-tg-provider-0"* \
      && "$(cat "$delta_prompt")" != *"{{delta_claude}}"* ]]; then
    test_pass
else
    test_fail "rc=$delta_rc prompt='$(cat "$delta_prompt" 2>/dev/null)'"
fi

test_case "second sequential agent sees the first sequential agent's own output"
# Sibling gathering must reflect everything completed so far in the phase,
# not just the most recent parallel batch — otherwise a phase with two
# sequential agents in a row can never let the second reference the first.
IOTA_YAML="$TEST_TMP_DIR/iota.yaml"
cat > "$IOTA_YAML" <<'EOF'
name: iota-workflow
description: "two consecutive sequential agents"
version: "1.0.0"

phases:
  - name: iota
    alias: iota
    description: "Iota phase"
    emoji: "I"
    agents:
      - provider: codex
        role: "Parallel worker"
        parallel: true
        prompt_template: |
          Codex: {{prompt}}
      - provider: agy
        role: "First sequential agent"
        parallel: false
        prompt_template: |
          Parallel sibling: {{iota_codex}}
      - provider: claude
        role: "Second sequential agent"
        parallel: false
        prompt_template: |
          Parallel sibling: {{iota_codex}}
          First sequential sibling: {{iota_agy}}
    quality_gate:
      threshold: 1.0

quality_gates:
  consensus:
    threshold: 0.75
EOF
iota_stdout=$(
    export "OPENAI_API_KEY=test-key" "ANTIGRAVITY_API_KEY=test-key"
    execute_workflow_phase "$IOTA_YAML" "iota" "test prompt" "" "tg-iota" 2>/dev/null
)
iota_rc=$?
iota_prompt="$TEST_TMP_DIR/prompt-iota-tg-iota-2.txt"
if [[ $iota_rc -eq 0 \
      && -f "$iota_prompt" \
      && "$(cat "$iota_prompt")" == *"output of codex for iota-tg-iota-0"* \
      && "$(cat "$iota_prompt")" == *"output of agy for iota-tg-iota-1"* \
      && "$(cat "$iota_prompt")" != *"{{iota_codex}}"* \
      && "$(cat "$iota_prompt")" != *"{{iota_agy}}"* ]]; then
    test_pass
else
    test_fail "rc=$iota_rc prompt='$(cat "$iota_prompt" 2>/dev/null)'"
fi

test_case "tampered sibling result is excluded, not injected into the next prompt"
verify_result_integrity() {
    [[ "$1" == *"codex-"* ]] && return 1
    return 0
}
epsilon_rc=0
epsilon_out=$(
    export "OPENAI_API_KEY=test-key" "ANTIGRAVITY_API_KEY=test-key"
    execute_workflow_phase "$BETA_YAML" "beta" "test prompt" "" "tg-tamper" 2>&1
) || epsilon_rc=$?
verify_result_integrity() { return 0; }
if [[ $epsilon_rc -ne 0 ]]; then
    test_pass
else
    test_fail "expected the phase to halt when a sibling result fails integrity verification: $epsilon_out"
fi

test_case "unavailable-provider note survives the sib_providers rebuild"
# sib_providers/sib_outputs are rebuilt from spawned_tasks on every agent
# iteration (so a later agent can see an earlier one's output). A skipped
# provider never enters spawned_tasks, so without preserving it separately
# the rebuild would silently drop the "(unavailable)" note the very next
# iteration and its placeholder would go unresolved instead.
KAPPA_YAML="$TEST_TMP_DIR/kappa.yaml"
cat > "$KAPPA_YAML" <<'EOF'
name: kappa-workflow
description: "unavailable-provider note must survive the rebuild"
version: "1.0.0"

phases:
  - name: kappa
    alias: kappa
    description: "Kappa phase"
    emoji: "K"
    agents:
      - provider: codex
        role: "Parallel worker"
        parallel: true
        prompt_template: |
          Codex: {{prompt}}
      - provider: agy
        role: "Other parallel worker"
        parallel: true
        prompt_template: |
          Agy: {{prompt}}
      - provider: claude
        role: "Synthesis"
        parallel: false
        prompt_template: |
          Codex says: {{kappa_codex}}
          Agy says: {{kappa_agy}}
    quality_gate:
      threshold: 0.5

quality_gates:
  consensus:
    threshold: 0.75
EOF
kappa_stdout=$(
    export "ANTIGRAVITY_API_KEY=test-key"
    unset -v OPENAI_API_KEY 2>/dev/null || true
    execute_workflow_phase "$KAPPA_YAML" "kappa" "test prompt" "" "tg-kappa" 2>/dev/null
)
kappa_rc=$?
kappa_prompt="$TEST_TMP_DIR/prompt-kappa-tg-kappa-2.txt"
if [[ $kappa_rc -eq 0 \
      && -f "$kappa_prompt" \
      && "$(cat "$kappa_prompt")" == *"(codex unavailable — skipped this run)"* \
      && "$(cat "$kappa_prompt")" == *"output of agy for kappa-tg-kappa-1"* \
      && "$(cat "$kappa_prompt")" != *"{{kappa_codex}}"* \
      && "$(cat "$kappa_prompt")" != *"{{kappa_agy}}"* ]]; then
    test_pass
else
    test_fail "rc=$kappa_rc prompt='$(cat "$kappa_prompt" 2>/dev/null)'"
fi

test_case "sequential agent does not start while a parallel sibling is still running past its wait window"
# _yaml_wait_for_pids always returns 0, even when it gives up at its
# max_wait with a pid still alive (it has other bare, unchecked call sites
# under this file's set -e caller, so its contract can't change here). The
# sequential-agent wait must catch that itself instead of trusting it.
#
# _yaml_wait_for_pids is stubbed to an instant no-op rather than timed
# against a real sleeping agent, and the "still running" pid is a process
# launched directly at this test's own top level rather than backgrounded
# from inside the stub: whether `pid=$(spawn_agent_capture_pid ...)` itself
# blocks until a job it backgrounds completes is shell/environment-
# dependent (it does on some CI runners, not in every sandbox), so a job
# backgrounded *inside* that command substitution can already be dead by
# the time the check below runs. A pid from outside that boundary is alive
# regardless.
_theta_orig_spawn=$(declare -f spawn_agent_capture_pid)
_theta_orig_wait=$(declare -f _yaml_wait_for_pids)
_theta_orig_markers=$(declare -f _yaml_wait_for_done_markers)
# Stubbed to instant success too, so this test isolates the kill -0
# liveness check specifically (its name promise) rather than incidentally
# passing via the separate missing-.done-marker path — codex's stub below
# never writes a marker either way, since it must appear to run forever.
_yaml_wait_for_done_markers() { return 0; }
sleep 60 &
_theta_long_pid=$!
spawn_agent_capture_pid() {
    local agent_type="$1" agent_prompt="$2" task_id="$3"
    echo "spawn:$agent_type:$task_id" >> "$SPAWN_LOG"
    printf '%s\n' "$agent_prompt" > "$TEST_TMP_DIR/prompt-${task_id}.txt"
    if [[ "$agent_type" == "codex" ]]; then
        # Never writes a result or .done marker — this agent must appear to
        # still be running for the lifetime of this test case.
        echo "$_theta_long_pid"
    else
        # Only reached if the fix under test fails to halt the phase; spawn
        # for real so the test fails fast on the assertion below instead of
        # hanging.
        echo "output of $agent_type for $task_id" > "$RESULTS_DIR/${agent_type}-${task_id}.md"
        echo "0" > "$WORKSPACE_DIR/.octo/agents/${task_id}.done"
        echo $$
    fi
}
_yaml_wait_for_pids() { return 0; }
THETA_YAML="$TEST_TMP_DIR/theta.yaml"
cat > "$THETA_YAML" <<'EOF'
name: theta-workflow
description: "sibling still running past its wait window"
version: "1.0.0"

phases:
  - name: theta
    alias: theta
    description: "Theta phase"
    emoji: "T"
    agents:
      - provider: codex
        role: "Slow parallel worker"
        parallel: true
        prompt_template: |
          Codex: {{prompt}}
      - provider: claude
        role: "Synthesis"
        parallel: false
        prompt_template: |
          Synthesis: {{prompt}}
    quality_gate:
      threshold: 1.0

quality_gates:
  consensus:
    threshold: 0.75
EOF
theta_rc=0
theta_out=$(
    export "OPENAI_API_KEY=test-key"
    execute_workflow_phase "$THETA_YAML" "theta" "test prompt" "" "tg-theta" 2>&1
) || theta_rc=$?
kill "$_theta_long_pid" 2>/dev/null || true
wait "$_theta_long_pid" 2>/dev/null || true
eval "$_theta_orig_spawn"
eval "$_theta_orig_wait"
eval "$_theta_orig_markers"
if [[ $theta_rc -ne 0 && ! -f "$TEST_TMP_DIR/prompt-theta-tg-theta-1.txt" ]]; then
    test_pass
else
    test_fail "rc=$theta_rc (expected non-zero, and the sequential agent should never have been prompted): $theta_out"
fi

test_case "literal double-curly-brace text in prompt/previous_output does not false-positive halt"
# {{prompt}} and {{grasp_consensus}}/{{tangle_implementation}} substitute raw
# text verbatim (a user's own request, or a prior phase's AI output). If that
# text happens to quote a Jinja/Helm/GH Actions template, it must not be
# mistaken for one of this mechanism's own unresolved {{<phase>_<provider>}}
# sibling placeholders.
ETA_YAML="$TEST_TMP_DIR/eta.yaml"
cat > "$ETA_YAML" <<'EOF'
name: eta-workflow
description: "literal curly braces must not false-positive"
version: "1.0.0"

phases:
  - name: eta
    alias: eta
    description: "Eta phase"
    emoji: "E"
    agents:
      - provider: claude
        role: "Synthesis"
        parallel: false
        prompt_template: |
          {{prompt}}
    quality_gate:
      threshold: 1.0

quality_gates:
  consensus:
    threshold: 0.75
EOF
literal_prompt='Explain this Helm snippet: {{ .Release.Name }} and this GH Actions expr: ${{ secrets.TOKEN }}'
if execute_workflow_phase "$ETA_YAML" "eta" "$literal_prompt" "" "tg-literal" >/dev/null 2>&1; then
    test_pass
else
    test_fail "literal {{...}} text in the prompt incorrectly halted the phase"
fi

test_case "unresolved-placeholder halt drains parallel siblings and closes fleet_dispatch"
ZETA_YAML="$TEST_TMP_DIR/zeta.yaml"
cat > "$ZETA_YAML" <<'EOF'
name: zeta-workflow
description: "halt path must not leak pids or dispatch state"
version: "1.0.0"

phases:
  - name: zeta
    alias: zeta
    description: "Zeta phase"
    emoji: "Z"
    agents:
      - provider: codex
        role: "Parallel worker"
        parallel: true
        prompt_template: |
          Codex: {{prompt}}
      - provider: claude
        role: "Synthesis"
        parallel: false
        prompt_template: |
          Real sibling: {{zeta_codex}}
          Bogus sibling: {{zeta_bogus}}
    quality_gate:
      threshold: 1.0

quality_gates:
  consensus:
    threshold: 0.75
EOF
fleet_begin_before=$(grep -c "^fleet:begin$" "$SPAWN_LOG" 2>/dev/null || echo 0)
fleet_end_before=$(grep -c "^fleet:end$" "$SPAWN_LOG" 2>/dev/null || echo 0)
zeta_rc=0
(
    export "OPENAI_API_KEY=test-key"
    execute_workflow_phase "$ZETA_YAML" "zeta" "test prompt" "" "tg-zeta" >/dev/null 2>&1
) || zeta_rc=$?
fleet_begin_after=$(grep -c "^fleet:begin$" "$SPAWN_LOG" 2>/dev/null || echo 0)
fleet_end_after=$(grep -c "^fleet:end$" "$SPAWN_LOG" 2>/dev/null || echo 0)
if [[ $zeta_rc -ne 0 \
      && $(( fleet_begin_after - fleet_begin_before )) -eq 1 \
      && $(( fleet_end_after - fleet_end_before )) -eq 1 \
      && -f "$RESULTS_DIR/codex-zeta-tg-zeta-0.md" ]]; then
    test_pass
else
    test_fail "rc=$zeta_rc begin_delta=$(( fleet_begin_after - fleet_begin_before )) end_delta=$(( fleet_end_after - fleet_end_before )) codex_result_exists=$([[ -f "$RESULTS_DIR/codex-zeta-tg-zeta-0.md" ]] && echo yes || echo no)"
fi

test_case "phase halts instead of spawning with an unresolved sibling placeholder"
# Shaped like this mechanism's own {{<phase>_<provider>}} convention (unlike
# an arbitrary {{nonexistent_thing}}, which the halt no longer flags — see
# the literal-curly-brace false-positive test above).
GAMMA_YAML="$TEST_TMP_DIR/gamma.yaml"
cat > "$GAMMA_YAML" <<'EOF'
name: gamma-workflow
description: "unresolved placeholder"
version: "1.0.0"

phases:
  - name: gamma
    alias: gamma
    description: "Gamma phase"
    emoji: "G"
    agents:
      - provider: claude
        role: "Synthesis"
        parallel: false
        prompt_template: |
          Never resolved: {{gamma_missingprovider}}
    quality_gate:
      threshold: 1.0

quality_gates:
  consensus:
    threshold: 0.75
EOF
if execute_workflow_phase "$GAMMA_YAML" "gamma" "test prompt" "" "tg-fail" >/dev/null 2>&1; then
    test_fail "expected non-zero exit for an unresolved sibling-shaped placeholder"
else
    test_pass
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
