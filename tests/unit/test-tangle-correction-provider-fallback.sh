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
    REPO_DIR="$dir/repo"
    _PROVIDER_STATE_DIR="$dir/provider-state"
    CAPTURE="$dir/capture"
    mkdir -p "$RESULTS_DIR" "$WORKSPACE_DIR" "$REPO_DIR" "$_PROVIDER_STATE_DIR"
    : > "$CAPTURE"
    git -C "$REPO_DIR" init -q
    printf 'base\n' > "$REPO_DIR/tracked"
    git -C "$REPO_DIR" add tracked
    git -C "$REPO_DIR" -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm base

    log() { :; }
    tangle_normal_findings_summary() { printf 'app.ts:1 blocking finding\n'; }
    tangle_correction_strategy_prompt() { :; }
    tangle_resolve_repo_root() { printf '%s\n' "$REPO_DIR"; }
    tangle_scope_contamination_summary() { :; }
    get_agent_model() { printf 'fixture-model\n'; }

    case "$SCENARIO" in
        circuit-before) date +%s > "$_PROVIDER_STATE_DIR/codex.cooldown" ;;
        quota-before) octo_quota_mark_dead codex ;;
        quota-tracked-edit) printf 'edit\n' > "$REPO_DIR/tracked" ;;
        quota-untracked-edit) printf 'edit\n' > "$REPO_DIR/untracked" ;;
    esac

    run_agent_sync() {
        local agent="$1"
        printf 'dispatch %s\n' "$agent" >> "$CAPTURE"
        if [[ "$agent" == codex ]]; then
            case "$SCENARIO" in
                quota-during) octo_quota_mark_dead codex ;;
                quota-interrupted-wrapper|quota-missing-record)
                    octo_quota_mark_dead codex
                    if [[ "$SCENARIO" == quota-interrupted-wrapper ]]; then
                        exec bash -c 'kill -KILL "$$"'
                    fi
                    exit 0
                    ;;
                quota-invalid-record)
                    octo_quota_mark_dead codex
                    printf() { builtin printf 'invalid\n'; }
                    return 1
                    ;;
                quota-tracked-edit)
                    printf 'next\n' > "$REPO_DIR/tracked"
                    octo_quota_mark_dead codex
                    ;;
                quota-untracked-edit)
                    printf 'next\n' > "$REPO_DIR/untracked"
                    octo_quota_mark_dead codex
                    ;;
                circuit-during) date +%s > "$_PROVIDER_STATE_DIR/codex.cooldown" ;;
            esac
            if octo_quota_is_dead codex || ! is_provider_available codex; then
                printf "ERROR: You've hit your usage limit.\n"
                return 1
            fi
            if [[ "$SCENARIO" == fails-healthy ]]; then
                printf 'ERROR: the fix did not compile\n'
                return 1
            fi
        fi
        printf 'edited by %s\n' "$agent" > "$REPO_DIR/tracked"
        printf 'fixed the finding\n'
    }

    local rc=0
    tangle_apply_review_corrections "prompt" "$dir/context.md" "$dir/findings.json" 1 codex delta >/dev/null 2>&1 || rc=$?
    printf 'rc=%s status=%s\n' "$rc" "${TANGLE_CORRECTION_STATUS:-}"
    cat "$CAPTURE"
    if [[ "$SCENARIO" == quota-during && "$rc" == 0 ]]; then
        local failures=("$RESULTS_DIR"/tangle-review-corrections-1-codex-*.md)
        if [[ ${#failures[@]} != 1 || ! -f "${failures[0]}" ]] ||
            ! grep -Fq 'FAILED - NO PROGRESS' "${failures[0]}"; then
            printf 'The original failed correction transcript was not retained.\n'
        fi
        if ! grep -Fq 'Status: SUCCESS' "$TANGLE_CORRECTION_FILE"; then
            printf 'The latest correction transcript did not record success.\n'
        fi
    fi
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

expect_correction "a stale codex route does not override the claude-only allowlist" \
"rc=0 status=completed
dispatch claude-sonnet" \
    stale-route healthy claude

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

expect_correction "a circuit opens during a correction without writes" \
"rc=0 status=completed
dispatch codex
dispatch claude-sonnet" \
    circuit-during circuit-during

for file_kind in tracked untracked; do
    expect_correction "an equal-size edit to an existing $file_kind file keeps the partial correction" \
"rc=0 status=failed-partial
dispatch codex" \
        "quota-$file_kind-edit" "quota-$file_kind-edit"
done

expect_correction "a provider lost during the round stops when the allowlist has no fallback" \
"rc=1 status=provider-unavailable
dispatch codex" \
    exhausted quota-during codex

expect_correction "a failure with codex still healthy is not retried elsewhere" \
"rc=1 status=failed-no-progress
dispatch codex" \
    fails-healthy fails-healthy

expect_correction "allowlist 'codex' with codex dead dispatches nothing and stops the loop" \
"rc=1 status=provider-unavailable" \
    allowlist-codex-only quota-before "codex"

for scenario in quota-interrupted-wrapper quota-missing-record quota-invalid-record; do
    expect_correction "$scenario stops the round without launching a fallback" \
"rc=1 status=interrupted-partial
dispatch codex" \
        "$scenario" "$scenario"
done

test_summary
