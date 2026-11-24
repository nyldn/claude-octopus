#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "tangle reruns a subtask whose provider died while it ran"

export OCTOPUS_TANGLE_CODE_REVIEW=false
unset OCTO_ALLOWED_PROVIDERS
mkdir -p "$TEST_TMP_DIR/provider-allowlist"
export OCTOPUS_CONFIG_DIR="$TEST_TMP_DIR/provider-allowlist"

STUB_BIN="$TEST_TMP_DIR/running-fallback-bin"
mkdir -p "$STUB_BIN"
printf '#!/bin/sh\nexit 0\n' > "$STUB_BIN/codex"
chmod +x "$STUB_BIN/codex"

load_fixture() {
    local dir="$1" allowlist="$2"
    rm -rf "$dir"
    mkdir -p "$dir/home" "$dir/repo"
    export HOME="$dir/home"
    if [[ -n "$allowlist" ]]; then
        export OCTO_ALLOWED_PROVIDERS="$allowlist"
    fi
    PATH="$STUB_BIN:$PATH"
    PLUGIN_DIR="$PROJECT_ROOT"

    source "$PROJECT_ROOT/scripts/lib/testing.sh"
    source "$PROJECT_ROOT/scripts/lib/agent-spec.sh"
    source "$PROJECT_ROOT/scripts/lib/provider-allowlist.sh"
    source "$PROJECT_ROOT/scripts/lib/quota-watcher.sh"
    source "$PROJECT_ROOT/scripts/provider-router.sh"
    source "$PROJECT_ROOT/scripts/lib/agent-utils.sh"
    source "$PROJECT_ROOT/scripts/lib/workflows.sh"
    source "$PROJECT_ROOT/scripts/lib/spawn.sh"

    git -C "$dir/repo" init -q
    printf 'fixture\n' > "$dir/repo/README.md"
    git -C "$dir/repo" add README.md
    git -C "$dir/repo" -c user.name=fixture -c user.email=fixture@example.invalid commit -qm fixture
    PROJECT_ROOT="$dir/repo"
    cd "$dir/repo"

    CYAN="" GREEN="" MAGENTA="" YELLOW="" NC=""
    TMUX_MODE=false
    DRY_RUN=false
    SUPPORTS_PARALLEL_FILE_SAFETY=false
    SUPPORTS_CONTINUATION=false
    RESULTS_DIR="$dir/results"
    LOGS_DIR="$RESULTS_DIR/logs"
    WORKSPACE_DIR="$dir/workspace"
    _PROVIDER_STATE_DIR="$dir/provider-state"
    CAPTURE="$dir/capture"
    mkdir -p "$WORKSPACE_DIR/.octo/agents" "$LOGS_DIR" "$_PROVIDER_STATE_DIR"
    : > "$CAPTURE"

    log() { :; }
    octopus_tangle_cancel_active() { :; }
}

kill_provider() {
    case "$1" in
        circuit) date +%s > "$_PROVIDER_STATE_DIR/codex.cooldown" ;;
        quota) octo_quota_mark_dead codex ;;
        claude) octo_quota_mark_dead claude ;;
    esac
}

write_result() {
    local agent="$1" task_id="$2" status="$3"
    printf '%s\n' "# Agent: $agent" "# Task ID: $task_id" "# Role: implementer" \
        "# Prompt: Add the two org scopes." "# Started: fixture" "" "## Output" "fixture" "" \
        "## Status: $status" > "$RESULTS_DIR/${agent}-${task_id}.md"
}

run_develop() (
    local name="$1"
    SCENARIO="$2"
    load_fixture "$TEST_TMP_DIR/running-fallback-$name" "${3:-}"

    octopus_phase_banner() { :; }
    display_workflow_cost_estimate() { return 0; }
    reset_provider_lockouts() { :; }
    design_review_ceremony() { :; }
    fleet_dispatch_begin() { :; }
    fleet_dispatch_end() { :; }
    validate_tangle_results() { :; }
    if [[ "$SCENARIO" == deadline ]]; then
        tangle_subtask_wait_deadline() { printf '1\n'; }
    fi

    run_agent_sync() {
        if [[ "${OCTOPUS_UNBOUNDED_EXECUTION_SUPERVISED:-}" == "tangle-decomposition-adequacy" ]]; then
            printf '%s\n' 'VERDICT: PASS' 'REASONS: fixture decomposition is adequate' 'SCOPE_REVIEW: NONE'
            return 0
        fi
        cat <<'EOF'
<external-cli-output provider="codex" trust="untrusted">
1. [CODING] Declare scopes — Files: src/scopes.ts — Task: Add the two org scopes.
2. [CODING] Add storage primitives — Files: src/storage.ts — Task: Add the outbox helpers.
</external-cli-output>
EOF
    }

    attempt_dies() {
        local agent="$1" task_id="$2" spawned="$3"
        [[ "$task_id" == *-0 ]] || return 1
        case "$SCENARIO" in
            replacement-dies) [[ "$spawned" -eq 0 || "$agent" == claude-sonnet ]] ;;
            *) [[ "$spawned" -eq 0 ]] ;;
        esac
    }

    spawn_agent_capture_pid() {
        local agent="$1" task_id="$3" role="$4" phase="$5" provider spawned
        cat >/dev/null || true
        printf 'attempt %s %s\n' "$task_id" "$agent" >> "$CAPTURE"
        [[ "$task_id" != *-0 || "$2" == *"Add the two org scopes."* ]] || printf 'lost prompt %s\n' "$task_id" >> "$CAPTURE"
        provider="$(octo_agent_spec_provider "$agent")"
        is_provider_available "$provider" || return 1
        octo_quota_is_dead "$provider" && return 1
        spawned=$(grep -c '^spawned ' "$CAPTURE" || true)
        printf 'spawned %s %s|%s\n' "$task_id" "$agent" "$role" >> "$CAPTURE"
        if [[ "$SCENARIO" == boundary && "$agent" == claude-sonnet ]]; then
            if octopus_tangle_execution_boundary_required &&
               [[ "${OCTOPUS_TANGLE_WORKTREE:-}" == "$PROJECT_ROOT" &&
                  "${OCTOPUS_TANGLE_RESULTS_DIR:-}" == "$RESULTS_DIR" ]]; then
                printf 'boundary configured\n' >> "$CAPTURE"
            else
                printf 'boundary missing\n' >> "$CAPTURE"
            fi
            printf 'contract %s\n' "${7#"$task_id"}" >> "$CAPTURE"
        fi
        mkdir -p src
        if attempt_dies "$agent" "$task_id" "$spawned"; then
            printf 'partial by %s\n' "$agent" >> src/scopes.ts
            if [[ "$SCENARIO" == healthy-failure || "$SCENARIO" == unrelated-quota ]]; then
                write_result "$agent" "$task_id" "FAILED (exit code: 1)"
                printf '1\n' > "$WORKSPACE_DIR/.octo/agents/${task_id}.done"
            elif [[ "$SCENARIO" == ordinary-75 ]]; then
                write_result "$agent" "$task_id" "FAILED (exit code: 75)"
                printf '75\n' > "$WORKSPACE_DIR/.octo/agents/${task_id}.done"
            else
                [[ "$agent" != claude-sonnet ]] || kill_provider claude
                write_result "$agent" "$task_id" "FAILED - QUOTA OR AUTH ERROR (exit code: 75)"
                printf '75\n' > "$WORKSPACE_DIR/.octo/agents/${task_id}.done"
            fi
        else
            [[ "$task_id" != *-0 ]] || printf 'finished by %s\n' "$agent" >> src/scopes.ts
            write_result "$agent" "$task_id" "SUCCESS"
            printf '0\n' > "$WORKSPACE_DIR/.octo/agents/${task_id}.done"
        fi
        if [[ "$spawned" -eq 1 ]]; then
            case "$SCENARIO" in
                circuit) kill_provider circuit ;;
                quota|replacement-dies|codex-only|boundary|unrelated-quota|ordinary-75|deadline) kill_provider quota ;;
            esac
        fi
        printf '12345\n'
    }

    local rc=0 result results=""
    tangle_develop "Implement the two-part plan." >/dev/null 2>&1 || rc=$?
    printf 'rc=%s\n' "$rc"
    sed -E 's/tangle-[^ ]*-([0-9]+) /task\1 /' "$CAPTURE"
    cat src/scopes.ts
    for result in "$RESULTS_DIR"/*-tangle-*.md; do
        [[ -f "$result" ]] || continue
        results+=" $(basename "$result" | sed -E 's/-tangle-.*-([0-9]+)\.md$/-task\1/')"
    done
    printf 'results:%s\n' "$results"
)

run_retry() (
    local name="$1"
    SCENARIO="$2"
    load_fixture "$TEST_TMP_DIR/running-fallback-$name" ""

    is_provider_locked() { return 1; }
    search_similar_errors() { printf '0\n'; }
    flag_repeat_error() { :; }
    should_use_agent_teams() { return 1; }

    spawn_agent_capture_pid() {
        local agent="$1" task_id="$3" provider
        cat >/dev/null || true
        printf 'attempt %s %s\n' "$task_id" "$agent" >> "$CAPTURE"
        provider="$(octo_agent_spec_provider "$agent")"
        is_provider_available "$provider" || return 1
        octo_quota_is_dead "$provider" && return 1
        printf '0\n' > "$WORKSPACE_DIR/.octo/agents/${task_id}.done"
        printf '12345\n'
    }

    write_result codex tangle-fixture-0 "FAILED - QUOTA OR AUTH ERROR (exit code: 75)"
    [[ "$SCENARIO" == healthy ]] || kill_provider quota
    FAILED_SUBTASKS="result:$RESULTS_DIR/codex-tangle-fixture-0.md"

    local rc=0
    retry_failed_subtasks fixture 1 >/dev/null 2>&1 || rc=$?
    printf 'rc=%s\n' "$rc"
    cat "$CAPTURE"
)

expect_output() {
    local title="$1" expected="$2" runner="$3"
    shift 3
    test_case "$title"
    local got
    got="$("$runner" "$@")"
    if [[ "$got" == "$expected" ]]; then
        test_pass
    else
        test_fail "expected:
$expected
got:
$got"
    fi
}

expect_output "codex is marked quota-dead while subtask 1 runs: it reruns on claude-sonnet over its partial edits" \
"rc=0
attempt task0 codex
spawned task0 codex|implementer
attempt task1 codex
spawned task1 codex|implementer
attempt task0 claude-sonnet
spawned task0 claude-sonnet|implementer
partial by codex
finished by claude-sonnet
results: claude-sonnet-task0 codex-task1" \
    run_develop quota quota

expect_output "codex's circuit opens while subtask 1 runs: it reruns on claude-sonnet over its partial edits" \
"rc=0
attempt task0 codex
spawned task0 codex|implementer
attempt task1 codex
spawned task1 codex|implementer
attempt task0 claude-sonnet
spawned task0 claude-sonnet|implementer
partial by codex
finished by claude-sonnet
results: claude-sonnet-task0 codex-task1" \
    run_develop circuit circuit

expect_output "a subtask that fails with codex still healthy is not moved" \
"rc=0
attempt task0 codex
spawned task0 codex|implementer
attempt task1 codex
spawned task1 codex|implementer
partial by codex
results: codex-task0 codex-task1" \
    run_develop healthy-failure healthy-failure

for scenario in unrelated-quota ordinary-75 deadline; do
    expect_output "a task is eligible for recovery only with provider-failure evidence and time left ($scenario)" \
"rc=0
attempt task0 codex
spawned task0 codex|implementer
attempt task1 codex
spawned task1 codex|implementer
partial by codex
results: codex-task0 codex-task1" \
        run_develop "$scenario" "$scenario"
done

expect_output "a replacement retains the boundary and gets a new execution contract seat" \
"rc=0
attempt task0 codex
spawned task0 codex|implementer
attempt task1 codex
spawned task1 codex|implementer
attempt task0 claude-sonnet
spawned task0 claude-sonnet|implementer
boundary configured
contract :recovery-1-attempt-1
partial by codex
finished by claude-sonnet
results: claude-sonnet-task0 codex-task1" \
    run_develop boundary boundary

expect_output "allowlist 'codex' has no replacement, so the failed subtask stays failed" \
"rc=0
attempt task0 codex
spawned task0 codex|implementer
attempt task1 codex
spawned task1 codex|implementer
partial by codex
results: codex-task0 codex-task1" \
    run_develop codex-only codex-only "codex"

expect_output "the replacement dies too: with no provider left the subtask stays failed" \
"rc=0
attempt task0 codex
spawned task0 codex|implementer
attempt task1 codex
spawned task1 codex|implementer
attempt task0 claude-sonnet
spawned task0 claude-sonnet|implementer
partial by codex
partial by claude-sonnet
results: claude-sonnet-task0 codex-task1" \
    run_develop replacement-dies replacement-dies

expect_output "a loop retry of a subtask whose codex is quota-dead runs on claude-sonnet" \
"rc=0
attempt tangle-fixture-retry1-0 claude-sonnet" \
    run_retry retry-quota quota

expect_output "a loop retry with codex still healthy stays on codex" \
"rc=0
attempt tangle-fixture-retry1-0 codex" \
    run_retry retry-healthy healthy

test_summary
