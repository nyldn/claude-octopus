#!/usr/bin/env bash
# Contract tests for expensive, explicit-only frontier models.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Frontier model policy"

export WORKSPACE_DIR="$TEST_TMP_DIR/workspace"
mkdir -p "$WORKSPACE_DIR"

source "$PROJECT_ROOT/scripts/lib/models.sh"
source "$PROJECT_ROOT/scripts/lib/cost.sh"
source "$PROJECT_ROOT/scripts/lib/provider-versions.sh"

test_case "Fable 5.1 and Astra are canonical catalog entries"
if is_known_model claude-fable-5-1 && is_known_model gpt-6-astra &&
   grep -Fxq claude-fable-5-1 < <(octo_model_ids) &&
   grep -Fxq gpt-6-astra < <(octo_model_ids); then
    test_pass
else
    test_fail "missing claude-fable-5-1 or gpt-6-astra from canonical catalog"
fi

test_case "frontier metadata matches provider capabilities and rollout state"
fable_catalog="$(get_model_catalog claude-fable-5-1)"
astra_catalog="$(get_model_catalog gpt-6-astra)"
if [[ "$fable_catalog" == "1000|yes|yes|yes|claude|premium|active" &&
      "$astra_catalog" == "1050|yes|yes|yes|codex|premium|limited" ]]; then
    test_pass
else
    test_fail "unexpected frontier metadata: fable=$fable_catalog astra=$astra_catalog"
fi

test_case "frontier policy makes both models explicit-only and non-automatic"
if [[ "$(get_model_policy claude-fable-5-1)" == "explicit|no|0|1|general" &&
      "$(get_model_policy gpt-6-astra)" == "explicit|no|0|0|limited" ]] &&
   ! octo_model_auto_eligible claude-fable-5-1 &&
   ! octo_model_auto_eligible gpt-6-astra; then
    test_pass
else
    test_fail "expensive frontier models became eligible for automatic routing"
fi

test_case "model-config exposes explicit-only policy beside frontier models"
model_config_output="$(HOME="$TEST_TMP_DIR/home" bash "$PROJECT_ROOT/scripts/helpers/octo-model-config.sh" models 2>/dev/null)"
if grep -E '^  gpt-6-astra[[:space:]].*premium[[:space:]]+explicit[[:space:]]+limited$' <<< "$model_config_output" >/dev/null &&
   grep -E '^  claude-fable-5-1[[:space:]].*premium[[:space:]]+explicit[[:space:]]+active$' <<< "$model_config_output" >/dev/null; then
    test_pass
else
    test_fail "model-config hides the explicit-only frontier policy"
fi

test_case "model-config refuses frontier models on persisted configuration surfaces"
config_home="$TEST_TMP_DIR/config-home"
mkdir -p "$config_home"
if HOME="$config_home" bash "$PROJECT_ROOT/scripts/helpers/octo-model-config.sh" set codex gpt-6-astra >/dev/null 2>&1 ||
   HOME="$config_home" bash "$PROJECT_ROOT/scripts/helpers/octo-model-config.sh" tier premium codex gpt-6-astra >/dev/null 2>&1 ||
   HOME="$config_home" bash "$PROJECT_ROOT/scripts/helpers/octo-model-config.sh" tier premium codex codex:gpt-6-astra >/dev/null 2>&1 ||
   HOME="$config_home" bash "$PROJECT_ROOT/scripts/helpers/octo-model-config.sh" set codex.frontier gpt-6-astra >/dev/null 2>&1 ||
   HOME="$config_home" bash "$PROJECT_ROOT/scripts/helpers/octo-model-config.sh" route review codex:gpt-6-astra >/dev/null 2>&1 ||
   HOME="$config_home" bash "$PROJECT_ROOT/scripts/helpers/octo-model-config.sh" route-role reviewer codex:gpt-6-astra >/dev/null 2>&1 ||
   HOME="$config_home" bash "$PROJECT_ROOT/scripts/helpers/octo-model-config.sh" set claude claude-fable-5-1 >/dev/null 2>&1 ||
   HOME="$config_home" bash "$PROJECT_ROOT/scripts/helpers/octo-model-config.sh" set codex gpt-6-astra --session >/dev/null 2>&1; then
    test_fail "explicit-only model was accepted by an automatic config surface"
else
    session_model="$(jq -r '.overrides.codex // empty' "$config_home/.claude-octopus/config/providers.json")"
    if [[ -z "$session_model" ]]; then
        test_pass
    else
        test_fail "rejected Astra override was still persisted"
    fi
fi

test_case "lower-level provider setter refuses stored frontier models"
provider_home="$TEST_TMP_DIR/provider-home"
if HOME="$provider_home" PROJECT_ROOT="$PROJECT_ROOT" bash -c '
    validate_model_name() { [[ -n "${1:-}" ]]; }
    source "$PROJECT_ROOT/scripts/lib/provider-routing.sh" >/dev/null 2>&1
    ! set_provider_model codex gpt-6-astra >/dev/null 2>&1 &&
        ! set_provider_model claude claude-fable-5-1 --session >/dev/null 2>&1
'; then
    test_pass
else
    test_fail "set_provider_model allowed an explicit-only model into providers.json"
fi

test_case "legacy Fable remains explicit-only"
if [[ "$(get_model_policy claude-fable-5)" == "explicit|no|0|0|general" ]] &&
   ! octo_model_auto_eligible claude-fable-5; then
    test_pass
else
    test_fail "legacy Fable policy drifted"
fi

test_case "unknown models fail closed for automatic routing"
if [[ "$(get_model_policy invented-frontier-model)" == "explicit|no|0|0|unknown" ]] &&
   ! octo_model_auto_eligible invented-frontier-model; then
    test_pass
else
    test_fail "unknown model was eligible for automatic routing"
fi

test_case "current direct API prices are represented exactly"
if [[ "$(get_model_pricing claude-fable-5-1 claude)" == "10.00:50.00" &&
      "$(get_model_pricing gpt-6-astra codex)" == "10.00:50.00" &&
      "$(get_model_pricing gpt-5.6-sol codex)" == "4.00:20.00" &&
      "$(get_model_pricing gpt-5.6-terra codex)" == "2.00:12.00" &&
      "$(get_model_pricing gpt-5.6-luna codex)" == "0.20:1.20" &&
      "$(get_model_pricing claude-sonnet-5 claude)" == "2.00:10.00" ]]; then
    test_pass
else
    test_fail "frontier or adjacent model pricing is stale"
fi

test_case "Astra cost estimates include the long-context multiplier"
is_api_based_provider() { return 0; }
estimate_tokens() { printf '%s\n' 300000; }
astra_long_cost="$(estimate_agent_call_cost codex-api gpt-6-astra ignored)"
estimate_tokens() { printf '%s\n' 272000; }
astra_threshold_cost="$(estimate_agent_call_cost codex-api gpt-6-astra ignored)"
if [[ "$astra_long_cost" == "51.000000" && "$astra_threshold_cost" == "29.920000" ]]; then
    test_pass
else
    test_fail "Astra multiplier mismatch: long=$astra_long_cost threshold=$astra_threshold_cost"
fi

test_case "native usage parsing preserves separate input and output counts"
SUPPORTS_NATIVE_TASK_METRICS=true
SUPPORTS_OTEL_SPEED=false
parse_task_metrics $'<usage>\ninput_tokens: 272001\noutput_tokens: 127999\ntotal_tokens: 400000\ntool_uses: 3\nduration_ms: 1000\n</usage>'
if [[ "${_PARSED_INPUT_TOKENS:-}" == "272001" &&
      "${_PARSED_OUTPUT_TOKENS:-}" == "127999" &&
      "$_PARSED_TOKENS" == "400000" ]]; then
    test_pass
else
    test_fail "native usage parser discarded input/output token counts"
fi

test_case "session usage prices Astra from native input and output counts"
DRY_RUN=false
log() { :; }
init_usage_tracking
: > "${USAGE_FILE}.log"
record_agent_complete "astra-native-split" codex-api gpt-6-astra "" frontier \
    400000 0 1 272001 127999
native_usage="$(awk -F'|' 'END {print $6 ":" $7 ":" $8 ":" $9}' "${USAGE_FILE}.log")"
if [[ "$native_usage" == "272001:127999:400000:15.039945" ]]; then
    test_pass
else
    test_fail "session usage lost native token counts or Astra pricing: $native_usage"
fi

test_case "session usage uses the measured prompt when only native total is available"
estimate_tokens() { printf '%s\n' 272001; }
prompt_metrics_id="$(record_agent_start codex-api gpt-6-astra ignored frontier)"
record_agent_complete "$prompt_metrics_id" codex-api gpt-6-astra "" frontier 400000 0 1
fallback_usage="$(awk -F'|' 'END {print $6 ":" $7 ":" $8 ":" $9}' "${USAGE_FILE}.log")"
if [[ "$fallback_usage" == "272001:127999:400000:15.039945" ]]; then
    test_pass
else
    test_fail "session usage ignored measured prompt tokens: $fallback_usage"
fi

test_case "legacy metrics tracking uses canonical Astra input and output pricing"
source "$PROJECT_ROOT/scripts/metrics-tracker.sh"
METRICS_BASE="$TEST_TMP_DIR/metrics"
mkdir -p "$METRICS_BASE"
init_metrics_tracking
metrics_id="astra-test"
printf '%s|%s\n' "$(date +%s)" 300000 > "$METRICS_BASE/.agent-start-$metrics_id"
record_agent_complete "$metrics_id" codex gpt-6-astra "" frontier 400000 0 1 272001 127999
metrics_cost="$(jq -r '.phases[0].estimated_cost_usd' "$METRICS_BASE/metrics-session.json")"
if [[ "$metrics_cost" == "15.0399" ]]; then
    test_pass
else
    test_fail "legacy metrics tracker discarded native input/output counts: $metrics_cost"
fi

test_case "legacy metrics token totals include estimated prompt and output"
metrics_id="estimated-token-test"
printf '%s|%s\n' "$(date +%s)" 300 > "$METRICS_BASE/.agent-start-$metrics_id"
record_agent_complete "$metrics_id" codex gpt-5.6-sol "$(printf '%400s' '')" frontier
estimated_tokens="$(jq -r '.phases[1].estimated_tokens' "$METRICS_BASE/metrics-session.json")"
if [[ "$estimated_tokens" == "400" ]]; then
    test_pass
else
    test_fail "legacy metrics tracker recorded $estimated_tokens estimated tokens instead of 400"
fi

test_case "Astra requires the Codex release that added its catalog entry"
if ! octo_codex_model_version_ok 0.153.0 gpt-6-astra &&
   octo_codex_model_version_ok 0.153.1 gpt-6-astra &&
   octo_codex_model_version_ok 0.153.3 gpt-6-astra &&
   ! octo_codex_model_version_ok unknown gpt-6-astra &&
   octo_codex_model_version_ok 0.144.0 gpt-5.6-sol; then
    test_pass
else
    test_fail "Astra's model-specific Codex version gate is missing"
fi

test_case "Codex command construction refuses Astra on an old CLI"
PLUGIN_DIR="$PROJECT_ROOT"
log() { :; }
source "$PROJECT_ROOT/scripts/lib/dispatch.sh"
fake_codex_bin="$TEST_TMP_DIR/fake-codex-bin"
mkdir -p "$fake_codex_bin"
cat > "$fake_codex_bin/codex" <<'EOF'
#!/bin/sh
printf 'codex-cli %s\n' "${OCTOPUS_TEST_CODEX_VERSION:?}"
EOF
chmod +x "$fake_codex_bin/codex"
if PATH="$fake_codex_bin:$PATH" OCTOPUS_TEST_CODEX_VERSION=0.153.0 \
   _build_codex_exec_command gpt-6-astra '--sandbox workspace-write' '' >/dev/null 2>&1; then
    test_fail "old Codex CLI was allowed to dispatch Astra"
else
    astra_command="$(PATH="$fake_codex_bin:$PATH" OCTOPUS_TEST_CODEX_VERSION=0.153.1 \
        _build_codex_exec_command gpt-6-astra '--sandbox workspace-write' '' 2>/dev/null || true)"
    if [[ "$astra_command" == 'codex exec --skip-git-repo-check --model gpt-6-astra --sandbox workspace-write -' ]]; then
        test_pass
    else
        test_fail "supported Codex CLI could not dispatch an explicit Astra pin"
    fi
fi

test_case "Astra version lookup ignores the removed environment override"
reported_version="$(PATH="$fake_codex_bin:$PATH" OCTOPUS_TEST_CODEX_VERSION=0.153.0 \
    OCTO_CODEX_VERSION_OVERRIDE=9.9.9 octo_codex_installed_version)"
if [[ "$reported_version" == "0.153.0" ]]; then
    test_pass
else
    test_fail "version lookup trusted OCTO_CODEX_VERSION_OVERRIDE: $reported_version"
fi

test_summary
