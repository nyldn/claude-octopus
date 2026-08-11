#!/usr/bin/env bash
# Regression checks for #872: progress.json is a task-keyed workflow ledger.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "progress tracking consistency"

WORKSPACE_DIR="$TEST_TMP_DIR/progress-workspace"
PROGRESS_FILE="$WORKSPACE_DIR/progress.json"
RESULTS_DIR="$WORKSPACE_DIR/results"
LOGS_DIR="$WORKSPACE_DIR/logs"
mkdir -p "$WORKSPACE_DIR" "$RESULTS_DIR" "$LOGS_DIR"

# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/validation.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/session.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/agents.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/cost.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/agent-sync.sh"

PROGRESS_TRACKING_ENABLED=true
CLAUDE_CODE_SESSION="progress-test"
TIMEOUT=600

log() { :; }

test_case "planned phase width does not shrink while the first tasks register"
init_progress_tracking "discover" 3
update_agent_status "codex" "running" 0 0 600 "planned-task-1" "discover"
if jq -e '.total_agents == 3 and (.agents | length) == 1' "$PROGRESS_FILE" >/dev/null; then
    test_pass
else
    test_fail "the first task registration replaced the planned phase width"
fi

test_case "malformed elapsed time and cost normalize to safe numeric defaults"
init_progress_tracking "develop" 1
update_agent_status "legacy" "completed" "invalid" "null" 600 "legacy-bad-numbers" "develop"
if jq -e '
    .completed_agents == 1 and
    .total_time_ms == 0 and
    .total_cost == 0 and
    .agents[0].elapsed_ms == 0 and
    .agents[0].cost == 0
' "$PROGRESS_FILE" >/dev/null; then
    test_pass
else
    test_fail "malformed numeric inputs prevented or corrupted the ledger update"
fi

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

test_case "source-safe workflow phases tolerate progress tracking not being loaded"
guard_count=$(grep -c 'declare -F begin_progress_phase' "$PROJECT_ROOT/scripts/lib/workflows.sh" || true)
if [[ "$guard_count" -eq 3 ]]; then
    test_pass
else
    test_fail "workflow phase calls are not guarded for standalone source-safe harnesses"
fi

test_case "sync dispatch records task identity and positive API cost"
FAKE_PROVIDER="$TEST_TMP_DIR/fake-api-provider.sh"
cat > "$FAKE_PROVIDER" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
printf '%s\n' "provider completed"
EOF
chmod +x "$FAKE_PROVIDER"
OCTOPUS_PERSONA_PACKS=off
OCTOPUS_PERSISTENCE_AVAILABLE=true
DRY_RUN=false
PROVIDER_ENV_ARRAY=()
apply_persona() { printf '%s\n' "$2"; }
load_earned_skills() { :; }
build_provider_context() { :; }
enforce_context_budget() { printf '%s\n' "$1"; }
get_agent_model() { printf '%s\n' "api-test-model"; }
get_agent_command() { printf '%s\n' "$FAKE_PROVIDER"; }
build_provider_env() { PROVIDER_ENV_ARRAY=(); }
run_with_timeout() { shift; "$@"; }
record_agent_call() { :; }
record_agent_start() { :; }
write_agent_status() { :; }
stop_quota_watcher() { :; }
octo_estimate_tokens_for_file() { printf '%s\n' 1; }
get_model_pricing() { printf '%s\n' "1.00:2.00"; }
is_api_based_provider() { [[ "$1" == "fake-api" ]]; }
classify_agent_output() { printf '%s\n' "ok:Output accepted"; }
init_progress_tracking "develop" 1
run_agent_sync "fake-api" "Behavioral progress dispatch" 10 "implementer" "develop" >/dev/null
if jq -e '
    .completed_agents == 1 and
    .agents[0].status == "ok" and
    (.agents[0].task_id | type == "string" and length > 0) and
    .agents[0].cost > 0
' "$PROGRESS_FILE" >/dev/null; then
    test_pass
else
    test_fail "sync dispatch wrote an anonymous or zero-cost API progress row"
fi

test_case "oversize rejection is skipped without attributing provider cost"
classify_agent_output() { printf '%s\n' "failed:Prompt rejected by provider (oversize)"; }
init_progress_tracking "develop" 1
run_agent_sync "fake-api" "Oversize behavioral dispatch" 10 "implementer" "develop" >/dev/null
if jq -e '
    .completed_agents == 1 and
    .skipped_agents == 1 and
    .agents[0].status == "skipped" and
    .agents[0].cost == 0
' "$PROGRESS_FILE" >/dev/null; then
    test_pass
else
    test_fail "a provider-rejected prompt retained estimated spend"
fi

test_summary
