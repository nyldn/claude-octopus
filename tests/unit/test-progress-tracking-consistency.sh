#!/usr/bin/env bash
# Regression checks for #872: progress.json is a task-keyed workflow ledger.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"
WORKSPACE_DIR="$TEST_ROOT/workspace"
PROGRESS_FILE="$WORKSPACE_DIR/progress.json"
mkdir -p "$WORKSPACE_DIR"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "progress tracking consistency"

# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/validation.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/session.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/agents.sh"

PROGRESS_TRACKING_ENABLED=true
CLAUDE_CODE_SESSION="progress-test"
TIMEOUT=600
trap 'rm -rf "$TEST_ROOT"' EXIT

log() { :; }

test_case "phase transitions preserve task totals and terminal rows are counted once"
init_progress_tracking "discover" 0
if ! declare -F begin_progress_phase >/dev/null 2>&1; then
    test_fail "begin_progress_phase is missing"
else
    begin_progress_phase "define"
    update_agent_status "codex" "running" 0 0.25 600 "task-1" "define"
    update_agent_status "codex" "completed" 1000 0.25 600 "task-1" "define"
    update_agent_status "codex" "completed" 1000 0.25 600 "task-1" "define"
    update_agent_status "codex" "running" 0 0.50 1200 "task-2" "develop"
    update_agent_status "codex" "timeout" 2000 0.50 1200 "task-2" "develop"
    # A late terminal event from an earlier phase must not move the workflow
    # summary backward from develop to probe.
    update_agent_status "codex" "completed" 1000 0.25 600 "task-1" "probe"

    if jq -e '
        .phase == "develop" and
        .total_agents == 2 and
        .completed_agents == 2 and
        .successful_agents == 1 and
        .timeout_agents == 1 and
        .failed_agents == 0 and
        .total_time_ms == 3000 and
        .total_cost == 0.75 and
        (.agents | length) == 2 and
        ([.agents[] | select(.status == "running")] | length) == 0 and
        ([.agents[].task_id] | sort) == ["task-1", "task-2"]
    ' "$PROGRESS_FILE" >/dev/null; then
        test_pass
    else
        test_fail "progress ledger reset, duplicated a task, or miscounted terminal totals"
    fi
fi

test_case "all workflow phases advance the canonical progress ledger"
if grep -q 'begin_progress_phase "define"' <<< "$(sed -n '/^grasp_define()/,/^}/p' "$PROJECT_ROOT/scripts/lib/workflows.sh")" &&
   grep -q 'begin_progress_phase "develop"' <<< "$(sed -n '/^_tangle_develop_in_workspace()/,/^}/p' "$PROJECT_ROOT/scripts/lib/workflows.sh")" &&
   grep -q 'begin_progress_phase "deliver"' <<< "$(sed -n '/^ink_deliver()/,/^}/p' "$PROJECT_ROOT/scripts/lib/workflows.sh")"; then
    test_pass
else
    test_fail "define, develop, and deliver do not all advance progress tracking"
fi

test_case "probe, sync, and background dispatches report task identity and estimated cost"
if grep -q '"\$estimated_cost" "\$TIMEOUT" "\$task_id" "\$phase" "\$result_file"' "$PROJECT_ROOT/scripts/lib/workflows.sh" &&
   grep -q '"\$_progress_task_id" "\${phase:-unknown}"' "$PROJECT_ROOT/scripts/lib/agent-sync.sh" &&
   grep -q '"\$_estimated_cost".*"\$task_id"' "$PROJECT_ROOT/scripts/lib/spawn.sh"; then
    test_pass
else
    test_fail "one or more dispatch paths still writes anonymous zero-cost progress rows"
fi

test_summary
