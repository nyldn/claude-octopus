#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "embrace debate gate provider failure reasons"

run_gate() (
    local scenario="$1" codex_mode="$2" claude_mode="${3:-ok}"
    local root="$TEST_TMP_DIR/$scenario"
    mkdir -p "$root/home" "$root/results" "$root/logs" "$root/workspace"
    export HOME="$root/home" WORKSPACE_DIR="$root/workspace"
    export RESULTS_DIR="$root/results" LOGS_DIR="$root/logs"
    export OCTOPUS_TASK_GROUP="$scenario" FIXTURE_ROOT="$root"

    cat > "$root/codex" <<EOF
#!/usr/bin/env bash
cat >/dev/null
printf '%s\n' 'OpenAI Codex v0.150.0 (research preview)' '--------' 'user' 'review the change' >&2
case "$codex_mode" in
    usage-limit)
        printf '%s\n' "ERROR: You've hit your usage limit. Upgrade to Pro (https://chatgpt.com/explore/pro), visit https://chatgpt.com/codex/settings/usage to purchase more credits or try again at Nov 20th, 2026 12:27 AM." >&2 ;;
    other)
        printf '%s\n' 'ERROR: The model gpt-unknown does not exist or you do not have access to it.' >&2 ;;
esac
exit 1
EOF
    cat > "$root/claude" <<EOF
#!/usr/bin/env bash
prompt="\$(cat)"
if [[ "$claude_mode" == fail ]]; then
    printf '%s\n' 'ERROR: claude reported an internal server error' >&2
    exit 1
fi
if [[ "\$prompt" == *"Synthesize this Embrace"* ]]; then
    printf '%s' "\$prompt" > "\$FIXTURE_ROOT/synthesis-prompt"
    printf '%s\n' 'Gate verdict: PROCEED_WITH_RISKS. Codex did not participate.'
else
    printf '%s\n' 'Verdict: PROCEED_WITH_RISKS' 'Blocking issues: none found in the context artifact.'
fi
EOF
    chmod 755 "$root/codex" "$root/claude"
    printf '%s\n' '# Develop summary' 'All slices implemented.' > "$root/context.md"

    source "$PROJECT_ROOT/scripts/lib/agent-sync.sh"
    source "$PROJECT_ROOT/scripts/lib/secure.sh"
    source "$PROJECT_ROOT/scripts/lib/workflows.sh"

    log() { :; }
    classify_task() { printf 'standard\n'; }
    compute_dynamic_timeout() { printf '30\n'; }
    get_role_for_context() { printf 'reviewer\n'; }
    apply_persona() { printf '%s\n' "$2"; }
    load_earned_skills() { :; }
    build_provider_context() { :; }
    enforce_context_budget() { printf '%s\n' "$1"; }
    get_agent_model() { printf 'fixture-model\n'; }
    estimate_agent_call_cost() { printf '0.000000\n'; }
    check_provider_health() { return 0; }
    record_agent_call() { :; }
    get_agent_command() {
        case "$1" in
            codex*) printf '%s\n' "$FIXTURE_ROOT/codex" ;;
            *) printf '%s\n' "$FIXTURE_ROOT/claude" ;;
        esac
    }
    build_provider_env() { PROVIDER_ENV_ARRAY=(); }
    run_with_timeout() { shift; "$@"; }
    stop_quota_watcher() { :; }
    update_agent_status() { :; }
    octo_estimate_tokens_for_file() { printf '0\n'; }
    write_agent_status() { :; }
    octo_provider_allowed() { [[ "$1" != agy ]]; }
    save_session_checkpoint() { :; }
    write_structured_decision() { :; }

    set +e
    OCTOPUS_PERSISTENCE_AVAILABLE=true CODEX_SUBAGENT_PREAMBLE="" \
        embrace_debate_gate develop-deliver 'Review delivery readiness' "$root/context.md" >"$root/gate.out" 2>&1
)

test_case "a codex usage-limit failure is named in the gate artifact and the synthesis prompt"
run_gate usage-limit usage-limit && rc=0 || rc=$?
artifact="$TEST_TMP_DIR/usage-limit/results/embrace-gate-develop-deliver-usage-limit.md"
synthesis_prompt="$TEST_TMP_DIR/usage-limit/synthesis-prompt"
reason='usage limit reached; try again at Nov 20th, 2026 12:27 AM'
if [[ "$rc" -eq 0 && -f "$artifact" && -f "$synthesis_prompt" ]] &&
   grep -Fxq "**Provider Statuses:** codex=failed (${reason}), agy=skipped, claude=ok" "$artifact" &&
   grep -Fxq "No output. Failure reason: ${reason}" "$artifact" &&
   grep -Fxq "Provider statuses: codex=failed (${reason}), agy=skipped, claude=ok" "$synthesis_prompt" &&
   grep -Fxq "[no output; failure reason: ${reason}]" "$synthesis_prompt"; then
    test_pass
else
    test_fail "rc=$rc statuses=$(grep -F 'Provider Statuses' "$artifact" 2>/dev/null || echo missing)"
fi

test_case "the failed seat's diagnostic is kept privately next to the gate artifact"
capture="$TEST_TMP_DIR/usage-limit/results/embrace-gate-develop-deliver-usage-limit-codex.stderr.log"
mode="$(stat -c '%a' "$capture" 2>/dev/null || stat -f '%Lp' "$capture" 2>/dev/null || true)"
if [[ "$mode" == 600 ]] && grep -q "^ERROR: You've hit your usage limit" "$capture" &&
   [[ ! -e "$TEST_TMP_DIR/usage-limit/results/embrace-gate-develop-deliver-usage-limit-claude.stderr.log" ]]; then
    test_pass
else
    test_fail "mode=$mode capture=$(tr '\n' '|' < "$capture" 2>/dev/null)"
fi

test_case "a non-quota codex failure reports the provider's error line"
run_gate other-error other && rc=0 || rc=$?
artifact="$TEST_TMP_DIR/other-error/results/embrace-gate-develop-deliver-other-error.md"
reason='Exit code 1: The model gpt-unknown does not exist or you do not have access to it.'
if [[ "$rc" -eq 0 ]] &&
   grep -Fxq "**Provider Statuses:** codex=failed (${reason}), agy=skipped, claude=ok" "$artifact" &&
   grep -Fxq "No output. Failure reason: ${reason}" "$artifact" &&
   ! grep -Fq 'usage limit' "$artifact"; then
    test_pass
else
    test_fail "rc=$rc statuses=$(grep -F 'Provider Statuses' "$artifact" 2>/dev/null || echo missing)"
fi

test_case "a gate whose every seat fails names each reason in its error"
run_gate all-failed usage-limit fail && rc=0 || rc=$?
gate_out="$TEST_TMP_DIR/all-failed/gate.out"
if [[ "$rc" -ne 0 && ! -e "$TEST_TMP_DIR/all-failed/results/embrace-gate-develop-deliver-all-failed.md" ]] &&
   grep -Fq 'produced no provider output: codex=failed (usage limit reached; try again at Nov 20th, 2026 12:27 AM), agy=skipped, claude=failed (Exit code 1: claude reported an internal server error)' "$gate_out"; then
    test_pass
else
    test_fail "rc=$rc output=$(tr '\n' '|' < "$gate_out" 2>/dev/null)"
fi

test_summary
