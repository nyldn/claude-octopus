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

test_summary
