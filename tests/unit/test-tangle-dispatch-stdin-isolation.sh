#!/usr/bin/env bash
# Regression check: tangle dispatch must not let the first provider consume
# remaining decomposition lines from the dispatch loop stdin.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKFLOWS="$PROJECT_ROOT/scripts/lib/workflows.sh"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "tangle dispatch stdin isolation"

test_case "workflows.sh has valid bash syntax"
if bash -n "$WORKFLOWS" 2>/dev/null; then
    test_pass
else
    test_fail "syntax error in workflows.sh"
fi

# shellcheck source=/dev/null
source "$WORKFLOWS"

CYAN=""
GREEN=""
MAGENTA=""
NC=""
TMUX_MODE=false
DRY_RUN=false
SUPPORTS_PARALLEL_FILE_SAFETY=false
RESULTS_DIR="$TEST_TMP_DIR/tangle-dispatch-stdin-isolation"
LOGS_DIR="$RESULTS_DIR/logs"
WORKSPACE_DIR="$RESULTS_DIR/workspace"
CAPTURE_DIR="$RESULTS_DIR/captured"
rm -rf "$RESULTS_DIR"
mkdir -p "$WORKSPACE_DIR/.octo/agents" "$CAPTURE_DIR"
trap 'rm -rf "$RESULTS_DIR"' EXIT

log() { :; }
octopus_phase_banner() { :; }
display_workflow_cost_estimate() { return 0; }
reset_provider_lockouts() { :; }
design_review_ceremony() { :; }
fleet_dispatch_begin() { :; }
fleet_dispatch_end() { :; }
validate_tangle_results() { :; }

run_agent_sync() {
    cat <<'EOF'
<external-cli-output provider="agy" trust="untrusted">
1. [REASONING] Verify workspace clean state — Task: Check git status.
2. [CODING] Implement syntax smoke test — Files: package.json, scripts/check-syntax.js — Task: Update npm test and add syntax checker.
</external-cli-output>
EOF
}

spawn_agent_capture_pid() {
    local agent="$1"
    local prompt="$2"
    local task_id="$3"
    local role="$4"

    # Simulate CLI/provider code that reads inherited stdin. Before this fix,
    # this drained the while-loop here-string and skipped later subtasks.
    cat >/dev/null || true

    printf '%s|%s
' "$agent" "$role" > "$CAPTURE_DIR/${task_id}.agent"
    printf '%s' "$prompt" > "$CAPTURE_DIR/${task_id}.prompt"
    printf '0
' > "$WORKSPACE_DIR/.octo/agents/${task_id}.done"
    printf '12345
'
}

original_prompt="Replace placeholder npm test with scripts/check-syntax.js."
tangle_develop "$original_prompt" >/dev/null

spawned_count=$(find "$CAPTURE_DIR" -name '*.agent' -type f | wc -l | tr -d ' ')
combined_agents=$(cat "$CAPTURE_DIR"/*.agent 2>/dev/null || true)
combined_prompts=$(cat "$CAPTURE_DIR"/*.prompt 2>/dev/null || true)

test_case "dispatch launches all parseable decomposition lines even if a spawn reads stdin"
if [[ "$spawned_count" -eq 2 ]]; then
    test_pass
else
    test_fail "expected 2 spawned subtasks, got $spawned_count"
fi

test_case "dispatch preserves reasoning and coding routing"
if [[ "$combined_agents" == *"agy|researcher"* ]] && [[ "$combined_agents" == *"codex|implementer"* ]]; then
    test_pass
else
    test_fail "expected agy researcher and codex implementer, got: $combined_agents"
fi

test_case "coding subtask prompt is not lost"
if [[ "$combined_prompts" == *"Implement syntax smoke test"* ]] && [[ "$combined_prompts" == *"scripts/check-syntax.js"* ]]; then
    test_pass
else
    test_fail "coding subtask prompt was not dispatched"
fi

test_summary
