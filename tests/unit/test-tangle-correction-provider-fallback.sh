#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "tangle correction round moves off a dead provider"

unset OCTO_ALLOWED_PROVIDERS
mkdir -p "$TEST_TMP_DIR/provider-allowlist"
export OCTOPUS_CONFIG_DIR="$TEST_TMP_DIR/provider-allowlist"

STUB_BIN="$TEST_TMP_DIR/correction-fallback-bin"
mkdir -p "$STUB_BIN"
printf '#!/bin/sh\nexit 0\n' > "$STUB_BIN/codex"
chmod +x "$STUB_BIN/codex"

run_correction() (
    local name="$1"
    SCENARIO="$2"
    local allowlist="${3:-}"
    local dir="$TEST_TMP_DIR/correction-fallback-$name"
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

    RESULTS_DIR="$dir/results"
    WORKSPACE_DIR="$dir/workspace"
    _PROVIDER_STATE_DIR="$dir/provider-state"
    CAPTURE="$dir/capture"
    WORKTREE_STATE="$dir/worktree-state"
    mkdir -p "$RESULTS_DIR" "$WORKSPACE_DIR" "$_PROVIDER_STATE_DIR"
    : > "$CAPTURE"
    printf 'clean\n' > "$WORKTREE_STATE"

    log() { :; }
    tangle_normal_findings_summary() { printf 'app.ts:1 blocking finding\n'; }
    tangle_correction_strategy_prompt() { :; }
    tangle_worktree_fingerprint() { cat "$WORKTREE_STATE"; }
    tangle_scope_contamination_summary() { :; }
    get_agent_model() { printf 'fixture-model\n'; }

    case "$SCENARIO" in
        circuit-before) date +%s > "$_PROVIDER_STATE_DIR/codex.cooldown" ;;
        quota-before) octo_quota_mark_dead codex ;;
    esac

    run_agent_sync() {
        local agent="$1"
        printf 'dispatch %s\n' "$agent" >> "$CAPTURE"
        if [[ "$agent" == codex ]]; then
            if [[ "$SCENARIO" == quota-during ]]; then
                octo_quota_mark_dead codex
            fi
            if octo_quota_is_dead codex || ! is_provider_available codex; then
                printf "ERROR: You've hit your usage limit.\n"
                return 1
            fi
            if [[ "$SCENARIO" == fails-healthy ]]; then
                printf 'ERROR: the fix did not compile\n'
                return 1
            fi
        fi
        printf 'edited by %s\n' "$agent" > "$WORKTREE_STATE"
        printf 'fixed the finding\n'
    }

    local rc=0
    tangle_apply_review_corrections "prompt" "$dir/context.md" "$dir/findings.json" 1 codex delta >/dev/null 2>&1 || rc=$?
    printf 'rc=%s status=%s\n' "$rc" "${TANGLE_CORRECTION_STATUS:-}"
    cat "$CAPTURE"
)

expect_correction() {
    local title="$1" expected="$2"
    shift 2
    test_case "$title"
    local got
    got="$(run_correction "$@")"
    if [[ "$got" == "$expected" ]]; then
        test_pass
    else
        test_fail "expected:
$expected
got:
$got"
    fi
}

expect_correction "a healthy codex runs the correction round itself" \
"rc=0 status=completed
dispatch codex" \
    healthy healthy

expect_correction "codex quota-dead before the round: the round runs on claude-sonnet" \
"rc=0 status=completed
dispatch claude-sonnet" \
    quota-before quota-before

expect_correction "codex circuit open before the round: the round runs on claude-sonnet" \
"rc=0 status=completed
dispatch claude-sonnet" \
    circuit-before circuit-before

expect_correction "codex dies during the round without writing: the same round reruns on claude-sonnet" \
"rc=0 status=completed
dispatch codex
dispatch claude-sonnet" \
    quota-during quota-during

expect_correction "a failure with codex still healthy is not retried elsewhere" \
"rc=1 status=failed-no-progress
dispatch codex" \
    fails-healthy fails-healthy

expect_correction "allowlist 'codex' with codex dead dispatches nothing and stops the loop" \
"rc=1 status=provider-unavailable" \
    allowlist-codex-only quota-before "codex"

test_summary
