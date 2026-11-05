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
cursor_price="$(get_model_pricing cursor-grok-4.6-high cursor-agent)"
standalone_price="$(get_model_pricing cursor-grok-4.6-high grok)"
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

test_case "current Sol, Luna, and Sonnet appear with canonical capabilities and prices"
if [[ "$(get_model_catalog gpt-6.1-sol)" == "1050|yes|yes|yes|codex|standard|active" &&
      "$(get_model_catalog gpt-6-sol)" == "1050|yes|yes|yes|codex|standard|active" &&
      "$(get_model_catalog gpt-6-luna)" == "1050|yes|yes|yes|codex|budget|active" &&
      "$(get_model_catalog claude-sonnet-5-5)" == "1000|yes|yes|yes|claude|standard|active" &&
      "$(get_model_pricing openai/gpt-6.1-sol:nitro)" == "2.00:10.00" &&
      "$(get_model_pricing gpt-6-sol)" == "2.00:10.00" &&
      "$(get_model_pricing gpt-6-luna)" == "0.10:0.50" &&
      "$(get_model_pricing claude-sonnet-5-5)" == "2.00:10.00" ]]; then
    test_pass
else
    test_fail "current model metadata or namespaced pricing is missing"
fi

test_case "GPT-6 long-context pricing changes only above 272000 input tokens"
if PRICING_FILE="$pricing_file" python3 - <<'PY'
import os, subprocess
root = os.path.dirname(os.path.dirname(os.environ["PRICING_FILE"]))
for model, input_rate, output_rate in [("gpt-6.1-sol", 2, 10), ("gpt-6-sol", 2, 10), ("gpt-6-luna", .1, .5)]:
    for input_tokens in (271999, 272000, 272001):
        # Exercise the billing function, including canonical namespace handling.
        command = 'source "$1/scripts/lib/models.sh"; source "$1/scripts/lib/cost.sh"; is_api_based_provider() { return 0; }; estimate_tokens() { printf "%s" "$test_input_tokens"; }; test_input_tokens="$3"; estimate_agent_call_cost codex-api "$2" ignored'
        actual = float(subprocess.check_output(["bash", "-c", command, "test", root, "openai/" + model + ":floor", str(input_tokens)], text=True))
        in_multiplier, out_multiplier = (2, 1.5) if input_tokens > 272000 else (1, 1)
        expected = (input_tokens * input_rate * in_multiplier + input_tokens * 2 * output_rate * out_multiplier) / 1e6
        assert abs(actual - expected) < .000001, (model, input_tokens, actual, expected)
PY
then
    test_pass
else
    test_fail "GPT-6 pricing lost the threshold or whole-request multiplier"
fi

test_case "Haiku 5.5 can be saved as a budget pin without changing defaults"
pin_home="$TEST_TMP_DIR/haiku-pin-home"
if env "HOME=$pin_home" OCTO_ALLOWED_PROVIDERS=claude bash "$PROJECT_ROOT/scripts/helpers/octo-model-config.sh" set claude.budget claude-haiku-5-5 >/dev/null 2>&1 &&
   [[ "$(jq -r '.providers.claude.budget' "$pin_home/.claude-octopus/config/providers.json")" == "claude-haiku-5-5" ]] &&
   [[ "$(get_model_catalog claude-haiku-5-5)" == "1000|yes|yes|yes|claude|budget|active" ]] &&
   grep -Fqx 'claude-haiku-5-5' < <(octo_model_ids) &&
   grep -Fq '"budget": "claude-haiku-4.5"' "$PROJECT_ROOT/scripts/helpers/octo-model-config.sh"; then
    test_pass
else
    test_fail "Haiku 5.5 pin admission failed or the existing budget default changed"
fi

test_case "Haiku 5.5 billing applies the whole-request tariff strictly above 100K"
if PRICING_FILE="$pricing_file" python3 - <<'PY'
import os, subprocess
root = os.path.dirname(os.path.dirname(os.environ["PRICING_FILE"]))
for model in ("claude-haiku-5-5", "anthropic/claude-haiku-5-5"):
    for input_tokens in (99999, 100000, 100001):
        command = 'source "$1/scripts/lib/models.sh"; source "$1/scripts/lib/cost.sh"; is_api_based_provider() { return 0; }; estimate_tokens() { printf "%s" "$test_input_tokens"; }; test_input_tokens="$3"; estimate_agent_call_cost claude-sdk "$2" ignored'
        actual = float(subprocess.check_output(["bash", "-c", command, "test", root, model, str(input_tokens)], text=True))
        multiplier = 5 if input_tokens > 100000 else 1
        expected = input_tokens * (.1 + 2 * .5) * multiplier / 1e6
        assert abs(actual - expected) < .000001, (model, input_tokens, actual, expected)
PY
then
    test_pass
else
    test_fail "Haiku 5.5 pricing lost the strict threshold or whole-request multiplier"
fi

test_case "standalone metrics retain the session writer and complete request pricing"
if PROJECT_ROOT="$PROJECT_ROOT" python3 - <<'PY'
import json, os, pathlib, subprocess, tempfile
root = os.environ["PROJECT_ROOT"]
command = '''set -euo pipefail
source "$1/scripts/metrics-tracker.sh"
init_metrics_tracking
printf '%s|%s\\n' "$(date +%s)" "$3" > "$METRICS_BASE/.agent-start-pricing"
record_agent_complete pricing "$4" "$2" '' pricing "$(( $3 + 100000 ))" 0 1 "$3" 100000
'''
for model in ("claude-haiku-5-5", "anthropic/claude-haiku-5-5"):
    for provider in ("claude-sdk", "copilot"):
        for count in (99999, 100000, 100001):
            with tempfile.TemporaryDirectory() as workspace:
                env = dict(os.environ, METRICS_BASE=workspace)
                env.pop("WORKSPACE_DIR", None)
                subprocess.run(["bash", "-c", command, "test", root, model, str(count), provider], env=env, check=True)
                report = json.loads((pathlib.Path(workspace) / "metrics-session.json").read_text())
                expected = round((count * .1 + 100000 * .5) * (5 if count > 100000 else 1) / 1e6, 4)
                if provider == "copilot":
                    expected = 0
                assert report["totals"]["agent_calls"] == 1, report
                assert report["phases"][0]["metrics_source"] == "native", report
                assert abs(report["totals"]["estimated_cost_usd"] - expected) < .000001, (model, provider, count, report, expected)
                assert not (pathlib.Path(workspace) / "usage-session.json").exists()
PY
then
    test_pass
else
    test_fail "standalone metrics lost request pricing or replaced the metrics-session writer"
fi

test_case "standalone metrics use the Haiku 5.5 base input rate"
source "$PROJECT_ROOT/scripts/metrics-tracker.sh"
if [[ "$(get_model_cost claude-haiku-5-5)" == "0.10" ]]; then
    test_pass
else
    test_fail "Haiku 5.5 standalone input estimate is missing"
fi

test_case "routing suffix normalization preserves custom model identities"
if [[ "$(octo_model_canonical_id floor)" == "floor" &&
      "$(octo_model_canonical_id :nitro)" == ":nitro" &&
      "$(octo_model_canonical_id vendor/custom:nitro)" == "vendor/custom:nitro" &&
      "$(octo_model_canonical_id openai/gpt-6.1-sol:custom)" == "openai/gpt-6.1-sol:custom" &&
      "$(get_model_policy openai/gpt-6-astra:nitro)" == "explicit|no|0|1|limited" ]]; then
    test_pass
else
    test_fail "routing suffix normalization rewrote a custom ID or bypassed frontier policy"
fi

test_summary
