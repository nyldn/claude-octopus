#!/usr/bin/env bash
# Local configuration must admit the same provider that dispatch can run.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "UberLLM configuration parity"
FAKE_HOME="$TEST_TMP_DIR/home"
mkdir -p "$FAKE_HOME/.claude-octopus/config"
CONFIG="$FAKE_HOME/.claude-octopus/config/providers.json"
PROBE="$TEST_TMP_DIR/probe.sh"
cat > "$PROBE" <<'PROBE'
set -u
root="$1"; action="$2"
log() { :; }
if [[ "$action" == available-bounded-first ]]; then
    source "$root/scripts/lib/bounded-probe.sh"
fi
source "$root/scripts/lib/model-resolver.sh"
if [[ "$action" == available-bounded-first ]]; then
    is_agent_available_v2 "${PROBE_AGENT:-uberllm-agent}"
    exit $?
fi
source "$root/scripts/lib/dispatch.sh"
source "$root/scripts/lib/preflight.sh"
PLUGIN_DIR="$root"
PROVIDER_CODEX_INSTALLED=false
case "$action" in
 available) is_agent_available_v2 "${PROBE_AGENT:-uberllm-agent}" ;;
 available-standalone) unset -f validate_model_allowed; is_agent_available_v2 "${PROBE_AGENT:-uberllm-agent}" ;;
 available-bounded-first) is_agent_available_v2 "${PROBE_AGENT:-uberllm-agent}" ;;
 health) check_provider_health uberllm ;;
 health-qualified) check_provider_health uberllm "${PROBE_MODEL:-vendor/pinned}" ;;
 detection) detect_providers | grep -q 'uberllm:api-key' ;;
 readiness) _octo_provider_static_readiness uberllm | grep -q '^available|ready|' ;;
 dispatch) get_agent_command uberllm-agent review code-reviewer ;;
 qualified) get_agent_command "${PROBE_AGENT:-uberllm-agent:vendor/pinned}" review code-reviewer ;;
 resolved) get_agent_model "${PROBE_AGENT:-uberllm-agent}" review code-reviewer ;;
 model) octo_uberllm_model ;;
 family) octo_agent_spec_model_family "${PROBE_AGENT:-uberllm-agent}" ;;
esac
PROBE
probe() {
    local action="$1"; shift
    env -i "PATH=$PATH" "HOME=$FAKE_HOME" "OCTO_ALLOWED_PROVIDERS=uberllm" \
        "UBERLLM_API_KEY=fixture-key" "$@" bash "$PROBE" "$PROJECT_ROOT" "$action"
}
printf '%s\n' '{"providers":{"uberllm":{"default":"vendor/config-model"}}}' > "$CONFIG"
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
if command_text="$(probe qualified UBERLLM_MODEL=vendor/environment 2>/dev/null)" &&
   [[ "$command_text" == *'--model vendor/pinned'* && "$command_text" == *'--tool-policy none'* ]]; then
    test_pass
else
    test_fail "qualified model pin changed"
fi
test_case "model allowlist rejects an excluded qualified model"
if probe qualified UBERLLM_ALLOWED_MODELS=vendor/allowed >/dev/null 2>&1; then
    test_fail "excluded qualified model was admitted"
else
    test_pass
fi
test_case "model environment precedence preserves explicit pins"
if [[ "$(probe model UBERLLM_MODEL=vendor/primary OCTOPUS_UBERLLM_MODEL=vendor/octopus OPENAI_COMPAT_MODEL=vendor/generic)" == vendor/primary ]] &&
   [[ "$(probe model OCTOPUS_UBERLLM_MODEL=vendor/octopus OPENAI_COMPAT_MODEL=vendor/generic)" == vendor/octopus ]] &&
   [[ "$(probe model OPENAI_COMPAT_MODEL=vendor/generic)" == vendor/config-model ]]; then
    test_pass
else
    test_fail "model precedence changed"
fi
for value in 'null' 'true' '17' '{}' '[]' '"   "' '"bad;model"' '"/absolute"' '"vendor/model\n"' '"vendor/model\u0000"'; do
    printf '{"providers":{"uberllm":{"default":%s}}}\n' "$value" > "$CONFIG"
    test_case "invalid configured model $value fails closed"
    admitted=false
    for action in available health detection readiness dispatch resolved; do
        if probe "$action" >/dev/null 2>&1; then admitted=true; fi
    done
    if [[ "$admitted" == false ]]; then test_pass; else test_fail "invalid config admitted"; fi
done
printf '%s\n' '{"providers":{"uberllm":{"default":"vendor/config-model"}}}' > "$CONFIG"
test_case "invalid explicit model does not fall back to configured default"
if probe dispatch UBERLLM_MODEL='bad;model' >/dev/null 2>&1 ||
   probe readiness UBERLLM_MODEL='   ' >/dev/null 2>&1; then
    test_fail "invalid explicit pin fell back"
else
    test_pass
fi
printf '%s\n' '{broken' > "$CONFIG"
for value in $'vendor/\001' $'vendor/\177' $'vendor/model\n'; do
    test_case "control byte in environment model fails admissions and dispatch"
    admitted=false
    for action in available health detection readiness dispatch resolved; do
        if probe "$action" "UBERLLM_MODEL=$value" >/dev/null 2>&1; then admitted=true; fi
    done
    if [[ "$admitted" == false ]]; then test_pass; else test_fail "control byte admitted"; fi
done
test_case "malformed config fails closed but valid environment pin remains usable"
if probe dispatch >/dev/null 2>&1 || ! probe dispatch UBERLLM_MODEL=vendor/explicit >/dev/null 2>&1; then
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
if probe available PROBE_AGENT=uberllm-agent:vendor/pinned >/dev/null 2>&1; then test_pass; else test_fail "qualified pin required a redundant default"; fi
for model in '' $'vendor/\001' $'vendor/\177' 'bad;model'; do
    test_case "invalid qualified pin fails availability and dispatch"
    if probe available "PROBE_AGENT=uberllm-agent:$model" >/dev/null 2>&1 ||
       probe qualified "PROBE_AGENT=uberllm-agent:$model" >/dev/null 2>&1; then
        test_fail "invalid qualified pin admitted"
    else
        test_pass
    fi
done
test_case "invalid allowlist fallback fails dispatch"
if probe dispatch UBERLLM_MODEL=vendor/blocked UBERLLM_ALLOWED_MODELS=$'vendor/\001' >/dev/null 2>&1 ||
   probe resolved UBERLLM_MODEL=vendor/blocked UBERLLM_ALLOWED_MODELS=$'vendor/\001' >/dev/null 2>&1; then
    test_fail "control-byte fallback admitted"
else
    test_pass
fi
test_case "valid bare allowlist fallback remains supported"
if command_text="$(probe dispatch UBERLLM_MODEL=vendor/blocked UBERLLM_ALLOWED_MODELS=vendor/allowed 2>/dev/null)" &&
   [[ "$command_text" == *'--model vendor/allowed'* ]]; then test_pass; else test_fail "valid fallback rejected"; fi
test_case "whitespace-only key fails local admissions"
admitted=false
for action in available health detection readiness; do
    if probe "$action" UBERLLM_MODEL=vendor/model 'UBERLLM_API_KEY=   ' >/dev/null 2>&1; then admitted=true; fi
done
if [[ "$admitted" == false ]]; then test_pass; else test_fail "blank key admitted"; fi
test_case "native model resolution shares every documented environment pin and precedence"
if [[ "$(probe resolved UBERLLM_MODEL=vendor/primary)" == vendor/primary ]] &&
   ! probe resolved OPENAI_COMPAT_MODEL=vendor/generic >/dev/null 2>&1 &&
   [[ "$(probe resolved UBERLLM_MODEL=vendor/primary OCTOPUS_UBERLLM_MODEL=vendor/secondary)" == vendor/primary ]]; then
    test_pass
else
    test_fail "native model resolution diverged from dispatch"
fi
CUSTOM_CONFIG="$TEST_TMP_DIR/custom-providers.json"
printf '%s\n' '{"providers":{"uberllm":{"default":"vendor/custom-model"}}}' > "$CUSTOM_CONFIG"
test_case "custom provider config remains consistent across native resolution and admissions"
admitted=true
for action in available health detection readiness dispatch resolved; do
    if ! probe "$action" "OCTOPUS_PROVIDERS_CONFIG=$CUSTOM_CONFIG" >/dev/null 2>&1; then admitted=false; fi
done
if [[ "$admitted" == true && "$(probe resolved "OCTOPUS_PROVIDERS_CONFIG=$CUSTOM_CONFIG")" == vendor/custom-model ]]; then test_pass; else test_fail "custom config rejected or changed"; fi
test_case "qualified health honors the resolved pin without a default and over an invalid environment pin"
if probe health-qualified >/dev/null 2>&1 &&
   probe health-qualified UBERLLM_MODEL='bad;model' >/dev/null 2>&1 &&
   ! probe health-qualified PROBE_MODEL=$'vendor/\001' >/dev/null 2>&1; then
    test_pass
else
    test_fail "qualified health rejected the resolved pin or admitted controls"
fi
test_case "explicit-only model cannot be selected by an allowlist fallback"
if probe resolved UBERLLM_MODEL=vendor/blocked UBERLLM_ALLOWED_MODELS=gpt-6-astra >/dev/null 2>&1 ||
   probe dispatch UBERLLM_MODEL=vendor/blocked UBERLLM_ALLOWED_MODELS=gpt-6-astra >/dev/null 2>&1; then
    test_fail "explicit-only automatic fallback admitted"
else
    test_pass
fi
test_case "explicit-only model remains usable through an explicit user pin"
if [[ "$(probe resolved UBERLLM_MODEL=gpt-6-astra)" == gpt-6-astra ]] &&
   probe dispatch UBERLLM_MODEL=gpt-6-astra >/dev/null 2>&1 &&
   probe qualified PROBE_AGENT=uberllm-agent:gpt-6-astra >/dev/null 2>&1; then
    test_pass
else
    test_fail "explicit user pin rejected"
fi
for action in available available-standalone; do
    test_case "qualified $action enforces its allowlist without replacing the pin"
    if probe "$action" PROBE_AGENT=uberllm-agent:vendor/blocked UBERLLM_ALLOWED_MODELS=vendor/allowed >/dev/null 2>&1 ||
       ! probe "$action" PROBE_AGENT=uberllm-agent:vendor/allowed UBERLLM_ALLOWED_MODELS=vendor/allowed >/dev/null 2>&1; then
        test_fail "qualified availability bypassed its model policy or rejected an allowed pin"
    else
        test_pass
    fi
done
for action in available health detection readiness; do
    test_case "$action rejects a fallback requiring an explicit pin"
    if probe "$action" UBERLLM_MODEL=vendor/blocked UBERLLM_ALLOWED_MODELS=gpt-6-astra >/dev/null 2>&1; then
        test_fail "undispatchable fallback advertised by $action"
    else
        test_pass
    fi
    test_case "$action accepts a dispatchable allowlist fallback"
    if probe "$action" UBERLLM_MODEL=vendor/blocked UBERLLM_ALLOWED_MODELS=vendor/allowed >/dev/null 2>&1; then
        test_pass
    else
        test_fail "valid fallback rejected by $action"
    fi
done
test_case "bounded-probe source order preserves allowed exact-model admission"
if probe available-bounded-first PROBE_AGENT=uberllm-agent:vendor/allowed UBERLLM_ALLOWED_MODELS=vendor/allowed >/dev/null 2>&1 &&
   ! probe available-bounded-first PROBE_AGENT=uberllm-agent:vendor/blocked UBERLLM_ALLOWED_MODELS=vendor/allowed >/dev/null 2>&1; then
    test_pass
else
    test_fail "source order changed exact-model admission"
fi
test_case "effective model determines family for environment and fallback pins"
if [[ "$(probe family UBERLLM_MODEL=openai/gpt-5.6-sol)" == openai ]] &&
   [[ "$(probe family UBERLLM_MODEL=vendor/blocked UBERLLM_ALLOWED_MODELS=google/gemini-4-argon)" == google ]] &&
   [[ "$(probe family PROBE_AGENT=uberllm-agent:vendor/blocked UBERLLM_ALLOWED_MODELS=openai/gpt-5.6-sol)" == unknown ]]; then
    test_pass
else
    test_fail "gateway transport was mistaken for model-family independence"
fi
for value in 'bad model' 'bad,model' 'bad\\model' 'bad;model' 'bad|model' 'bad&model' 'bad$model' \
    'bad`model' "bad'model" 'bad"model' 'bad(model' 'bad)model' 'bad<model' 'bad>model' \
    'bad!model' 'bad*model' 'bad?model' 'bad[model' 'bad]model' 'bad{model' 'bad}model'; do
    test_case "unsafe model token fails the Bash 3.2 grammar: $value"
    if probe model "UBERLLM_MODEL=$value" >/dev/null 2>&1; then
        test_fail "unsafe token admitted"
    else
        test_pass
    fi
done
test_case "MCP environment retains model policy and refuses blocked exact pins"
if node --input-type=module - "$PROJECT_ROOT" "$PROBE" "$FAKE_HOME" <<'JS_MCP'
import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';
const [root, probe, home] = process.argv.slice(2);
const { loadProviderEnvAllowlist, providerEnvironment } = await import(pathToFileURL(`${root}/shared/adapter-runtime.mjs`));
const filtered = providerEnvironment(loadProviderEnvAllowlist(root), {
  UBERLLM_API_KEY: 'fixture-key', UBERLLM_MODEL: 'vendor/allowed',
  UBERLLM_ALLOWED_MODELS: 'vendor/allowed', UNAPPROVED_API_KEY: 'fixture-other',
});
assert.equal(filtered.UBERLLM_MODEL, 'vendor/allowed');
assert.equal(filtered.UBERLLM_ALLOWED_MODELS, 'vendor/allowed');
assert.equal(filtered.UNAPPROVED_API_KEY, undefined);
for (const action of ['available', 'qualified']) {
  for (const [model, allowed] of [['vendor/allowed', true], ['vendor/blocked', false]]) {
    const child = spawnSync('/bin/bash', [probe, root, action], {
      env: { ...filtered, PATH: process.env.PATH, HOME: home,
        OCTO_ALLOWED_PROVIDERS: 'uberllm', PROBE_AGENT: `uberllm-agent:${model}` },
      encoding: 'utf8', timeout: 15000,
    });
    assert.equal(child.status === 0, allowed, `${action}: ${model}`);
  }
}
JS_MCP
then test_pass; else test_fail "MCP filtering lost or bypassed UberLLM policy"; fi
printf '%s\n' '{"providers":{"uberllm":{"default":"gpt-6-astra"}}}' > "$CONFIG"
for action in available health detection readiness resolved dispatch; do
    test_case "$action rejects an explicit-only model from configured defaults"
    if probe "$action" >/dev/null 2>&1; then
        test_fail "configured default bypassed automatic-target admission in $action"
    else
        test_pass
    fi
done
test_case "configured defaults do not block explicit environment or qualified pins"
if [[ "$(probe resolved UBERLLM_MODEL=gpt-6-astra)" == gpt-6-astra ]] &&
   probe dispatch UBERLLM_MODEL=gpt-6-astra >/dev/null 2>&1 &&
   probe qualified PROBE_AGENT=uberllm-agent:gpt-6-astra >/dev/null 2>&1; then
    test_pass
else
    test_fail "automatic-target policy rejected an explicit user pin"
fi
test_case "a configured default may fall back to an allowed automatic model"
if command_text="$(probe dispatch UBERLLM_ALLOWED_MODELS=vendor/allowed 2>/dev/null)" &&
   [[ "$command_text" == *'--model vendor/allowed'* ]] &&
   [[ "$(probe resolved UBERLLM_ALLOWED_MODELS=vendor/allowed)" == vendor/allowed ]]; then
    test_pass
else
    test_fail "configured default could not select a safe allowlist fallback"
fi
test_summary
