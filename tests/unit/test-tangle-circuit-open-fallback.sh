#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "tangle re-routes a subtask when its provider dies mid-run"

export OCTOPUS_TANGLE_CODE_REVIEW=false
unset OCTO_ALLOWED_PROVIDERS
mkdir -p "$TEST_TMP_DIR/provider-allowlist"
export OCTOPUS_CONFIG_DIR="$TEST_TMP_DIR/provider-allowlist"

STUB_BIN="$TEST_TMP_DIR/circuit-fallback-bin"
mkdir -p "$STUB_BIN"
printf '#!/bin/sh\nexit 0\n' > "$STUB_BIN/codex"
chmod +x "$STUB_BIN/codex"

missing_codex_candidates() (
    export OCTO_ALLOWED_PROVIDERS="$2"
    source "$PROJECT_ROOT/scripts/lib/agent-spec.sh"
    source "$PROJECT_ROOT/scripts/lib/provider-allowlist.sh"
    source "$PROJECT_ROOT/scripts/lib/workflows.sh"
    command() {
        if [[ "$*" == "-v codex" ]]; then
            return 1
        fi
        builtin command "$@"
    }
    tangle_subtask_fallback_agents "$1"
)

for routed_agent in codex codex-standard; do
    test_case "$routed_agent is skipped when the Codex executable disappears"
    if [[ "$(missing_codex_candidates "$routed_agent" 'codex claude')" == "claude-sonnet" ]] &&
       [[ -z "$(missing_codex_candidates "$routed_agent" codex)" ]]; then
        test_pass
    else
        test_fail "the missing Codex executable remained a candidate or the allowlist was ignored"
    fi
done

run_correction() (
    export OCTO_ALLOWED_PROVIDERS="$1"
    PATH="$STUB_BIN:$PATH"
    source "$PROJECT_ROOT/scripts/lib/agent-spec.sh"
    source "$PROJECT_ROOT/scripts/lib/provider-allowlist.sh"
    source "$PROJECT_ROOT/scripts/lib/quota-watcher.sh"
    source "$PROJECT_ROOT/scripts/provider-router.sh"
    source "$PROJECT_ROOT/scripts/lib/workflows.sh"

    RESULTS_DIR="$TEST_TMP_DIR/correction-$2"
    WORKSPACE_DIR="$RESULTS_DIR/workspace"
    _OCTO_QUOTA_RUN_DEAD=" "
    _PROVIDER_STATE_DIR="$RESULTS_DIR/provider-state"
    mkdir -p "$_PROVIDER_STATE_DIR"
    case "$2" in
        circuit) date +%s > "$_PROVIDER_STATE_DIR/codex.cooldown" ;;
        quota|excluded) octo_quota_mark_dead codex ;;
    esac
    printf '%s\n' '{"findings":[{"severity":"normal","title":"Fix the fixture"}]}' > "$RESULTS_DIR/findings.json"
    log() { :; }
    tangle_worktree_fingerprint() { printf '%s\n' fixture; }
    tangle_scope_contamination_summary() { :; }
    get_agent_model() { printf '%s\n' fixture-model; }
    run_agent_sync() {
        printf '%s\n' "$1" > "$RESULTS_DIR/dispatched"
        tangle_subtask_agent_dispatchable "$1"
    }

    local rc=0 dispatched="none"
    tangle_apply_review_corrections "Implement fixture" context "$RESULTS_DIR/findings.json" 1 codex || rc=$?
    [[ ! -f "$RESULTS_DIR/dispatched" ]] || dispatched=$(<"$RESULTS_DIR/dispatched")
    printf '%s %s %s\n' "$rc" "$TANGLE_CORRECTION_STATUS" "$dispatched"
)

for scenario in healthy circuit quota excluded; do
    test_case "correction dispatch selects an allowed, healthy implementer ($scenario)"
    allowlist='codex claude'
    case "$scenario" in
        healthy) expected='0 completed codex' ;;
        circuit|quota) expected='0 completed claude-sonnet' ;;
        excluded) allowlist=codex; expected='1 provider-unavailable none' ;;
    esac
    got=$(run_correction "$allowlist" "$scenario")
    if [[ "$got" == "$expected" ]]; then
        test_pass
    else
        test_fail "expected '$expected', got '$got'"
    fi
done

run_scenario() (
    local name="$1"
    SCENARIO="$2"
    local allowlist="${3:-}"
    local dir="$TEST_TMP_DIR/circuit-fallback-$name"
    rm -rf "$dir"
    mkdir -p "$dir"
    export HOME="$dir/home"
    mkdir -p "$HOME"
    if [[ -n "$allowlist" ]]; then
        export OCTO_ALLOWED_PROVIDERS="$allowlist"
    fi
    PATH="$STUB_BIN:$PATH"

    source "$PROJECT_ROOT/scripts/lib/testing.sh"
    source "$PROJECT_ROOT/scripts/lib/agent-spec.sh"
    source "$PROJECT_ROOT/scripts/lib/provider-allowlist.sh"
    source "$PROJECT_ROOT/scripts/lib/quota-watcher.sh"
    source "$PROJECT_ROOT/scripts/provider-router.sh"
    source "$PROJECT_ROOT/scripts/lib/workflows.sh"

    CYAN="" GREEN="" MAGENTA="" NC=""
    TMUX_MODE=false
    DRY_RUN=false
    SUPPORTS_PARALLEL_FILE_SAFETY=false
    RESULTS_DIR="$dir/results"
    LOGS_DIR="$RESULTS_DIR/logs"
    WORKSPACE_DIR="$dir/workspace"
    _PROVIDER_STATE_DIR="$dir/provider-state"
    CAPTURE="$dir/capture"
    mkdir -p "$WORKSPACE_DIR/.octo/agents" "$LOGS_DIR" "$_PROVIDER_STATE_DIR"
    : > "$CAPTURE"

    log() { :; }
    octopus_phase_banner() { :; }
    display_workflow_cost_estimate() { return 0; }
    reset_provider_lockouts() { :; }
    design_review_ceremony() { :; }
    fleet_dispatch_begin() { :; }
    fleet_dispatch_end() { :; }
    validate_tangle_results() { :; }
    octopus_tangle_cancel_active() { :; }

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

    codex_dies() {
        case "$SCENARIO" in
            circuit-*) date +%s > "$_PROVIDER_STATE_DIR/codex.cooldown" ;;
            quota-*) octo_quota_mark_dead codex ;;
        esac
    }

    spawn_agent_capture_pid() {
        local agent="$1" task_id="$3" role="$4" provider attempts
        cat >/dev/null || true
        printf 'attempt %s %s\n' "$task_id" "$agent" >> "$CAPTURE"
        attempts=$(grep -c '^attempt ' "$CAPTURE")
        if [[ "$attempts" -eq 2 && "$SCENARIO" == *-during-spawn ]]; then
            codex_dies
            # A lost PID handoff is ambiguous even if provider health changed.
            [[ "$SCENARIO" != circuit-lost-handoff-during-spawn ]] || return 1
        fi
        provider="$(octo_agent_spec_provider "$agent")"
        is_provider_available "$provider" || return 75
        octo_quota_is_dead "$provider" && return 75
        if [[ "$attempts" -eq 2 && "$SCENARIO" == refused ]]; then
            return 1
        fi
        printf 'spawned %s %s|%s\n' "$task_id" "$agent" "$role" >> "$CAPTURE"
        printf '0\n' > "$WORKSPACE_DIR/.octo/agents/${task_id}.done"
        if [[ "$attempts" -eq 1 && "$SCENARIO" == *-after-first ]]; then
            codex_dies
        fi
        printf '12345\n'
    }

    local rc=0
    tangle_develop "Implement the two-part plan." >/dev/null 2>&1 || rc=$?
    printf 'rc=%s\n' "$rc"
    sed -E 's/tangle-[^ ]*-([0-9]+) /task\1 /' "$CAPTURE"
)

expect_scenario() {
    local title="$1" expected="$2"
    shift 2
    test_case "$title"
    local got
    got="$(run_scenario "$@")"
    if [[ "$got" == "$expected" ]]; then
        test_pass
    else
        test_fail "expected:
$expected
got:
$got"
    fi
}

expect_scenario "codex circuit opens while subtask 1 runs: subtask 2 moves to claude-sonnet" \
"rc=0
attempt task0 codex
spawned task0 codex|implementer
attempt task1 claude-sonnet
spawned task1 claude-sonnet|implementer" \
    circuit-after-first circuit-after-first

expect_scenario "codex circuit opens during subtask 2's own spawn: it retries on claude-sonnet" \
"rc=0
attempt task0 codex
spawned task0 codex|implementer
attempt task1 codex
attempt task1 claude-sonnet
spawned task1 claude-sonnet|implementer" \
    circuit-during-spawn circuit-during-spawn

expect_scenario "a lost PID handoff does not permit another worker despite the open circuit" \
"rc=1
attempt task0 codex
spawned task0 codex|implementer
attempt task1 codex" \
    lost-handoff circuit-lost-handoff-during-spawn

expect_scenario "codex marked quota-dead while subtask 1 runs: subtask 2 moves to claude-sonnet" \
"rc=0
attempt task0 codex
spawned task0 codex|implementer
attempt task1 claude-sonnet
spawned task1 claude-sonnet|implementer" \
    quota-after-first quota-after-first

expect_scenario "allowlist 'codex claude' still admits claude-sonnet as the replacement" \
"rc=0
attempt task0 codex
spawned task0 codex|implementer
attempt task1 claude-sonnet
spawned task1 claude-sonnet|implementer" \
    allowlist-codex-claude circuit-after-first "codex claude"

expect_scenario "allowlist 'codex' has no replacement, so the run still aborts" \
"rc=1
attempt task0 codex
spawned task0 codex|implementer" \
    allowlist-codex-only circuit-after-first "codex"

expect_scenario "a refusal with codex still healthy is a real failure and still aborts" \
"rc=1
attempt task0 codex
spawned task0 codex|implementer
attempt task1 codex" \
    refused refused

test_summary
