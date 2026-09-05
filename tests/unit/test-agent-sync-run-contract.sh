#!/usr/bin/env bash
# Typed lifecycle coverage for synchronous provider dispatch.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "synchronous v10 run contract"

# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/run-contract.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/error-tracking.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/agent-sync.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/validation.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/kimi.sh"

eval "$(declare -f run_contract_transition | sed '1s/run_contract_transition/_fixture_run_contract_transition/')"
run_contract_transition() {
    if [[ "${FIXTURE_SCENARIO:-}" == usage-running-transition-fail && "${2:-}" == running ]]; then
        return 1
    fi
    _fixture_run_contract_transition "$@"
}

fixture_provider="$TEST_TMP_DIR/fixture-provider.sh"
cat > "$fixture_provider" <<'EOF'
#!/usr/bin/env bash
attempt=0
[[ -f "$FIXTURE_CALLS" ]] && attempt="$(wc -l < "$FIXTURE_CALLS" | tr -d ' ')"
attempt=$((attempt + 1))
printf '%s\n' "$attempt" >> "$FIXTURE_CALLS"
case "$FIXTURE_SCENARIO" in
    success|exact-seat|kimi-success) printf '%s\n' 'Substantive provider result.' ;;
    agy-pin)
        printf '%s\n' "${OCTOPUS_AGY_MODEL:-missing}" > "$FIXTURE_ROOT/executed-agy-model"
        printf '%s\n' 'Substantive AGY result.'
        ;;
    empty) : ;;
    whitespace) printf ' \n\t\n' ;;
    placeholder) printf '%s\n' 'Provider available' ;;
    oversize) printf '%s\n' 'Prompt is too long for the context limit' ;;
    timeout) printf '%s\n' 'partial output' ; exit 124 ;;
    sigsegv)
        if [[ "$attempt" -eq 1 ]]; then
            printf '%s\n' 'synthetic segfault' >&2
            exit 139
        fi
        printf '%s\n' 'Recovered substantive provider result.'
        ;;
    stdin-close)
        printf '%s\n' 'Substantive Codex review result.'
        printf '%s\n' 'write_stdin failed: stdin is closed for this session' >&2
        ;;
    stdin-close-large)
        printf '%s\n' 'Provider available'
        printf '%s\n' '## Verification' >&2
        printf '%0500d\n' 0 | tr '0' 'E' >&2
        printf '%s\n' 'write_stdin failed: stdin is closed for this session' >&2
        ;;
    truncated)
        printf '%0500d\n' 0 | tr '0' 'A'
        ;;
    *) printf '%s\n' "unknown fixture: $FIXTURE_SCENARIO" >&2; exit 2 ;;
esac
EOF
chmod 755 "$fixture_provider"

kimi_config_bin="$TEST_TMP_DIR/kimi-config-bin"
mkdir -p "$kimi_config_bin"
cat > "$kimi_config_bin/kimi" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    __plugin_run_node) shift; exec "${KIMI_TEST_NODE:?}" "$@" ;;
    doctor|provider) exec "${KIMI_TEST_NODE:?}" "${KIMI_TEST_DRIVER:?}" "$@" ;;
    *) exit 1 ;;
esac
EOF
chmod 755 "$kimi_config_bin/kimi"
export KIMI_TEST_NODE="$(command -v node)"
export KIMI_TEST_DRIVER="$PROJECT_ROOT/tests/fixtures/kimi-code-cli-mock.mjs"
PATH="$kimi_config_bin:$PATH"

log() { :; }
classify_task() { printf '%s\n' standard; }
get_role_for_context() { printf '%s\n' reviewer; }
apply_persona() { printf '%s\n' "$2"; }
load_earned_skills() { :; }
build_provider_context() { :; }
enforce_context_budget() { printf '%s\n' "$1"; }
octo_prompt_byte_length() { LC_ALL=C printf '%s' "$1" | wc -c | tr -d '[:space:]'; }
octo_dispatch_command_model() {
    printf '%s\n' "$1" | awk -v fallback="$2" '
        { for (i = 1; i <= NF; i++) if ($i == "--model" && i < NF) { print $(i + 1); found=1; exit } }
        END { if (!found) print fallback }
    '
}
get_agent_model() {
    [[ "${FIXTURE_SCENARIO:-}" == model-fail ]] && return 1
    if [[ "${1:-}" == *:* ]]; then
        printf '%s\n' "${1#*:}"
        return 0
    fi
    [[ "${FIXTURE_SCENARIO:-}" == agy-pin ]] && { printf '%s\n' 'Gemini 3.1 Pro (High)'; return 0; }
    printf '%s\n' fixture-model
}
estimate_agent_call_cost() { printf '%s\n' 0.000000; }
record_agent_start() { printf '%s\n' "call-${FIXTURE_SCENARIO:-unknown}"; }
record_agent_call() { :; }
record_agent_complete() {
    printf 'completed|%s\n' "$1" >> "$FIXTURE_ROOT/usage-terminal"
}
record_agent_failure() {
    printf '%s|%s|%s\n' "${4:-failed}" "$1" "${3:-}" >> "$FIXTURE_ROOT/usage-terminal"
}
parse_task_metrics() {
    _PARSED_TOKENS="" _PARSED_TOOL_USES="" _PARSED_DURATION_MS=""
    _PARSED_INPUT_TOKENS="" _PARSED_OUTPUT_TOKENS=""
    _PARSED_CACHED_INPUT_TOKENS="" _PARSED_CACHE_WRITE_TOKENS=""
    _PARSED_REASONING_TOKENS=""
}
get_agent_command() {
    local command_model="routed-model"
    if [[ "${1:-}" == *:* ]]; then
        command_model="${1#*:}"
    fi
    printf '%s\n' "${4:-missing}" > "$FIXTURE_ROOT/prompt-bytes"
    if [[ "${FIXTURE_SCENARIO:-}" == agy-pin ]]; then
        printf '%s\n' "$fixture_provider"
        return 0
    fi
    printf '%s\n' "$fixture_provider --model $command_model"
}
build_provider_env() { PROVIDER_ENV_ARRAY=(); }
run_with_timeout() { shift; "$@"; }
stop_quota_watcher() { :; }
update_agent_status() { :; }
octo_estimate_tokens_for_file() { printf '%s\n' 0; }
write_agent_status() {
    printf '%s|%s|%s|%s|%s\n' "$1" "$2" "$5" "$7" "$8" >> "$FIXTURE_ROOT/legacy-statuses"
}
check_provider_health() {
    if [[ "$1" == kimi ]]; then
        printf '%s\n' "${2:-missing}" > "$FIXTURE_ROOT/health-model"
    fi
    if [[ "$FIXTURE_SCENARIO" == kimi-dangling-default ]]; then
        if ! KIMI_CODE_HOME="$PROJECT_ROOT/tests/fixtures/kimi-dangling-default" \
            OCTOPUS_KIMI_MODEL="${2:-}" \
            kimi_configured_credential_method >/dev/null 2>&1; then
            printf '%s\n' 'fixture dangling Kimi default'
            return 1
        fi
    fi
    if [[ "$FIXTURE_SCENARIO" == auth-fail || "$FIXTURE_SCENARIO" == health-fail-qwen ]]; then
        printf '%s\n' 'fixture authentication rejected'
        return 1
    fi
    return 0
}

export CODEX_SUBAGENT_PREAMBLE=""

run_fixture() {
    local scenario="$1" agent_type="${2:-codex}"
    local role="reviewer" phase="probe"
    if [[ "$scenario" == exact-seat ]]; then
        role="implementation-verifier"
        phase="review"
    fi
    export FIXTURE_SCENARIO="$scenario"
    export FIXTURE_ROOT="$TEST_TMP_DIR/$scenario"
    export FIXTURE_CALLS="$FIXTURE_ROOT/provider-calls"
    export WORKSPACE_DIR="$FIXTURE_ROOT/workspace"
    export RESULTS_DIR="$FIXTURE_ROOT/results"
    export OCTOPUS_RUN_ID="sync-$scenario"
    export OCTOPUS_AGENT_MAX_OUTPUT_BYTES=262144
    export OCTOPUS_PERSISTENCE_AVAILABLE=true
    [[ "$scenario" == truncated ]] && export OCTOPUS_AGENT_MAX_OUTPUT_BYTES=120
    [[ "$scenario" == stdin-close-large ]] && export OCTOPUS_AGENT_MAX_OUTPUT_BYTES=256
    [[ "$scenario" == persistence-fail ]] && export OCTOPUS_PERSISTENCE_AVAILABLE=false
    mkdir -p "$RESULTS_DIR"

    set +e
    run_agent_sync "$agent_type" 'Review the fixture.' 5 "$role" "$phase" \
        > "$FIXTURE_ROOT/stdout" 2> "$FIXTURE_ROOT/stderr"
    fixture_rc=$?
    set -e
    printf '%s\n' "$fixture_rc" > "$FIXTURE_ROOT/rc"
}

assert_scenario() {
    local scenario="$1" expected_rc="$2" expected_calls="$3"
    local expected_transitions="$4" expected_terminal="$5"
    local expected_contribution="$6" expected_reason="$7" agent_type="${8:-codex}"
    local root ledger actual_calls actual_transitions actual_terminal actual_contribution actual_reason

    run_fixture "$scenario" "$agent_type"
    root="$TEST_TMP_DIR/$scenario"
    ledger="$root/workspace/runs/sync-$scenario/seats.jsonl"
    if [[ -f "$root/provider-calls" ]]; then
        actual_calls="$(wc -l < "$root/provider-calls" | tr -d ' ')"
    else
        actual_calls=0
    fi
    actual_transitions="$(jq -r '.transition' "$ledger" 2>/dev/null | paste -sd, - || true)"
    actual_terminal="$(jq -r '.transition' "$ledger" 2>/dev/null | tail -n 1 || true)"
    actual_contribution="$(jq -r '.contribution' "$ledger" 2>/dev/null | tail -n 1 || true)"
    actual_reason="$(jq -r '.reason' "$ledger" 2>/dev/null | tail -n 1 || true)"

    test_case "$scenario has an exact synchronous lifecycle oracle"
    if [[ "$(cat "$root/rc")" == "$expected_rc" ]] && \
       [[ "$actual_calls" == "$expected_calls" ]] && \
       [[ "$actual_transitions" == "$expected_transitions" ]] && \
       [[ "$actual_terminal" == "$expected_terminal" ]] && \
       [[ "$actual_contribution" == "$expected_contribution" ]] && \
       [[ "$actual_reason" == "$expected_reason" ]] && \
       jq -e --arg terminal "$expected_terminal" '
           .schema_version == "10.0" and
           (.seats | length == 1) and
           .seats[0].transition == $terminal
       ' "$root/workspace/runs/sync-$scenario/seats.json" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "rc=$(cat "$root/rc") calls=$actual_calls transitions=${actual_transitions:-missing} terminal=${actual_terminal:-missing} contribution=${actual_contribution:-missing} reason=${actual_reason:-missing}"
    fi
}

assert_scenario success 0 1 \
    planned,starting,authenticated,running,output_received,validated,contributed \
    contributed eligible ''
assert_scenario exact-seat 0 1 \
    planned,starting,authenticated,running,output_received,validated,contributed \
    contributed eligible '' 'command-code:thinkingmachines/inkling-small'
assert_scenario agy-pin 0 1 \
    planned,starting,authenticated,running,output_received,validated,contributed \
    contributed eligible '' 'agy:Gemini 3.1 Pro (High)'

run_fixture kimi-success kimi-research
test_case "synchronous Kimi output crosses the real untrusted-output boundary"
if grep -q '<external-cli-output provider="kimi-research".*trust="untrusted">' \
       "$TEST_TMP_DIR/kimi-success/stdout" && \
   [[ "$(cat "$TEST_TMP_DIR/kimi-success/health-model")" == fixture-model ]]; then
    test_pass
else
    test_fail "run_agent_sync did not health-check the resolved Kimi model or returned unwrapped output"
fi
assert_scenario kimi-dangling-default 1 0 planned,starting,failed failed none \
    'Provider unavailable: fixture dangling Kimi default' kimi
assert_scenario auth-fail 1 0 planned,starting,failed failed none \
    'Provider unavailable: fixture authentication rejected'
assert_scenario health-fail-qwen 1 0 planned,starting,failed failed none \
    'Provider unavailable: fixture authentication rejected' qwen
assert_scenario persistence-fail 74 0 planned,starting,authenticated,failed failed none \
    'Persistence unavailable'
assert_scenario model-fail 1 0 planned,failed failed none \
    'Model resolution failed'
assert_scenario empty 1 1 planned,starting,authenticated,running,failed failed none \
    'Empty output'
assert_scenario whitespace 1 1 planned,starting,authenticated,running,failed failed none \
    'Empty or placeholder output'
assert_scenario placeholder 1 1 planned,starting,authenticated,running,failed failed none \
    'Empty or placeholder output'
assert_scenario oversize 0 1 planned,starting,authenticated,running,skipped skipped none \
    'Prompt rejected by provider (oversize)'
assert_scenario timeout 124 1 planned,starting,authenticated,running,timeout timeout none \
    'Timed out before completion'
assert_scenario usage-running-transition-fail 74 0 \
    planned,starting,authenticated,failed failed none \
    'Unable to record running state'
assert_scenario sigsegv 0 2 \
    planned,starting,authenticated,running,output_received,validated,degraded \
    degraded eligible-with-warning 'Recovered after AGY exit 139' agy
assert_scenario stdin-close 0 1 \
    planned,starting,authenticated,running,output_received,validated,degraded \
    degraded eligible-with-warning 'Codex stdin closed after substantive output was captured'
assert_scenario stdin-close-large 0 1 \
    planned,starting,authenticated,running,output_received,validated,degraded \
    degraded eligible-with-warning 'Codex stdin closed after substantive output was captured; output truncated'
assert_scenario truncated 0 1 \
    planned,starting,authenticated,running,output_received,validated,degraded \
    degraded eligible-with-warning 'Output truncated'

test_case "a post-reservation lifecycle failure writes one terminal usage event"
usage_terminal="$TEST_TMP_DIR/usage-running-transition-fail/usage-terminal"
if [[ "$(wc -l < "$usage_terminal" | tr -d ' ')" == 1 ]] &&
   grep -Fxq 'failed|call-usage-running-transition-fail|Unable to record running state' "$usage_terminal"; then
    test_pass
else
    test_fail "usage terminal event missing or duplicated: $(cat "$usage_terminal" 2>/dev/null || true)"
fi

test_case "recovery and stdin diagnostics remain durable and attempts are distinct"
sigsegv_snapshot="$TEST_TMP_DIR/sigsegv/workspace/runs/sync-sigsegv/seats.json"
stdin_snapshot="$TEST_TMP_DIR/stdin-close/workspace/runs/sync-stdin-close/seats.json"
sigsegv_stderr="$(jq -r '.seats[0].artifacts.stderr' "$sigsegv_snapshot")"
stdin_stderr="$(jq -r '.seats[0].artifacts.stderr' "$stdin_snapshot")"
if [[ -s "$sigsegv_stderr" ]] && grep -q 'synthetic segfault' "$sigsegv_stderr" && \
   [[ -s "$stdin_stderr" ]] && grep -q 'stdin is closed' "$stdin_stderr" && \
   [[ "$(jq -r '.seats[0].attempt_id' "$sigsegv_snapshot")" == *-attempt-2 ]]; then
    test_pass
else
    test_fail "retry attempt or durable stderr artifacts were not preserved"
fi

test_case "successful synchronous output remains durable after temp cleanup"
success_snapshot="$TEST_TMP_DIR/success/workspace/runs/sync-success/seats.json"
success_artifact=""
if [[ -f "$success_snapshot" ]]; then
    success_artifact="$(jq -r '.seats[0].artifacts.output' "$success_snapshot" 2>/dev/null || true)"
fi
if [[ -s "$success_artifact" ]] && grep -q 'Substantive provider result' "$success_artifact"; then
    test_pass
else
    test_fail "successful output artifact is missing after run_agent_sync cleanup"
fi

test_case "uncapped synchronous artifacts preserve provider bytes exactly"
if [[ "$(tail -c 1 "$success_artifact" | od -An -t x1 | tr -d '[:space:]')" == "0a" ]]; then
    test_pass
else
    test_fail "uncapped provider artifact lost its trailing newline"
fi

test_case "stdout and recovered stderr artifacts obey the byte cap"
truncated_artifact="$(jq -r '.seats[0].artifacts.output' "$TEST_TMP_DIR/truncated/workspace/runs/sync-truncated/seats.json")"
stderr_artifact="$(jq -r '.seats[0].artifacts.output' "$TEST_TMP_DIR/stdin-close-large/workspace/runs/sync-stdin-close-large/seats.json")"
truncated_bytes="$(wc -c < "$truncated_artifact" | tr -d ' ')"
stderr_bytes="$(wc -c < "$stderr_artifact" | tr -d ' ')"
if [[ "$truncated_bytes" -le 120 && "$stderr_bytes" -le 256 ]]; then
    test_pass
else
    test_fail "cap=120 stdout=$truncated_bytes recovered-stderr=$stderr_bytes"
fi

test_case "post-routing model identity is persisted before provider execution"
if [[ "$(jq -r '.seats[0].resolved.model' "$success_snapshot")" == routed-model ]]; then
    test_pass
else
    test_fail "manifest retained the pre-routing model identity"
fi

test_case "exact synchronous seat records canonical provider and literal model"
exact_sync_model="thinkingmachines/inkling-small"
exact_sync_snapshot="$TEST_TMP_DIR/exact-seat/workspace/runs/sync-exact-seat/seats.json"
if jq -e --arg model "$exact_sync_model" '
    .seats[0].requested.provider == "commandcode" and
    .seats[0].requested.model == $model and
    .seats[0].resolved.provider == "commandcode" and
    .seats[0].resolved.model == $model and
    .seats[0].execution.phase == "review" and
    .seats[0].execution.role == "implementation-verifier"
' "$exact_sync_snapshot" >/dev/null; then
    test_pass
else
    test_fail "exact synchronous lifecycle did not split canonical provider from literal model"
fi

test_case "exact synchronous Fable SDK seat executes with no retry and retains lifecycle identity"
if (
    export FIXTURE_SCENARIO=exact-fable-runtime
    export FIXTURE_ROOT="$TEST_TMP_DIR/exact-fable-runtime"
    export FIXTURE_CALLS="$FIXTURE_ROOT/provider-calls"
    export WORKSPACE_DIR="$FIXTURE_ROOT/workspace"
    export RESULTS_DIR="$FIXTURE_ROOT/results"
    export OCTOPUS_RUN_ID=sync-exact-fable-runtime
    export OCTOPUS_PERSISTENCE_AVAILABLE=true
    export OCTOPUS_AGENT_MAX_OUTPUT_BYTES=262144
    export CLAUDE_SDK_API_KEY=fixture-key
    export PLUGIN_DIR="$PROJECT_ROOT"
    mkdir -p "$RESULTS_DIR" "$FIXTURE_ROOT/bin"
    sdk_capture="$FIXTURE_ROOT/sdk-capture"
    export SDK_CAPTURE="$sdk_capture"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'printf "%s\n" "no_retry=${OCTOPUS_FABLE5_NO_RETRY:-unset}" > "$SDK_CAPTURE"' \
        'printf "%s\n" "$@" >> "$SDK_CAPTURE"' \
        'cat >/dev/null' \
        'printf "%s\n" "Substantive exact Fable SDK result."' > "$FIXTURE_ROOT/bin/claude-agent"
    chmod 755 "$FIXTURE_ROOT/bin/claude-agent"
    export PATH="$FIXTURE_ROOT/bin:$PATH"
    source "$PROJECT_ROOT/scripts/lib/provider-registry.sh"
    source "$PROJECT_ROOT/scripts/lib/validation.sh"
    source "$PROJECT_ROOT/scripts/lib/model-cache-path.sh"
    source "$PROJECT_ROOT/scripts/lib/model-resolver.sh"
    source "$PROJECT_ROOT/scripts/lib/provider-routing.sh"
    source "$PROJECT_ROOT/scripts/lib/dispatch.sh"
    apply_persona() { printf '%s\n' "$2"; }
    load_earned_skills() { :; }
    build_provider_context() { :; }
    enforce_context_budget() { printf '%s\n' "$1"; }
    build_provider_env() { PROVIDER_ENV_ARRAY=(); }
    sync_rc=0
    run_agent_sync 'claude-sdk:claude-fable-5' 'Review the exact Fable fixture.' 5 \
        implementation-logic-reviewer review > "$FIXTURE_ROOT/stdout" 2> "$FIXTURE_ROOT/stderr" || sync_rc=$?
    if [[ "$sync_rc" -ne 0 ]]; then
        printf 'exact Fable sync rc=%s stderr=%s\n' "$sync_rc" "$(tr '\n' ';' < "$FIXTURE_ROOT/stderr")" >&2
        exit 1
    fi
    snapshot="$WORKSPACE_DIR/runs/$OCTOPUS_RUN_ID/seats.json"
    grep -Fxq 'no_retry=1' "$sdk_capture" &&
    grep -Fxq 'claude-fable-5' "$sdk_capture" &&
    jq -e '
        .seats[0].requested.provider == "claude-sdk" and
        .seats[0].requested.model == "claude-fable-5" and
        .seats[0].resolved.provider == "claude-sdk" and
        .seats[0].resolved.model == "claude-fable-5" and
        .seats[0].transition == "contributed"
    ' "$snapshot" >/dev/null
); then
    test_pass
else
    test_fail "synchronous exact Fable execution retried or lost its lifecycle identity"
fi

test_case "exact AGY model pins reach execution and match lifecycle truth"
agy_pin_snapshot="$TEST_TMP_DIR/agy-pin/workspace/runs/sync-agy-pin/seats.json"
if [[ "$(cat "$TEST_TMP_DIR/agy-pin/executed-agy-model" 2>/dev/null || true)" == 'Gemini 3.1 Pro (High)' ]] && \
   [[ "$(jq -r '.seats[0].resolved.model' "$agy_pin_snapshot")" == 'Gemini 3.1 Pro (High)' ]] && \
   [[ "$(jq -r '.seats[0].resolved.provider' "$agy_pin_snapshot")" == 'agy' ]]; then
    test_pass
else
    test_fail "AGY execution model and lifecycle model diverged: executed=[$(cat "$TEST_TMP_DIR/agy-pin/executed-agy-model" 2>/dev/null || true)] lifecycle-model=[$(jq -r '.seats[0].resolved.model' "$agy_pin_snapshot" 2>/dev/null || true)] lifecycle-provider=[$(jq -r '.seats[0].resolved.provider' "$agy_pin_snapshot" 2>/dev/null || true)]"
fi

test_summary
