#!/usr/bin/env bash
# Council seat token usage and cost in summary.json.
#
# A council round's cost was invisible: summary.json carried only the up-front
# estimate. When the council sets _OCTOPUS_SEAT_USAGE_FILE, claude seats run
# with --output-format json and codex seats with --json; run_agent_sync turns
# that output back into the answer text and appends one usage line per dispatch.
# summary.json reports per-seat usage and the round total.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Council seat usage"

# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/agent-sync.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/secure.sh"

HELPER="$PROJECT_ROOT/scripts/helpers/seat-usage.py"
WORK="$(mktemp -d "${TEST_TMP_DIR:-/tmp}/seat-usage.XXXXXX")"
WORK="$(cd -- "$WORK" && pwd -P)"

CLAUDE_JSON='{"type":"result","subtype":"success","is_error":false,"result":"Reviewed it.\nVERDICT: APPROVE","total_cost_usd":0.0421,"usage":{"input_tokens":9,"cache_creation_input_tokens":1000,"cache_read_input_tokens":0,"output_tokens":41},"modelUsage":{"claude-opus-5-5":{"inputTokens":12,"outputTokens":300,"cacheReadInputTokens":5000,"cacheCreationInputTokens":2000,"costUSD":0.0421}}}'
CODEX_JSONL='{"type":"thread.started","thread_id":"t"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"Looking at the diff."}}
{"type":"item.completed","item":{"id":"item_1","type":"command_execution","command":"cat x"}}
{"type":"item.completed","item":{"id":"item_2","type":"agent_message","text":"Found nothing.\nVERDICT: APPROVE"}}
{"type":"turn.completed","usage":{"input_tokens":10000,"cached_input_tokens":8000,"cache_write_input_tokens":0,"output_tokens":500,"reasoning_output_tokens":200}}'

test_case "claude JSON becomes the answer text and a usage line with the CLI's own cost"
out="$WORK/claude.out"; ledger="$WORK/claude.jsonl"
printf '%s\n' "$CLAUDE_JSON" > "$out"
python3 "$HELPER" claude "$out" "$ledger" "independent-advice|strategy-analyst" claude-opus-5-5 "" ""
if [[ "$(cat "$out")" == $'Reviewed it.\nVERDICT: APPROVE' ]] &&
   jq -e '.phase == "independent-advice" and .persona == "strategy-analyst" and .provider == "claude"
          and .input_tokens == 12 and .cache_read_tokens == 5000 and .cache_write_tokens == 2000
          and .output_tokens == 300 and .cost_usd == 0.0421 and .cost_source == "claude-cli"' "$ledger" >/dev/null; then
    test_pass
else
    test_fail "out=$(cat "$out") ledger=$(cat "$ledger" 2>/dev/null)"
fi

test_case "codex JSONL keeps the last agent message and prices cached input at a tenth"
out="$WORK/codex.out"; ledger="$WORK/codex.jsonl"
printf '%s\n' "$CODEX_JSONL" > "$out"
python3 "$HELPER" codex "$out" "$ledger" "critique|backend-architect" gpt-5.6-sol 4 20
# fresh 2000 * 4 + cached 8000 * 0.4 + output 500 * 20 = 8000 + 3200 + 10000 per MTok
if [[ "$(cat "$out")" == $'Found nothing.\nVERDICT: APPROVE' ]] &&
   jq -e '.input_tokens == 2000 and .cache_read_tokens == 8000 and .output_tokens == 500
          and .reasoning_tokens == 200 and .cost_usd == 0.0212 and .cost_source == "estimated-list-price"' "$ledger" >/dev/null; then
    test_pass
else
    test_fail "out=$(cat "$out") ledger=$(cat "$ledger" 2>/dev/null)"
fi

test_case "OCTOPUS_CODEX_CACHED_INPUT_RATIO sets the cached input price"
out="$WORK/codex-ratio.out"; ledger="$WORK/codex-ratio.jsonl"
printf '%s\n' "$CODEX_JSONL" > "$out"
OCTOPUS_CODEX_CACHED_INPUT_RATIO=0.5 python3 "$HELPER" codex "$out" "$ledger" "critique|x" m 4 20
# fresh 2000 * 4 + cached 8000 * 2 + output 500 * 20 per MTok
if jq -e '.cost_usd == 0.034' "$ledger" >/dev/null; then test_pass; else test_fail "$(cat "$ledger")"; fi

test_case "plain text output is left untouched and records nothing"
out="$WORK/plain.out"; ledger="$WORK/plain.jsonl"
printf 'Plain answer.\nVERDICT: REVISE\n' > "$out"
python3 "$HELPER" claude "$out" "$ledger" "independent-advice|x" m "" "" && rc=0 || rc=$?
if [[ "$rc" == 1 && "$(cat "$out")" == $'Plain answer.\nVERDICT: REVISE' && ! -e "$ledger" ]]; then
    test_pass
else
    test_fail "rc=$rc out=$(cat "$out")"
fi

test_case "usage mode applies only to claude --print and codex exec seats with a ledger"
kinds=""
_OCTOPUS_SEAT_USAGE_FILE="$WORK/l.jsonl"
for argv in "claude|claude --print --model m" "claude-opus|/x/octo-claude-keyed --print --model m" \
            "codex|codex exec --model m -" "codex-review|codex exec review --model m -" \
            "claude-sdk|claude --print" "copilot|copilot -p x" "agy|/p/agy-exec.sh" \
            "claude|claude --print --output-format json" "claude|claude -p"; do
    read -r -a words <<< "${argv#*|}"
    kinds+="$(octo_seat_usage_kind "${argv%%|*}" "${words[@]}" || echo -),"
done
unset _OCTOPUS_SEAT_USAGE_FILE
off="$(octo_seat_usage_kind claude claude --print || echo -)"
disabled="$(_OCTOPUS_SEAT_USAGE_FILE=x OCTOPUS_COUNCIL_SEAT_USAGE=0 octo_seat_usage_kind claude claude --print || echo -)"
if [[ "$kinds" == "claude,claude,codex,codex,-,-,-,-,-," && "$off" == - && "$disabled" == - ]]; then
    test_pass
else
    test_fail "kinds=$kinds off=$off disabled=$disabled"
fi

# Drive the real run_agent_sync with a fake claude that answers in JSON only
# when asked to, so the flag and the rewrite are both exercised end to end.
run_seat() (
    local agent="$1" ledger="$2" fake="$WORK/bin/$3"
    mkdir -p "$WORK/bin" "$WORK/results-$3"
    export RESULTS_DIR="$WORK/results-$3"
    cat > "$fake" <<EOF
#!/usr/bin/env bash
cat >/dev/null
case " \$* " in
    *" --output-format json "*) printf '%s\n' '$CLAUDE_JSON' ;;
    *" --json "*) cat <<'JSONL'
$CODEX_JSONL
JSONL
    ;;
    *) printf 'plain answer\nVERDICT: APPROVE\n' ;;
esac
EOF
    chmod 755 "$fake"
    log() { :; }
    classify_task() { printf 'standard\n'; }
    get_role_for_context() { printf 'reviewer\n'; }
    apply_persona() { printf '%s\n' "$2"; }
    load_earned_skills() { :; }
    build_provider_context() { :; }
    enforce_context_budget() { printf '%s\n' "$1"; }
    get_agent_model() { printf 'fixture-model\n'; }
    estimate_agent_call_cost() { printf '0.000000\n'; }
    check_provider_health() { return 0; }
    record_agent_call() { :; }
    get_model_pricing() { printf '4:20\n'; }
    if [[ "$agent" == codex ]]; then
        get_agent_command() { printf '%s exec --model m -\n' "$fake"; }
    else
        get_agent_command() { printf '%s --print --model m\n' "$fake"; }
    fi
    build_provider_env() { PROVIDER_ENV_ARRAY=(); }
    run_with_timeout() { shift; "$@"; }
    stop_quota_watcher() { :; }
    update_agent_status() { :; }
    octo_estimate_tokens_for_file() { printf '0\n'; }
    write_agent_status() { :; }
    CODEX_SUBAGENT_PREAMBLE=""
    wrap_cli_output() { printf '%s\n' "$2"; }
    _OCTOPUS_SEAT_USAGE_FILE="$ledger" _OCTOPUS_SEAT_USAGE_LABEL="independent-advice|seat-$3" \
        OCTOPUS_PERSISTENCE_AVAILABLE=true \
        run_agent_sync "$agent" 'review this change' 30 reviewer council 2>"$WORK/err-$3"
)

test_case "a live claude seat returns its answer text and appends its usage"
ledger="$WORK/live.jsonl"
answer="$(run_seat claude "$ledger" claude)" || true
if [[ "$answer" == *"Reviewed it."* && "$answer" != *total_cost_usd* ]] &&
   jq -e 'select(.persona == "seat-claude") | .cost_usd == 0.0421' "$ledger" >/dev/null; then
    test_pass
else
    test_fail "answer=$answer ledger=$(cat "$ledger" 2>/dev/null)"
fi

test_case "a live codex seat returns its last message and appends its usage"
answer="$(run_seat codex "$ledger" codex)" || true
if [[ "$answer" == *"Found nothing."* && "$answer" != *turn.completed* ]] &&
   jq -e 'select(.persona == "seat-codex") | .cost_usd == 0.0212' "$ledger" >/dev/null; then
    test_pass
else
    test_fail "answer=$answer err=$(tail -c 600 "$WORK/err-codex" 2>/dev/null)"
fi

test_case "without a ledger the seat runs exactly as before"
answer="$(run_seat claude "" plainclaude)" || true
if [[ "$answer" == *"plain answer"* ]]; then test_pass; else test_fail "answer=$answer"; fi

test_case "summary.json totals the ledger by phase and attaches each seat's usage"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/council.sh"
COUNCIL_RUN_DIR="$WORK/run"; mkdir -p "$COUNCIL_RUN_DIR"
{
    jq -c '.persona = "strategy-analyst"' "$WORK/claude.jsonl"
    jq -c '.persona = "backend-architect"' "$WORK/codex.jsonl"
    printf 'not json\n'
    printf '%s\n' '{"phase":"chair-synthesis","persona":"strategy-analyst","provider":"claude","input_tokens":1,"cache_read_tokens":0,"cache_write_tokens":0,"output_tokens":9,"cost_usd":0.01}'
} > "$COUNCIL_RUN_DIR/usage.jsonl"
u="$(council_usage_summary_json)"
if jq -e '.total.dispatches == 3 and .total.output_tokens == 809 and .total.cache_read_tokens == 13000
          and .total.cost_usd == 0.0733 and .total.cost_complete == true
          and .by_phase["chair-synthesis"].dispatches == 1 and .by_phase.critique.cost_usd == 0.0212
          and .by_persona["strategy-analyst"].cost_usd == 0.0521' <<< "$u" >/dev/null; then
    test_pass
else
    test_fail "usage=$u"
fi

test_case "no ledger means usage is null"
COUNCIL_RUN_DIR="$WORK/empty-run"; mkdir -p "$COUNCIL_RUN_DIR"
if [[ "$(council_usage_summary_json)" == null ]]; then test_pass; else test_fail "$(council_usage_summary_json)"; fi

test_case "relative output directory remains visible from the seat workspace"
if (
    mkdir -p "$WORK/other/relative output" && cd "$WORK" &&
        CDPATH="$WORK/other" COUNCIL_OUTPUT_DIR="relative output" council_create_run_dir &&
        cd "$WORK/run" && [[ "$COUNCIL_RUN_DIR" == "$WORK/relative output/"* &&
            -s "$COUNCIL_RUN_DIR/run-status.json" ]]
); then
    test_pass
else
    test_fail "the published run is unavailable from the seat's working directory"
fi

test_summary
