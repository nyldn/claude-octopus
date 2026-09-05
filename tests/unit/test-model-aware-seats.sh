#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Model-aware seats"
cd "$PROJECT_ROOT"

source scripts/lib/agent-spec.sh

test_case "agent spec separates executor and explicit model"
if [[ "$(octo_agent_spec_executor 'commandcode:stealth/ox-alpha')" == commandcode ]] && \
   [[ "$(octo_agent_spec_explicit_model 'commandcode:stealth/ox-alpha')" == stealth/ox-alpha ]]; then test_pass; else test_fail "agent spec parsing mismatch"; fi

test_case "agent spec slug is path-safe"
[[ "$(octo_agent_spec_slug 'commandcode:stealth/ox-alpha')" == commandcode_stealth_ox-alpha ]] && test_pass || test_fail "unexpected slug"

test_case "legacy executor aliases stay intact while provider identity is canonicalized"
if [[ "$(octo_agent_spec_executor 'codex-standard')" == codex-standard ]] && \
   [[ "$(octo_agent_spec_provider 'codex-standard')" == codex ]] && \
   [[ "$(octo_agent_spec_provider 'commandcode:stealth/ox-alpha')" == commandcode ]]; then
  test_pass
else
  test_fail "executor alias and provider identity were conflated"
fi

test_case "model family distinguishes MiniMax and OpenAI"
if [[ "$(octo_model_family 'commandcode:minimaxai/minimax-m3')" == minimax ]] && \
   [[ "$(octo_model_family 'codex:gpt-5.6-luna')" == openai ]]; then test_pass; else test_fail "model family mismatch"; fi

log(){ :; }
PLUGIN_DIR="$PROJECT_ROOT"
_BARE_OPT=""
source scripts/lib/utils.sh
source scripts/lib/validation.sh
source scripts/lib/model-resolver.sh
source scripts/lib/dispatch.sh

# Keep exact-model command-shape coverage independent of the host AGY catalog.
# Provider catalog membership is covered by test-agy-provider.sh.
validate_agy_model_name() { validate_model_name "$1"; }

test_case "model-qualified dispatch preserves CommandCode and Codex pins"
cc_model="$(get_agent_model 'commandcode:stealth/ox-alpha' ceremony code-reviewer)"
codex_model="$(get_agent_model 'codex:gpt-5.6-luna' ceremony code-reviewer)"
cc_cmd="$(get_agent_command 'commandcode:stealth/ox-alpha' ceremony code-reviewer)"
codex_cmd="$(get_agent_command 'codex:gpt-5.6-luna' ceremony code-reviewer)"
if [[ "$cc_model" == stealth/ox-alpha && "$codex_model" == gpt-5.6-luna && "$cc_cmd" == *'commandcode-exec.sh stealth/ox-alpha'* && "$codex_cmd" == *'--model gpt-5.6-luna'* ]]; then test_pass; else test_fail "model-qualified dispatch mismatch"; fi

test_case "qualified contextual providers carry the exact model into dispatch"
exact_model='vendor/seat-exact-model'
agy_cmd="$(get_agent_command "agy:${exact_model}" review implementation-security-reviewer 2>/dev/null || true)"
claude_cmd="$(get_agent_command "claude:${exact_model}" review implementation-architecture-reviewer 2>/dev/null || true)"
opus_cmd="$(get_agent_command "claude-opus:${exact_model}" review implementation-architecture-reviewer 2>/dev/null || true)"
openrouter_cmd="$(get_agent_command "openrouter:${exact_model}" review implementation-diversity-reviewer 2>/dev/null || true)"
orcarouter_cmd="$(get_agent_command "orcarouter:${exact_model}" review implementation-diversity-reviewer 2>/dev/null || true)"
vibe_cmd="$(get_agent_command "vibe:${exact_model}" review implementation-diversity-reviewer 2>/dev/null || true)"
atlas_cmd="$(get_agent_command "atlascloud-agent:${exact_model}" review implementation-cve-reviewer 2>/dev/null || true)"
if [[ "$agy_cmd" == *"OCTOPUS_AGY_MODEL=${exact_model}"* ]] && \
   [[ "$claude_cmd" == *"--model ${exact_model}"* ]] && \
   [[ "$opus_cmd" == *"--model ${exact_model}"* ]] && \
   [[ "$openrouter_cmd" == "openrouter_execute_model ${exact_model}" ]] && \
   [[ "$orcarouter_cmd" == "orcarouter_execute_model ${exact_model}" ]] && \
   [[ "$vibe_cmd" == *"OCTOPUS_VIBE_MODEL=${exact_model}"* ]] && \
   [[ "$atlas_cmd" == *"--provider atlascloud --model ${exact_model}"* ]] && \
   validate_agent_command "$agy_cmd" && \
   validate_agent_command "$claude_cmd" && \
   validate_agent_command "$opus_cmd" && \
   validate_agent_command "$openrouter_cmd" && \
   validate_agent_command "$orcarouter_cmd" && \
   validate_agent_command "$vibe_cmd" && \
   validate_agent_command "$atlas_cmd"; then
  test_pass
else
  test_fail "an exact contextual model was omitted: agy=[$agy_cmd] claude=[$claude_cmd] opus=[$opus_cmd] openrouter=[$openrouter_cmd] orcarouter=[$orcarouter_cmd] vibe=[$vibe_cmd] atlas=[$atlas_cmd]"
fi

test_case "Codex review dispatch enforces Astra's model-specific CLI floor"
fake_codex_bin="$TEST_TMP_DIR/fake-codex-bin"
mkdir -p "$fake_codex_bin"
cat > "$fake_codex_bin/codex" <<'EOF'
#!/bin/sh
printf 'codex-cli %s\n' "${OCTOPUS_TEST_CODEX_VERSION:?}"
EOF
chmod +x "$fake_codex_bin/codex"
astra_review_old_rc=0
astra_review_old="$(PATH="$fake_codex_bin:$PATH" OCTOPUS_TEST_CODEX_VERSION=0.153.0 \
    get_agent_command 'codex-review:gpt-6-astra' review implementation-logic-reviewer 2>/dev/null)" || astra_review_old_rc=$?
astra_review_new="$(PATH="$fake_codex_bin:$PATH" OCTOPUS_TEST_CODEX_VERSION=0.153.1 \
    get_agent_command 'codex-review:gpt-6-astra' review implementation-logic-reviewer 2>/dev/null || true)"
if [[ "$astra_review_old_rc" -ne 0 && -z "$astra_review_old" ]] &&
   [[ "$astra_review_new" == *'codex exec review --model gpt-6-astra'* ]]; then
  test_pass
else
  test_fail "Astra review floor mismatch: old_rc=$astra_review_old_rc old=[$astra_review_old] new=[$astra_review_new]"
fi

test_case "explicit Claude seats preserve dotted model IDs byte-for-byte"
claude_dotted_cmd="$(get_agent_command 'claude:claude-3.5-sonnet' review implementation-architecture-reviewer 2>/dev/null || true)"
opus_dotted_cmd="$(get_agent_command 'claude-opus:claude-3.5-sonnet' review implementation-architecture-reviewer 2>/dev/null || true)"
if [[ "$claude_dotted_cmd" == *'--model claude-3.5-sonnet'* ]] &&
   [[ "$opus_dotted_cmd" == *'--model claude-3.5-sonnet'* ]] &&
   [[ "$claude_dotted_cmd" != *'--model claude-3-5-sonnet'* ]] &&
   [[ "$opus_dotted_cmd" != *'--model claude-3-5-sonnet'* ]]; then
  test_pass
else
  test_fail "explicit dotted Claude model was normalized: claude=[$claude_dotted_cmd] opus=[$opus_dotted_cmd]"
fi

test_case "unqualified Claude routes retain legacy dotted-model normalization"
legacy_claude_cmd="$(OCTOPUS_CLAUDE_MODEL='claude-3.5-sonnet' get_agent_command claude review implementation-architecture-reviewer 2>/dev/null || true)"
legacy_opus_cmd="$(OCTOPUS_OPUS_MODEL='claude-3.5-sonnet' get_agent_command claude-opus review implementation-architecture-reviewer 2>/dev/null || true)"
if [[ "$legacy_claude_cmd" == *'--model claude-3-5-sonnet'* ]] &&
   [[ "$legacy_opus_cmd" == *'--model claude-3-5-sonnet'* ]]; then
  test_pass
else
  test_fail "legacy Claude normalization changed: claude=[$legacy_claude_cmd] opus=[$legacy_opus_cmd]"
fi

test_case "an explicit model blocked by restrictions fails instead of falling back"
OCTOPUS_CODEX_ALLOWED_MODELS='gpt-5.6-luna'
restricted_rc=0
restricted_out="$(get_agent_model 'codex:gpt-5.6-sol' review implementation-logic-reviewer 2>/dev/null)" || restricted_rc=$?
unset OCTOPUS_CODEX_ALLOWED_MODELS
if [[ "$restricted_rc" -ne 0 && -z "$restricted_out" ]]; then
  test_pass
else
  test_fail "explicit model restriction silently substituted rc=$restricted_rc out=[$restricted_out]"
fi

test_case "an exact Fable model fails closed for security dispatches"
fable_security_rc=0
fable_security_out="$(get_agent_command 'claude-opus:claude-fable-5' review implementation-security-reviewer 2>/dev/null)" || fable_security_rc=$?
if [[ "$fable_security_rc" -ne 0 && -z "$fable_security_out" ]]; then
  test_pass
else
  test_fail "unsafe exact Fable security pin was dispatched rc=$fable_security_rc out=[$fable_security_out]"
fi

test_case "an exact Fable 5.1 model fails closed for security dispatches"
fable51_security_rc=0
fable51_security_out="$(get_agent_command 'claude-opus:claude-fable-5-1' review implementation-security-reviewer 2>/dev/null)" || fable51_security_rc=$?
if [[ "$fable51_security_rc" -ne 0 && -z "$fable51_security_out" ]]; then
  test_pass
else
  test_fail "unsafe exact Fable 5.1 security pin was dispatched rc=$fable51_security_rc out=[$fable51_security_out]"
fi

test_case "ordinary Claude env pins cannot bypass Fable security rerouting"
fable_env_security="$(OCTOPUS_CLAUDE_MODEL=claude-fable-5-1 get_agent_command claude review implementation-security-reviewer 2>/dev/null || true)"
if [[ "$fable_env_security" == *'--model claude-opus-5'* ]] && [[ "$fable_env_security" != *'claude-fable-5-1'* ]]; then
  test_pass
else
  test_fail "ordinary Claude Fable security pin bypassed rerouting: [$fable_env_security]"
fi

test_case "exact Fable seats fail closed above the input ceiling"
large_prompt_bytes=600000
fable_claude_rc=0
fable_opus_rc=0
fable_sdk_rc=0
OCTOPUS_FABLE5_MAX_INPUT_BYTES=1 get_agent_command 'claude:claude-fable-5-1' review implementation-logic-reviewer "$large_prompt_bytes" >/dev/null 2>&1 || fable_claude_rc=$?
OCTOPUS_FABLE5_MAX_INPUT_BYTES=1 get_agent_command 'claude-opus:claude-fable-5-1' review implementation-logic-reviewer "$large_prompt_bytes" >/dev/null 2>&1 || fable_opus_rc=$?
OCTOPUS_FABLE5_MAX_INPUT_BYTES=1 get_agent_command 'claude-sdk:claude-fable-5-1' review implementation-logic-reviewer "$large_prompt_bytes" >/dev/null 2>&1 || fable_sdk_rc=$?
if [[ "$fable_claude_rc" -ne 0 && "$fable_opus_rc" -ne 0 && "$fable_sdk_rc" -ne 0 ]]; then
  test_pass
else
  test_fail "oversized exact Fable seat escaped input gate: claude=$fable_claude_rc opus=$fable_opus_rc sdk=$fable_sdk_rc"
fi

test_case "ordinary Fable pins fall back above the input ceiling"
implicit_claude="$(OCTOPUS_FABLE5_MAX_INPUT_BYTES=1 OCTOPUS_CLAUDE_MODEL=claude-fable-5-1 \
  get_agent_command claude review implementation-logic-reviewer "$large_prompt_bytes" 2>/dev/null || true)"
implicit_sonnet="$(OCTOPUS_FABLE5_MAX_INPUT_BYTES=1 OCTOPUS_CLAUDE_MODEL=claude-fable-5-1 \
  get_agent_command claude-sonnet review implementation-logic-reviewer "$large_prompt_bytes" 2>/dev/null || true)"
implicit_sdk="$(OCTOPUS_FABLE5_MAX_INPUT_BYTES=1 OCTOPUS_CLAUDE_SDK_MODEL=claude-fable-5-1 \
  get_agent_command claude-sdk review implementation-logic-reviewer "$large_prompt_bytes" 2>/dev/null || true)"
if [[ "$implicit_claude" == *'--model claude-opus-5'* ]] &&
   [[ "$implicit_sonnet" == *'--model claude-opus-5'* ]] &&
   [[ "$implicit_sdk" == *'OCTOPUS_CLAUDE_SDK_MODEL=claude-opus-5'* ]]; then
  test_pass
else
  test_fail "ordinary Fable pin bypassed input fallback: claude=[$implicit_claude] sonnet=[$implicit_sonnet] sdk=[$implicit_sdk]"
fi

test_case "an exact Claude SDK Fable seat disables the shim retry without changing compatibility routes"
exact_fable_sdk_cmd="$(get_agent_command 'claude-sdk:claude-fable-5' review implementation-logic-reviewer 2>/dev/null || true)"
compat_fable_sdk_cmd="$(OCTOPUS_CLAUDE_SDK_MODEL=claude-fable-5 get_agent_command claude-sdk review implementation-logic-reviewer 2>/dev/null || true)"
if [[ "$exact_fable_sdk_cmd" == "env OCTOPUS_CLAUDE_SDK_MODEL=claude-fable-5 OCTOPUS_FABLE5_NO_RETRY=1 $PROJECT_ROOT/scripts/helpers/claude-sdk-exec.sh" ]] && \
   [[ "$compat_fable_sdk_cmd" == "env OCTOPUS_CLAUDE_SDK_MODEL=claude-fable-5 $PROJECT_ROOT/scripts/helpers/claude-sdk-exec.sh" ]]; then
  test_pass
else
  test_fail "exact/default Fable retry contract mismatch: exact=[$exact_fable_sdk_cmd] compatibility=[$compat_fable_sdk_cmd]"
fi

test_case "an exact Claude SDK Fable 5.1 seat disables the shim retry"
exact_fable51_sdk_cmd="$(get_agent_command 'claude-sdk:claude-fable-5-1' review implementation-logic-reviewer 2>/dev/null || true)"
if [[ "$exact_fable51_sdk_cmd" == "env OCTOPUS_CLAUDE_SDK_MODEL=claude-fable-5-1 OCTOPUS_FABLE5_NO_RETRY=1 $PROJECT_ROOT/scripts/helpers/claude-sdk-exec.sh" ]]; then
  test_pass
else
  test_fail "exact Fable 5.1 retry contract mismatch: [$exact_fable51_sdk_cmd]"
fi

test_case "review order keeps same-provider model variants and Ox Alpha before Luna"
fake="$TEST_TMP_DIR/provider-check.sh"
cat > "$fake" <<'CHECK'
#!/usr/bin/env bash
echo commandcode:available
echo codex:available
echo claude:available
CHECK
chmod +x "$fake"
order="$(OCTOPUS_PROVIDER_CHECKER="$fake" OCTOPUS_COUNCIL_DEFAULT_PROVIDERS='commandcode:stealth/ox-alpha,commandcode:minimaxai/minimax-m3,commandcode:deepseek/deepseek-v4-flash,codex:gpt-5.6-luna,codex:gpt-5.6-sol' bash scripts/helpers/build-fleet.sh review-order standard test)"
ox_line="$(printf '%s\n' "$order" | grep -n -F 'commandcode:stealth/ox-alpha' | head -1 | cut -d: -f1)"
luna_line="$(printf '%s\n' "$order" | grep -n -F 'codex:gpt-5.6-luna' | head -1 | cut -d: -f1)"
all_present=true
for spec in 'commandcode:stealth/ox-alpha' 'commandcode:minimaxai/minimax-m3' 'commandcode:deepseek/deepseek-v4-flash' 'codex:gpt-5.6-luna' 'codex:gpt-5.6-sol'; do
  printf '%s\n' "$order" | grep -Fxq "$spec" || all_present=false
done
if [[ "$all_present" == true && -n "$ox_line" && -n "$luna_line" && "$ox_line" -lt "$luna_line" ]]; then test_pass; else test_fail "review order mismatch"; fi

source scripts/lib/council.sh
council_prompt_for_member(){ echo prompt; }
council_persona_should_fail(){ return 1; }
run_quorum_case(){
  local roster="$1" d
  d="$TEST_TMP_DIR/quorum-$RANDOM"
  mkdir -p "$d/responses"
  COUNCIL_RUN_DIR="$d"
  COUNCIL_DEPTH=standard
  COUNCIL_FIXTURE=full-success
  COUNCIL_EXECUTION_MODE=""
  COUNCIL_TASK=x
  COUNCIL_GOAL=advice
  COUNCIL_DOMAIN=auto
  COUNCIL_STYLE=balanced
  COUNCIL_ROSTER_JSON="$roster"
  council_run_advice_phase >/dev/null 2>&1 || true
}

test_case "same provider with different model families contributes independent quorum"
case_a='[{"persona":"strategy-analyst","seat":"chair","agent_spec":"claude-sonnet","provider":"claude-sonnet","provider_org":"anthropic","model":"claude-sonnet-5","model_family":"anthropic"},{"persona":"code-reviewer","seat":"member","agent_spec":"commandcode:minimaxai/minimax-m3","provider":"commandcode","provider_org":"commandcode","model":"minimaxai/minimax-m3","model_family":"minimax"},{"persona":"backend-architect","seat":"member","agent_spec":"commandcode:deepseek/deepseek-v4-flash","provider":"commandcode","provider_org":"commandcode","model":"deepseek/deepseek-v4-flash","model_family":"deepseek"}]'
run_quorum_case "$case_a"
if [[ "$COUNCIL_QUORUM_MET" == true && "$COUNCIL_DISTINCT_APPROVING_MODEL_FAMILIES" == 2 && "$COUNCIL_DISTINCT_APPROVING_PROVIDERS" == 1 ]]; then test_pass; else test_fail "same-provider family quorum mismatch"; fi

test_case "different providers with one model family do not create false independence"
case_b='[{"persona":"strategy-analyst","seat":"chair","agent_spec":"claude-sonnet","provider":"claude-sonnet","provider_org":"anthropic","model":"claude-sonnet-5","model_family":"anthropic"},{"persona":"code-reviewer","seat":"member","agent_spec":"commandcode:openai/gpt-5","provider":"commandcode","provider_org":"commandcode","model":"openai/gpt-5","model_family":"openai"},{"persona":"backend-architect","seat":"member","agent_spec":"codex:gpt-5.6-luna","provider":"codex","provider_org":"openai","model":"gpt-5.6-luna","model_family":"openai"}]'
run_quorum_case "$case_b"
if [[ "$COUNCIL_QUORUM_MET" == false && "$COUNCIL_DISTINCT_APPROVING_MODEL_FAMILIES" == 1 && "$COUNCIL_DISTINCT_APPROVING_PROVIDERS" == 2 ]]; then test_pass; else test_fail "same-family quorum mismatch"; fi


test_case "model-qualified large-context Codex keeps the large context budget"
OCTOPUS_CONTEXT_BUDGET=12000
OCTOPUS_CODEX_CONTEXT_BUDGET=24000
OCTOPUS_CODEX_LARGE_CONTEXT_BUDGET=77777
if [[ "$(get_provider_context_limit 'codex-large-context:gpt-5')" == 77777 ]]; then
  test_pass
else
  test_fail "qualified codex-large-context lost its special budget"
fi

test_case "Council provider status canonicalizes model-qualified provider keys"
COUNCIL_PROVIDERS='commandcode:stealth/ox-alpha'
OCTOPUS_COUNCIL_PROVIDER_FIXTURE='commandcode:stealth/ox-alpha:available'
council_detect_providers
if [[ "$(jq -r '.commandcode // "missing"' <<< "$COUNCIL_PROVIDER_STATUS_JSON")" == available ]] && \
   [[ "$(jq -r 'has("commandcode:stealth/ox-alpha")' <<< "$COUNCIL_PROVIDER_STATUS_JSON")" == false ]] && \
   council_provider_is_available 'commandcode:stealth/ox-alpha'; then
  test_pass
else
  test_fail "provider status map was not canonicalized: $COUNCIL_PROVIDER_STATUS_JSON"
fi
unset OCTOPUS_COUNCIL_PROVIDER_FIXTURE

test_summary
