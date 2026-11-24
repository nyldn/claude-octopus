#!/usr/bin/env bash
# Compare shipped metadata with a dated, public provider response.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "November model catalog refresh"

source "$PROJECT_ROOT/scripts/lib/models.sh"
WORKSPACE_DIR="$TEST_TMP_DIR"
source "$PROJECT_ROOT/scripts/lib/cost.sh"
source "$PROJECT_ROOT/scripts/lib/providers.sh"
snapshot="$PROJECT_ROOT/tests/fixtures/model-catalog-20261124.json"
jq -e '.sources.opencode.models | length == 4' "$snapshot" >/dev/null

while IFS=$'\t' read -r id context tools images reasoning input output; do
    model="opencode/$id"
    test_case "$model capabilities match the public OpenCode listing"
    expected="$context|$tools|$images|$reasoning"
    actual="$(get_model_catalog "$model" | cut -d'|' -f1-4)"
    if [[ "$actual" == "$expected" ]]; then
        test_pass
    else
        test_fail "expected $expected, got $actual"
    fi

    test_case "$model uses the listed input and output tariff"
    price="$(get_model_pricing "$model" opencode)"
    if jq -en --arg price "$price" --argjson input "$input" --argjson output "$output" \
        '$price | split(":") | map(tonumber) | . == [$input, $output]' >/dev/null; then
        test_pass
    else
        test_fail "expected $input:$output, got $price"
    fi
done < <(jq -r '.sources.opencode.models[] | [
    .id, (.limit.context / 1000),
    (if .capabilities.tools.supported then "yes" else "no" end),
    (if any(.modalities.input[]; startswith("image/")) then "yes" else "no" end),
    (if .capabilities.reasoning.supported then "yes" else "no" end),
    .cost.text.input.price, .cost.text.output.price
] | @tsv' "$snapshot")

test_case "large OpenCode GPT-5.4 requests use the whole-request premium"
if [[ "$(get_model_pricing opencode/gpt-5.4 opencode 272000)" == "2.50:15.00" &&
      "$(get_model_pricing opencode/gpt-5.4 opencode 272001)" == "5.000000:22.500000" ]]; then
    test_pass
else
    test_fail "OpenCode GPT-5.4 did not apply the 272K request threshold"
fi

test_case "usage and costs reports apply the OpenCode GPT-5.4 premium"
mkdir -p "$TEST_TMP_DIR/report-usage" "$TEST_TMP_DIR/report-results"
printf '%s\n' '{"provider":"opencode","model":"opencode/gpt-5.4","tokens_in":300000,"tokens_out":1000}' \
    > "$TEST_TMP_DIR/report-usage/requests.jsonl"
report_ok=true
for view in usage costs; do
    report="$(bash "$PROJECT_ROOT/scripts/helpers/usage-report.sh" --view "$view" --format json \
        --usage-dir "$TEST_TMP_DIR/report-usage" --results-dir "$TEST_TMP_DIR/report-results")"
    if ! jq -e '.totals.est_cost_usd == 1.5225' >/dev/null <<<"$report"; then
        report_ok=false
    fi
done
if [[ "$report_ok" == true ]]; then
    test_pass
else
    test_fail "OpenCode report omitted its whole-request multiplier"
fi

OPENROUTER_ROUTING_OVERRIDE=""
PROVIDER_OPENROUTER_ROUTING_PREF=default
for task in coding review research design general; do
    test_case "OpenRouter $task selects the listed Sonnet successor"
    selected="$(get_openrouter_model "$task" 2)"
    if jq -e --arg id "$selected" '.sources.openrouter.models | any(.id == $id)' \
        "$snapshot" >/dev/null; then
        test_pass
    else
        test_fail "unlisted OpenRouter model: $selected"
    fi
done

test_case "OpenRouter successor retains routing suffixes and API pricing"
OPENROUTER_ROUTING_OVERRIDE=:nitro
PROVIDER_OPENROUTER_ROUTING_PREF=floor
if [[ "$(get_openrouter_model review 2)" == "anthropic/claude-sonnet-4.6:nitro" &&
      "$(get_model_pricing anthropic/claude-sonnet-4.6:nitro openrouter)" == "3.00:15.00" &&
      "$(OPENROUTER_ROUTING_OVERRIDE= get_openrouter_model research 2)" == "anthropic/claude-sonnet-4.6:floor" ]]; then
    test_pass
else
    test_fail "OpenRouter routing preference or pricing changed"
fi

test_case "routing suffixes preserve the gateway context override"
expected_context="$(jq -r '.sources.openrouter.models[0].context_length / 1000' "$snapshot")"
if [[ "$(get_model_capability anthropic/claude-sonnet-4.6:nitro context_k)" == "$expected_context" &&
      "$(get_model_capability anthropic/claude-sonnet-4.6:floor context_k)" == "$expected_context" ]]; then
    test_pass
else
    test_fail "gateway context was replaced by native-Claude metadata"
fi

test_case "retired OpenCode IDs are absent from the advertised catalog"
if ! octo_model_ids | grep -Eq '^opencode/(deepseek-v4-flash-free|glm-5\.1)$'; then
    test_pass
else
    test_fail "retired OpenCode models remain advertised"
fi

test_summary
