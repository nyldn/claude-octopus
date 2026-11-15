#!/usr/bin/env bash
# Focused token-component pricing behavior.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "usage component pricing"

WORKSPACE_DIR="$TEST_TMP_DIR/workspace"
mkdir -p "$WORKSPACE_DIR"
source "$PROJECT_ROOT/scripts/lib/models.sh"
source "$PROJECT_ROOT/scripts/lib/cost.sh"
DRY_RUN=false
SUPPORTS_ACCOUNT_ENV_VARS=false
log() { :; }
is_api_based_provider() { return 0; }
init_usage_tracking
: > "${USAGE_FILE}.log"

test_case "actual uncached usage replaces the reservation price"
call_id="$(record_agent_start codex-api gpt-6-astra x pricing)"
record_agent_call codex-api gpt-6-astra x pricing reviewer 0 "$call_id"
record_agent_complete "$call_id" codex-api gpt-6-astra "" pricing 300 0 1 100 200
report="$(generate_usage_json)"
if [[ "$(jq -r '.calls[0].cost_usd' <<<"$report")" == "0.011" ]]; then
  test_pass
else
  test_fail "actual component price did not replace the reservation"
fi

test_case "unknown cache tariff is never silently billed as uncached input"
cached_id="$(record_agent_start codex-api gpt-5.6-sol x pricing)"
record_agent_call codex-api gpt-5.6-sol x pricing reviewer 0 "$cached_id"
record_agent_complete "$cached_id" codex-api gpt-5.6-sol "" pricing 30 0 1 10 10 10 0 0
report="$(generate_usage_json)"
if jq -e --arg id "$cached_id" '.calls[] | select(.call_id == $id) | .cost_usd == null' >/dev/null <<<"$report"; then
  test_pass
else
  test_fail "unknown cached-token tariff was fabricated"
fi

test_case "native metrics parser keeps cache and reasoning fields"
SUPPORTS_NATIVE_TASK_METRICS=true
SUPPORTS_OTEL_SPEED=false
parse_task_metrics $'<usage>\ninput_tokens: 100\ncached_input_tokens: 20\ncache_creation_input_tokens: 10\noutput_tokens: 50\nreasoning_tokens: 10\ntotal_tokens: 190\n</usage>'
if [[ "$_PARSED_INPUT_TOKENS" == 100 && "$_PARSED_CACHED_INPUT_TOKENS" == 20 &&
      "$_PARSED_CACHE_WRITE_TOKENS" == 10 && "$_PARSED_OUTPUT_TOKENS" == 50 &&
      "$_PARSED_REASONING_TOKENS" == 10 ]]; then
  test_pass
else
  test_fail "native usage components were not parsed independently"
fi

test_case "explicit GPT-5.4 Mini usage uses its API tariff"
mini_id="$(record_agent_start codex-api gpt-5.4-mini x pricing)"
record_agent_call codex-api gpt-5.4-mini x pricing reviewer 0 "$mini_id"
record_agent_complete "$mini_id" codex-api gpt-5.4-mini "" pricing 3000 0 1 1000 2000
report="$(generate_usage_json)"
if jq -e --arg id "$mini_id" '.calls[] | select(.call_id == $id) | .cost_usd == 0.00975' >/dev/null <<<"$report"; then
  test_pass
else
  test_fail "GPT-5.4 Mini usage did not use the verified input/output tariff"
fi

test_case "GPT-5.4 Mini exposes vision and reasoning to capability selection"
mini_candidates="$(list_models codex --tools --images --reasoning --tier budget)"
if awk '$1 == "gpt-5.4-mini" && /\$0.75\/\$4.50 MTok/ { found=1 } END { exit !found }' <<<"$mini_candidates"; then
  test_pass
else
  test_fail "GPT-5.4 Mini was excluded from vision or reasoning work"
fi

test_case "OpenCode GPT-5.4 Mini exposes vision and reasoning to capability selection"
mini_candidates="$(list_models opencode --tools --images --reasoning --tier budget)"
if awk '$1 == "opencode/gpt-5.4-mini" { found=1 } END { exit !found }' <<<"$mini_candidates"; then
  test_pass
else
  test_fail "qualified GPT-5.4 Mini was excluded from OpenCode vision or reasoning work"
fi

test_case "UberLLM DeepSeek Flash uses the shared peak uncached fallback estimate"
flash_id="$(record_agent_start uberllm-agent deepseek/deepseek-v4-flash x pricing)"
record_agent_call uberllm-agent deepseek/deepseek-v4-flash x pricing reviewer 0 "$flash_id"
record_agent_complete "$flash_id" uberllm-agent deepseek/deepseek-v4-flash "" pricing 3000 0 1 1000 2000
report="$(generate_usage_json)"
if [[ "$(get_model_pricing deepseek/deepseek-v4-flash uberllm-agent)" == "0.30:1.20" ]] &&
   jq -e --arg id "$flash_id" '.calls[] | select(.call_id == $id) | .cost_usd == 0.0027' >/dev/null <<< "$report"; then
    test_pass
else
    test_fail "DeepSeek Flash retained the unrelated generic fallback rate"
fi

test_case "provider overrides bypass model request rules in every Bash billing path"
override_ok=true
for provider in grok-agent copilot cursor-agent-preview; do
    for override_model in gpt-5.5 openai/gpt-5.5; do
        expected_actual=0
        expected_estimate=0.000000
        expected_workflow=0.0000
        if [[ "$provider" == grok-agent ]]; then
            expected_actual=0.915
            expected_estimate=9.900000
            expected_workflow=9.9000
        fi
        reservation="$(
            estimate_tokens() { echo 300000; }
            estimate_agent_call_cost "$provider" "$override_model" x
        )"
        workflow="$(
            phase=pricing role=reviewer
            get_agent_model() { echo "$override_model"; }
            estimate_tokens() { echo 300000; }
            calculate_agent_cost "$provider" 1
        )"
        override_id="$(record_agent_start "$provider" "$override_model" x pricing)"
        record_agent_call "$provider" "$override_model" x pricing reviewer 0 "$override_id"
        record_agent_complete "$override_id" "$provider" "$override_model" "" pricing 301000 0 1 300000 1000
        actual="$(generate_usage_json | jq -r --arg id "$override_id" '.calls[] | select(.call_id == $id) | .cost_usd')"
        if ! jq -en --argjson actual "$actual" --argjson expected "$expected_actual" '$actual == $expected' >/dev/null ||
           [[ "$reservation" != "$expected_estimate" || "$workflow" != "$expected_workflow" ]]; then
            echo "$provider $override_model actual=$actual reservation=$reservation workflow=$workflow"
            override_ok=false
        fi
    done
done
if [[ "$override_ok" == true ]]; then
    test_pass
else
    test_fail "model request tariff changed a provider override"
fi

test_summary
