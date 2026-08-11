#!/usr/bin/env bash
# Regression coverage for issue #801: one catalog and one pricing source.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Model metadata parity (#801)"

source "$PROJECT_ROOT/scripts/lib/models.sh"

test_case "model-config renders every ID from the canonical model catalog"
catalog_output="$(env "HOME=${TEST_TMP_DIR}" bash "$PROJECT_ROOT/scripts/helpers/octo-model-config.sh" models 2>/dev/null)"
catalog_ids="$(awk '$2 ~ /^[0-9]+K$/ { print $1 }' <<< "$catalog_output")"
missing=""
while IFS= read -r model; do
    [[ -n "$model" ]] || continue
    grep -F -x -c -- "$model" <<< "$catalog_ids" >/dev/null || missing="$missing $model"
done < <(octo_model_ids)
if [[ -z "$missing" ]] && ! grep -q 'Inline catalog' "$PROJECT_ROOT/scripts/helpers/octo-model-config.sh"; then
    test_pass
else
    test_fail "model-config diverges from canonical model IDs:$missing"
fi

test_case "one checked-in pricing table drives Bash and Python reports"
pricing_file="$PROJECT_ROOT/config/model-pricing.tsv"
if [[ -f "$pricing_file" ]] &&
   grep -Fq 'config/model-pricing.tsv' "$PROJECT_ROOT/scripts/lib/cost.sh" &&
   grep -Fq 'config/model-pricing.tsv' "$PROJECT_ROOT/scripts/helpers/usage-report.sh" &&
   ! grep -q '"grok":[[:space:]]*(' "$PROJECT_ROOT/scripts/helpers/usage-report.sh" &&
   ! grep -q '"gpt-5\.6-sol":[[:space:]]*(' "$PROJECT_ROOT/scripts/helpers/usage-report.sh"; then
    test_pass
else
    test_fail "cost.sh and usage-report.sh do not share config/model-pricing.tsv"
fi

test_case "every canonical model has exactly one pricing row"
missing=""
while IFS= read -r model; do
    [[ -n "$model" ]] || continue
    count="$(awk -F '\t' -v id="$model" '$1 == "model" && $2 == id { n++ } END { print n + 0 }' "$pricing_file")"
    [[ "$count" -eq 1 ]] || missing="$missing $model($count)"
done < <(octo_model_ids)
if [[ -z "$missing" ]]; then
    test_pass
else
    test_fail "canonical models with missing/duplicate pricing rows:$missing"
fi

test_case "subscription Cursor Grok and metered standalone Grok stay distinct"
export "WORKSPACE_DIR=${TEST_TMP_DIR}"
source "$PROJECT_ROOT/scripts/lib/cost.sh"
cursor_price="$(get_model_pricing grok-4-20 cursor-agent)"
standalone_price="$(get_model_pricing grok-4-20 grok)"
if [[ "$cursor_price" == "0.00:0.00" && "$standalone_price" == "3.00:15.00" ]]; then
    test_pass
else
    test_fail "provider-aware Grok pricing drifted: cursor=$cursor_price standalone=$standalone_price"
fi

test_case "Copilot subscription overrides explicit model API pricing"
if [[ "$(get_model_pricing gpt-5.4 copilot)" == "0.00:0.00" ]]; then
    test_pass
else
    test_fail "Copilot model pin was priced as direct API usage"
fi

test_case "current DeepSeek V4 Pro price comes from the shared table"
if [[ "$(get_model_pricing deepseek/deepseek-v4-pro openrouter)" == "0.435:0.87" ]]; then
    test_pass
else
    test_fail "DeepSeek V4 Pro pricing is missing or stale"
fi

test_summary
