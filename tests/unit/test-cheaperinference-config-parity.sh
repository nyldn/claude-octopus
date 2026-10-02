#!/usr/bin/env bash
# Local configuration must admit the same provider that dispatch can run.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Cheaper Inference configuration parity"
FAKE_HOME="$TEST_TMP_DIR/home"
mkdir -p "$FAKE_HOME/.claude-octopus/config"
CONFIG="$FAKE_HOME/.claude-octopus/config/providers.json"
PROBE="$TEST_TMP_DIR/probe.sh"
cat > "$PROBE" <<'PROBE'
set -u
root="$1"; action="$2"
log() { :; }
source "$root/scripts/lib/model-resolver.sh"
source "$root/scripts/lib/dispatch.sh"
source "$root/scripts/lib/preflight.sh"
PLUGIN_DIR="$root"
PROVIDER_CODEX_INSTALLED=false
case "$action" in
 available) is_agent_available_v2 "${PROBE_AGENT:-cheaperinference-agent}" ;;
 health) check_provider_health cheaperinference ;;
 health-qualified) check_provider_health cheaperinference "${PROBE_MODEL:-vendor/pinned}" ;;
 detection) detect_providers | grep -q 'cheaperinference:api-key' ;;
 readiness) _octo_provider_static_readiness cheaperinference | grep -q '^available|ready|' ;;
 dispatch) get_agent_command cheaperinference-agent review code-reviewer ;;
 qualified) get_agent_command "${PROBE_AGENT:-cheaperinference-agent:vendor/pinned}" review code-reviewer ;;
 resolved) get_agent_model "${PROBE_AGENT:-cheaperinference-agent}" review code-reviewer ;;
 model) octo_cheaperinference_model ;;
esac
PROBE
probe() {
    local action="$1"; shift
    env -i "PATH=$PATH" "HOME=$FAKE_HOME" "OCTO_ALLOWED_PROVIDERS=cheaperinference" \
        "CHEAPER_INFERENCE_API_KEY=fixture-key" "$@" bash "$PROBE" "$PROJECT_ROOT" "$action"
}
printf '%s\n' '{"providers":{"cheaperinference":{"default":"vendor/config-model"}}}' > "$CONFIG"
for action in available health detection readiness resolved; do
    test_case "configured default passes $action"
    if probe "$action" >/dev/null 2>&1; then test_pass; else test_fail "configured default rejected by $action"; fi
done
test_case "configured default dispatch keeps read-only policy"
if command_text="$(probe dispatch 2>/dev/null)" &&
    [[ "$command_text" == *'--model vendor/config-model'* && "$command_text" == *'--tool-policy none'* ]]; then
    test_pass
else
    test_fail "configured default failed dispatch or omitted read-only policy"
fi
test_case "qualified model pin remains exact"
if command_text="$(probe qualified CHEAPER_INFERENCE_MODEL=vendor/environment 2>/dev/null)" &&
   [[ "$command_text" == *'--model vendor/pinned'* && "$command_text" == *'--tool-policy none'* ]]; then
    test_pass
else
    test_fail "qualified model pin changed"
fi
test_case "model allowlist rejects an excluded qualified model"
if probe qualified CHEAPER_INFERENCE_ALLOWED_MODELS=vendor/allowed >/dev/null 2>&1; then
    test_fail "excluded qualified model was admitted"
else
    test_pass
fi
test_case "model environment precedence preserves explicit pins"
if [[ "$(probe model CHEAPER_INFERENCE_MODEL=vendor/primary OCTOPUS_CHEAPERINFERENCE_MODEL=vendor/octopus OPENAI_COMPAT_MODEL=vendor/generic)" == vendor/primary ]] &&
   [[ "$(probe model OCTOPUS_CHEAPERINFERENCE_MODEL=vendor/octopus OPENAI_COMPAT_MODEL=vendor/generic)" == vendor/octopus ]] &&
   [[ "$(probe model OPENAI_COMPAT_MODEL=vendor/generic)" == vendor/generic ]]; then
    test_pass
else
    test_fail "model precedence changed"
fi
for value in 'null' 'true' '17' '{}' '[]' '"   "' '"bad;model"' '"/absolute"' '"vendor/model\n"' '"vendor/model\u0000"'; do
    printf '{"providers":{"cheaperinference":{"default":%s}}}\n' "$value" > "$CONFIG"
    test_case "invalid configured model $value fails closed"
    admitted=false
    for action in available health detection readiness dispatch resolved; do
        if probe "$action" >/dev/null 2>&1; then admitted=true; fi
    done
    if [[ "$admitted" == false ]]; then test_pass; else test_fail "invalid config admitted"; fi
done
printf '%s\n' '{"providers":{"cheaperinference":{"default":"vendor/config-model"}}}' > "$CONFIG"
test_case "invalid explicit model does not fall back to configured default"
if probe dispatch CHEAPER_INFERENCE_MODEL='bad;model' >/dev/null 2>&1 ||
   probe readiness CHEAPER_INFERENCE_MODEL='   ' >/dev/null 2>&1; then
    test_fail "invalid explicit pin fell back"
else
    test_pass
fi
printf '%s\n' '{broken' > "$CONFIG"
for value in $'vendor/\001' $'vendor/\177' $'vendor/model\n'; do
    test_case "control byte in environment model fails admissions and dispatch"
    admitted=false
    for action in available health detection readiness dispatch resolved; do
        if probe "$action" "CHEAPER_INFERENCE_MODEL=$value" >/dev/null 2>&1; then admitted=true; fi
    done
    if [[ "$admitted" == false ]]; then test_pass; else test_fail "control byte admitted"; fi
done
test_case "malformed config fails closed but valid environment pin remains usable"
if probe dispatch >/dev/null 2>&1 || ! probe dispatch CHEAPER_INFERENCE_MODEL=vendor/explicit >/dev/null 2>&1; then
    test_fail "malformed config or explicit override mishandled"
else
    test_pass
fi
rm -f "$CONFIG"
test_case "missing model fails all admissions and dispatch"
admitted=false
for action in available health detection readiness dispatch resolved; do
    if probe "$action" >/dev/null 2>&1; then admitted=true; fi
done
if [[ "$admitted" == false ]]; then test_pass; else test_fail "missing model admitted"; fi
test_case "qualified availability accepts an exact pin without another configured model"
if probe available PROBE_AGENT=cheaperinference-agent:vendor/pinned >/dev/null 2>&1; then test_pass; else test_fail "qualified pin required a redundant default"; fi
for model in '' $'vendor/\001' $'vendor/\177' 'bad;model'; do
    test_case "invalid qualified pin fails availability and dispatch"
    if probe available "PROBE_AGENT=cheaperinference-agent:$model" >/dev/null 2>&1 ||
       probe qualified "PROBE_AGENT=cheaperinference-agent:$model" >/dev/null 2>&1; then
        test_fail "invalid qualified pin admitted"
    else
        test_pass
    fi
done
test_case "invalid allowlist fallback fails dispatch"
if probe dispatch CHEAPER_INFERENCE_MODEL=vendor/blocked CHEAPER_INFERENCE_ALLOWED_MODELS=$'vendor/\001' >/dev/null 2>&1 ||
   probe resolved CHEAPER_INFERENCE_MODEL=vendor/blocked CHEAPER_INFERENCE_ALLOWED_MODELS=$'vendor/\001' >/dev/null 2>&1; then
    test_fail "control-byte fallback admitted"
else
    test_pass
fi
test_case "valid bare allowlist fallback remains supported"
if command_text="$(probe dispatch CHEAPER_INFERENCE_MODEL=vendor/blocked CHEAPER_INFERENCE_ALLOWED_MODELS=vendor/allowed 2>/dev/null)" &&
   [[ "$command_text" == *'--model vendor/allowed'* ]]; then test_pass; else test_fail "valid fallback rejected"; fi
test_case "whitespace-only key fails local admissions"
admitted=false
for action in available health detection readiness; do
    if probe "$action" CHEAPER_INFERENCE_MODEL=vendor/model 'CHEAPER_INFERENCE_API_KEY=   ' >/dev/null 2>&1; then admitted=true; fi
done
if [[ "$admitted" == false ]]; then test_pass; else test_fail "blank key admitted"; fi
test_case "native model resolution shares every documented environment pin and precedence"
if [[ "$(probe resolved CHEAPER_INFERENCE_MODEL=vendor/primary)" == vendor/primary ]] &&
   [[ "$(probe resolved OPENAI_COMPAT_MODEL=vendor/generic)" == vendor/generic ]] &&
   [[ "$(probe resolved CHEAPER_INFERENCE_MODEL=vendor/primary OCTOPUS_CHEAPERINFERENCE_MODEL=vendor/secondary)" == vendor/primary ]]; then
    test_pass
else
    test_fail "native model resolution diverged from dispatch"
fi
CUSTOM_CONFIG="$TEST_TMP_DIR/custom-providers.json"
printf '%s\n' '{"providers":{"cheaperinference":{"default":"vendor/custom-model"}}}' > "$CUSTOM_CONFIG"
test_case "custom provider config remains consistent across native resolution and admissions"
admitted=true
for action in available health detection readiness dispatch resolved; do
    if ! probe "$action" "OCTOPUS_PROVIDERS_CONFIG=$CUSTOM_CONFIG" >/dev/null 2>&1; then admitted=false; fi
done
if [[ "$admitted" == true && "$(probe resolved "OCTOPUS_PROVIDERS_CONFIG=$CUSTOM_CONFIG")" == vendor/custom-model ]]; then test_pass; else test_fail "custom config rejected or changed"; fi
test_case "qualified health honors the resolved pin without a default and over an invalid environment pin"
if probe health-qualified >/dev/null 2>&1 &&
   probe health-qualified CHEAPER_INFERENCE_MODEL='bad;model' >/dev/null 2>&1 &&
   ! probe health-qualified PROBE_MODEL=$'vendor/\001' >/dev/null 2>&1; then
    test_pass
else
    test_fail "qualified health rejected the resolved pin or admitted controls"
fi
test_summary
