#!/usr/bin/env bash
# Contract tests for one reconciled usage record per provider call.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "reconciled provider usage lifecycle"

WORKSPACE_DIR="$TEST_TMP_DIR/workspace"
mkdir -p "$WORKSPACE_DIR"
source "$PROJECT_ROOT/scripts/lib/cost.sh"
DRY_RUN=false
SUPPORTS_ACCOUNT_ENV_VARS=false
log() { :; }
get_model_pricing() { printf '%s\n' "1.00:2.00"; }
is_api_based_provider() { [[ "$1" == codex-api ]]; }
init_usage_tracking
: > "${USAGE_FILE}.log"

test_case "reservation and actual completion reconcile to one call"
call_id="$(record_agent_start codex-api gpt-test abc lifecycle)"
record_agent_call codex-api gpt-test abc lifecycle reviewer 0 "$call_id"
record_agent_complete "$call_id" codex-api gpt-test "" lifecycle 300 0 25 100 200
report="$(generate_usage_json)"
if jq -e --arg id "$call_id" '
    .totals.calls == 1 and .totals.tokens == 300 and
    (.calls | length) == 1 and .calls[0].call_id == $id and
    .calls[0].state == "completed" and .calls[0].usage_source == "actual" and
    .calls[0].input_tokens == 100 and .calls[0].output_tokens == 200
  ' >/dev/null <<<"$report"; then
  test_pass
else
  test_fail "estimate and actual usage were added instead of reconciled: $report"
fi

test_case "duplicate completion is idempotent"
record_agent_complete "$call_id" codex-api gpt-test "" lifecycle 999 0 99 333 666
report="$(generate_usage_json)"
if jq -e --arg id "$call_id" '
    [.calls[] | select(.call_id == $id)] | length == 1 and
    .[0].total_tokens == 300
  ' >/dev/null <<<"$report"; then
  test_pass
else
  test_fail "duplicate completion changed or duplicated terminal usage"
fi

test_case "a provider retry remains one logical call"
if [[ "$(jq -r --arg id "$call_id" '[.calls[] | select(.call_id == $id)] | length' <<<"$report")" == 1 ]]; then
  test_pass
else
  test_fail "retry accounting created more than one logical call"
fi

test_case "completion without native metrics terminalizes with measured estimates"
estimated_id="$(record_agent_start codex-api gpt-test estimate estimated-phase)"
record_agent_call codex-api gpt-test estimate estimated-phase reviewer 0 "$estimated_id"
record_agent_complete "$estimated_id" codex-api gpt-test "provider output" estimated-phase
report="$(generate_usage_json)"
if jq -e --arg id "$estimated_id" '
    .calls[] | select(.call_id == $id) |
    .state == "completed" and .usage_source == "estimated-output" and
    .input_tokens == 2 and .output_tokens == 4 and .total_tokens == 6
  ' >/dev/null <<<"$report"; then
  test_pass
else
  test_fail "completion without native usage remained reserved"
fi

test_case "failed call retains one estimated reservation"
failed_id="$(record_agent_start codex-api gpt-test failure failure-phase)"
record_agent_call codex-api gpt-test failure failure-phase implementer 0 "$failed_id"
record_agent_failure "$failed_id" 17 "provider failed"
report="$(generate_usage_json)"
if jq -e --arg id "$failed_id" '
    [.calls[] | select(.call_id == $id)] | length == 1 and
    .[0].state == "failed" and .[0].usage_source == "estimated" and
    .[0].failure_reason == "provider failed"
  ' >/dev/null <<<"$report"; then
  test_pass
else
  test_fail "failed call lost or duplicated its reservation: $report"
fi

test_case "completion without role preserves the reserved role"
terminal_log="$TEST_TMP_DIR/completed-role.jsonl"
python3 "$PROJECT_ROOT/scripts/helpers/usage-ledger.py" append \
  --file "$terminal_log" --state reserved --call-id completed-role \
  --agent codex-api --model gpt-test --phase lifecycle --role reviewer \
  --input-tokens 1 --output-tokens 2 --total-tokens 3 \
  --usage-source estimated --cost 0.000005 --cost-status estimated
python3 "$PROJECT_ROOT/scripts/helpers/usage-ledger.py" append \
  --file "$terminal_log" --state completed --call-id completed-role \
  --agent codex-api --model gpt-test --phase lifecycle \
  --input-tokens 10 --output-tokens 20 --total-tokens 30 \
  --usage-source actual --cost 0.25 --cost-status actual
terminal_report="$(python3 "$PROJECT_ROOT/scripts/helpers/usage-ledger.py" report --file "$terminal_log")"
if jq -e '
    .calls[0].state == "completed" and .calls[0].role == "reviewer" and
    .calls[0].total_tokens == 30 and .calls[0].cost_usd == 0.25
  ' <<< "$terminal_report" >/dev/null; then
  test_pass
else
  test_fail "completion erased its reserved role: $terminal_report"
fi

test_case "aborted terminal events retain reported billed usage"
terminal_log="$TEST_TMP_DIR/aborted-usage.jsonl"
for state in failed cancelled timeout; do
  python3 "$PROJECT_ROOT/scripts/helpers/usage-ledger.py" append \
    --file "$terminal_log" --state reserved --call-id "aborted-$state" \
    --agent codex-api --model gpt-test --phase lifecycle --role reviewer \
    --input-tokens 1 --output-tokens 2 --total-tokens 3 \
    --usage-source estimated --cost 0.000005 --cost-status estimated
  python3 "$PROJECT_ROOT/scripts/helpers/usage-ledger.py" append \
    --file "$terminal_log" --state "$state" --call-id "aborted-$state" \
    --agent codex-api --model gpt-test --phase lifecycle \
    --input-tokens 10 --output-tokens 20 --total-tokens 30 \
    --usage-source actual --cost 0.25 --cost-status actual --duration-ms 50 \
    --failure-reason "$state by provider"
done
terminal_report="$(python3 "$PROJECT_ROOT/scripts/helpers/usage-ledger.py" report --file "$terminal_log")"
if jq -e '
    .totals.tokens == 90 and .totals.cost_usd == 0.75 and
    ([.calls[] | select(
      .role == "reviewer" and .usage_source == "actual" and
      .input_tokens == 10 and .output_tokens == 20 and .total_tokens == 30 and
      .cost_usd == 0.25 and .cost_status == "actual" and .duration_ms == 50
    )] | length) == 3
  ' <<< "$terminal_report" >/dev/null; then
  test_pass
else
  test_fail "aborted calls lost reported billed usage: $terminal_report"
fi

test_case "native cached and reasoning components remain distinct"
cached_id="$(record_agent_start codex-api gpt-test cache cache-phase)"
record_agent_call codex-api gpt-test cache cache-phase reviewer 0 "$cached_id"
record_agent_complete "$cached_id" codex-api gpt-test "" cache-phase \
  190 0 12 100 50 20 10 10
report="$(generate_usage_json)"
if jq -e --arg id "$cached_id" '
    .calls[] | select(.call_id == $id) |
    .input_tokens == 100 and .cached_input_tokens == 20 and
    .cache_write_tokens == 10 and .output_tokens == 50 and
    .reasoning_tokens == 10 and .cost_usd == null and
    .cost_status == "unknown-cache-tariff"
  ' >/dev/null <<<"$report"; then
  test_pass
else
  test_fail "cached-token components were flattened or mispriced: $report"
fi

test_case "legacy pipe rows remain readable with malformed fields explicit"
printf '%s\n' '2026-01-01T00:00:00Z|legacy|old-model|old-phase|role|10|20|30|0.25|not-a-number|legacy-id' >> "${USAGE_FILE}.log"
report="$(generate_usage_json)"
if jq -e '
    .calls[] | select(.call_id == "legacy-id") |
    .state == "legacy" and .duration_ms == null and
    .billing_mode == "unknown" and .tariff_version == null
  ' >/dev/null <<<"$report"; then
  test_pass
else
  test_fail "legacy compatibility produced invalid or misleading fields: $report"
fi

test_case "JSON export is strict and totals count reconciled calls"
if jq -e '.totals.calls == 5 and (.calls | length) == 5' >/dev/null <<<"$report"; then
  test_pass
else
  test_fail "strict JSON export or reconciled total failed: $report"
fi

test_case "concurrent reservations remain valid and distinct"
for index in $(seq 1 20); do
  python3 "$PROJECT_ROOT/scripts/helpers/usage-ledger.py" append \
    --file "${USAGE_FILE}.log" --state reserved --call-id "parallel-$index" \
    --agent codex-api --model gpt-test --phase parallel --role reviewer \
    --input-tokens 1 --output-tokens 2 --total-tokens 3 \
    --usage-source estimated --cost 0.000005 --cost-status estimated \
    --billing-mode api --tariff-version test &
done
wait
report="$(generate_usage_json)"
if jq -e '.totals.calls == 25 and ([.calls[].call_id | select(startswith("parallel-"))] | length) == 20' >/dev/null <<<"$report"; then
  test_pass
else
  test_fail "concurrent JSONL appends were lost or interleaved"
fi

test_summary
