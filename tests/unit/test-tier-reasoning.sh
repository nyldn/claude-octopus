#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/helpers/test-framework.sh"
test_suite "Cost tier reasoning profiles"
export PLUGIN_DIR="${TIER_LIB_ROOT:-$ROOT}" OCTOPUS_MODEL_READ_ONLY=true
export OCTOPUS_PROVIDERS_CONFIG="$TEST_TMP_DIR/providers.json"
export OCTOPUS_SKIP_PROVIDER_PROBES=1
export _BARE_OPT=""
export SUPPORTS_EFFORT_COMMAND=true SUPPORTS_EFFORT_CLI_FLAG=true
unset OCTOPUS_CODEX_MODEL CLAUDE_MODEL OCTOPUS_CLAUDE_MODEL OCTOPUS_REASONING_LEVEL OCTOPUS_CODEX_REASONING OCTOPUS_COST_MODE
log() { :; }
source "$PLUGIN_DIR/scripts/lib/model-resolver.sh"
source "$PLUGIN_DIR/scripts/lib/dispatch.sh"
_octopus_require_codex_model_version() { return 0; }
configure() {
    cat > "$OCTOPUS_PROVIDERS_CONFIG" <<'JSON'
{"cost_mode":"budget","providers":{"codex":{"default":"gpt-5.6-sol","mini":"gpt-5.6-luna","reasoning_effort":"high"},"claude":{"default":"claude-sonnet-5","budget":"claude-haiku-4.5","reasoning_effort":"high"}},"tiers":{"budget":{"codex":{"capability":"mini","reasoning":"low"},"claude":{"capability":"budget","reasoning":"medium"}},"standard":{"codex":"default"}}}
JSON
}
edit_config() {
    jq "$1" "$OCTOPUS_PROVIDERS_CONFIG" > "$TEST_TMP_DIR/edited.json"
    mv "$TEST_TMP_DIR/edited.json" "$OCTOPUS_PROVIDERS_CONFIG"
}
expect() {
    test_case "$1"
    if [[ "$2" == "$3" ]]; then test_pass
    else test_fail "expected [$3], got [$2]"; fi
}
configure
expect "object tier resolves its capability" "$(resolve_octopus_model codex codex)" gpt-5.6-luna
expect "object tier effort overrides provider default" "$(octopus_resolve_reasoning_level codex)" low
expect "Claude tier selects a budget model" "$(resolve_octopus_model claude claude)" claude-haiku-4.5
expect "Claude tier selects its effort" "$(octopus_resolve_reasoning_level claude)" medium
command_line="$(get_agent_command codex develop implementer)" || command_line=dispatch-failed
expect "Codex dispatch carries the tier effort" "$([[ "$command_line" == *'model_reasoning_effort="low"'* && "$command_line" == *'--model gpt-5.6-luna'* ]] && echo yes || echo no)" yes
command_line="$(get_agent_command claude develop implementer)" || command_line=dispatch-failed
expect "Claude dispatch carries the tier effort" "$([[ "$command_line" == *'--effort medium'* && "$command_line" == *'--model claude-haiku-4-5'* ]] && echo yes || echo no)" yes
expect "environment effort wins" "$(OCTOPUS_CODEX_REASONING=medium octopus_resolve_reasoning_level codex)" medium
expect "environment model bypasses tier effort" "$(OCTOPUS_CODEX_MODEL=gpt-5.6-sol octopus_resolve_reasoning_level codex)" high
expect "exact model seat bypasses tier effort" "$(octopus_resolve_reasoning_level codex '' '' codex:gpt-5.6-sol)" high
expect "capability seat bypasses tier effort" "$(octopus_resolve_reasoning_level codex '' '' codex-mini)" high
edit_config '.routing.phases.develop = {provider:"codex",model:"gpt-5.6-sol",reasoning:"medium"}'
expect "phase effort wins" "$(octopus_resolve_reasoning_level codex develop)" medium
edit_config 'del(.routing.phases.develop.reasoning)'
expect "phase model does not inherit tier effort" "$(octopus_resolve_reasoning_level codex develop)" high
edit_config 'del(.routing) | .overrides.codex = "gpt-5.6-sol"'
expect "session model does not inherit tier effort" "$(octopus_resolve_reasoning_level codex)" high
configure
expect "environment cost mode keeps legacy strings" "$(OCTOPUS_COST_MODE=standard resolve_octopus_model codex codex)" gpt-5.6-sol
expect "legacy string effort uses provider default" "$(OCTOPUS_COST_MODE=standard octopus_resolve_reasoning_level codex)" high
edit_config 'del(.tiers.budget.codex.reasoning)'
expect "object without effort uses provider default" "$(octopus_resolve_reasoning_level codex)" high
configure
edit_config '.tiers.budget.codex.reasoning = "arbitrary"'
test_case "invalid effort fails closed"
if octopus_resolve_reasoning_level codex >/dev/null 2>&1; then test_fail "invalid effort admitted"; else test_pass; fi
for invalid_profile in '{capability:"mini",reasoning:7}' '{capability:"mini",reasoning:false}' '{capability:"mini",reasoning:null}' '{capability:"mini",reasoning:[]}' '{capability:"mini",reasoning:{}}' '{capability:""}' '{}'; do
    configure
    edit_config ".tiers.budget.codex = $invalid_profile"
    test_case "effort resolution rejects a malformed selected object tier: $invalid_profile"
    if octopus_resolve_reasoning_level codex >/dev/null 2>&1; then
        test_fail "malformed tier silently used provider effort"
    else
        test_pass
    fi
done
configure
edit_config '.tiers.budget.codex.reasoning = 7'
expect "an explicit model bypasses malformed tier effort" "$(OCTOPUS_CODEX_MODEL=gpt-5.6-sol octopus_resolve_reasoning_level codex)" high
expect "an explicit effort bypasses malformed tier effort" "$(OCTOPUS_CODEX_REASONING=medium octopus_resolve_reasoning_level codex)" medium
expect "a malformed inactive tier does not affect legacy strings" "$(OCTOPUS_COST_MODE=standard octopus_resolve_reasoning_level codex)" high
edit_config '.routing.phases.develop = {provider:"codex",model:"gpt-5.6-sol"}'
expect "an explicit phase model bypasses malformed tier effort" "$(octopus_resolve_reasoning_level codex develop)" high
configure
edit_config '.tiers.budget.codex.capability = "gpt-6-astra"'
expect "object tier preserves explicit-only restrictions" "$(resolve_octopus_model codex codex)" gpt-5.6-sol
expect "rejected tier cannot supply effort" "$(octopus_resolve_reasoning_level codex)" high
configure
resolve_octopus_model codex codex >/dev/null
expect "a model cache entry cannot hide tier effort" "$(octopus_resolve_reasoning_level codex)" low
edit_config '.tiers.budget.codex.reasoning = "auto"'
expect "explicit automatic effort does not inherit provider high" "$(octopus_resolve_reasoning_level codex)" ''
configure
expect "an allowlist fallback does not inherit tier effort" "$(OCTOPUS_CODEX_ALLOWED_MODELS=gpt-5.6-sol octopus_resolve_reasoning_level codex)" high
expect "a dispatched allowlist fallback does not inherit tier effort" "$(OCTOPUS_CODEX_ALLOWED_MODELS=gpt-5.6-sol octopus_resolve_reasoning_level codex '' '' codex gpt-5.6-sol)" high
command_line="$(OCTOPUS_CLAUDE_ALLOWED_MODELS=claude-sonnet-5 get_agent_command claude develop implementer)"
expect "Claude fallback uses provider effort instead of discarded tier effort" "$([[ "$command_line" == *'--model claude-sonnet-5'* && "$command_line" == *'--effort high'* ]] && echo yes || echo no)" yes
# Effort belongs to the final model after admission, including cache or gate replacements.
configure
for claude_seat in claude claude-sonnet; do
    command_line="$(
        get_agent_model() { echo claude-haiku-4.5; }
        _octopus_apply_nonexact_fable_input_gate() { echo claude-sonnet-5; }
        get_agent_command "$claude_seat" develop implementer
    )" || command_line=dispatch-failed
    expect "$claude_seat replacement uses provider effort instead of discarded tier effort" "$([[ "$command_line" == *'--model claude-sonnet-5'* && "$command_line" == *'--effort high'* ]] && echo yes || echo no)" yes
    command_line="$(
        get_agent_model() { echo claude-haiku-4.5; }
        _octopus_apply_nonexact_fable_input_gate() { echo claude-sonnet-5; }
        octopus_resolve_reasoning_level() { [[ "${5:-}" == claude-sonnet-5 ]] || return 1; echo high; }
        get_agent_command "$claude_seat" develop implementer
    )" || command_line=dispatch-failed
    expect "$claude_seat resolves effort after the model gate" "$([[ "$command_line" == *'--effort high'* ]] && echo yes || echo no)" yes
done
for invalid_tier in false true 7 '[]' '["default"]'; do
    configure
    edit_config ".providers.opencode = {default:\"opencode/default\"} | .tiers.budget.opencode = $invalid_tier"
    test_case "selected tier rejects non-string/non-object value: $invalid_tier"
    if resolve_octopus_model opencode opencode >/dev/null 2>&1; then test_fail "invalid tier admitted"; else test_pass; fi
done
for fallback_tier in null missing; do
    configure
    if [[ "$fallback_tier" == missing ]]; then edit_config 'del(.tiers.budget.codex)'
    else edit_config '.tiers.budget.codex = null'; fi
    expect "$fallback_tier tier preserves the provider default" "$(resolve_octopus_model codex codex)" gpt-5.6-sol
done
configure
edit_config '.tiers.budget.codex = {reasoning:"low"}'
test_case "missing capability fails closed"
if resolve_octopus_model codex codex >/dev/null 2>&1; then test_fail "missing capability admitted"; else test_pass; fi
configure
edit_config '.cost_mode = "premium" | .tiers.premium.codex = {capability:"default",reasoning:"low"} | .routing.frontier.codex = {model:"gpt-6-astra",mode:"bounded"}'
export OCTOPUS_MAX_COST_USD=10 OCTOPUS_DISPATCH_PREVIEW=true
octo_codex_installed_version() { echo 0.153.3; }
command_line="$(get_agent_command codex define architect 4000)"
expect "frontier replacement keeps provider effort instead of discarded tier effort" "$([[ "$command_line" == *'--model gpt-6-astra'* && "$command_line" == *'model_reasoning_effort="high"'* ]] && echo yes || echo no)" yes
command_line="$(OCTOPUS_CODEX_REASONING=medium get_agent_command codex define architect 4000)"
expect "frontier replacement still honors explicit effort" "$([[ "$command_line" == *'--model gpt-6-astra'* && "$command_line" == *'model_reasoning_effort="medium"'* ]] && echo yes || echo no)" yes
command_line="$(get_agent_command codex define implementer 4000)"
expect "a non-escalated tier retains its effort" "$([[ "$command_line" == *'--model gpt-5.6-sol'* && "$command_line" == *'model_reasoning_effort="low"'* ]] && echo yes || echo no)" yes
configure
export OPENAI_COMPAT_BASE_URL=https://example.invalid/v1 "OPENAI_API_KEY=test-only"
edit_config '.providers["openai-compatible-agent"] = {default:"shared-model",reasoning_effort:"high"} | .providers["openai-compatible"] = {default:"shared-model"} | .providers["openai-tools"] = {default:"shared-model"} | .tiers.budget["openai-compatible-agent"] = {capability:"default",reasoning:"low"}'
for compatible_seat in openai-compatible openai-tools; do
    command_line="$(get_agent_command "$compatible_seat" develop implementer)"
    expect "$compatible_seat cannot borrow another provider's tier effort" "$([[ "$command_line" == *'--model shared-model'* && "$command_line" == *'--reasoning-effort high'* ]] && echo yes || echo no)" yes
    command_line="$(OCTOPUS_OPENAI_COMPATIBLE_MODEL=shared-model OCTOPUS_OPENAI_TOOLS_MODEL=shared-model get_agent_command "$compatible_seat" develop implementer)"
    expect "$compatible_seat explicit pin cannot borrow same-model tier effort" "$([[ "$command_line" == *'--model shared-model'* && "$command_line" == *'--reasoning-effort high'* ]] && echo yes || echo no)" yes
done
edit_config '.tiers.budget["openai-compatible"] = {capability:"default",reasoning:"medium"} | .tiers.budget["openai-tools"] = {capability:"default",reasoning:"medium"}'
for compatible_seat in openai-compatible openai-tools openai-compatible-agent; do
    compatible_effort=medium
    [[ "$compatible_seat" != openai-compatible-agent ]] || compatible_effort=low
    command_line="$(get_agent_command "$compatible_seat" develop implementer)"
    expect "$compatible_seat uses its own tier effort" "$([[ "$command_line" == *"--reasoning-effort $compatible_effort"* ]] && echo yes || echo no)" yes
    command_line="$(OCTOPUS_OPENAI_COMPATIBLE_AGENT_REASONING=high get_agent_command "$compatible_seat" develop implementer)"
    expect "$compatible_seat preserves the existing explicit effort override" "$([[ "$command_line" == *'--reasoning-effort high'* ]] && echo yes || echo no)" yes
done
configure
edit_config '.tiers.standard.codex = {capability:"default",reasoning:"medium"} | .tiers.budget.codex.reasoning = 7'
expect "an active object tier ignores a malformed inactive tier" "$(OCTOPUS_COST_MODE=standard octopus_resolve_reasoning_level codex)" medium
for inactive_mode in '"invalid"' '[]' false 7 null; do
    configure
    edit_config ".tiers.unused = $inactive_mode"
    expect "inactive mode $inactive_mode cannot suppress active tier effort" "$(octopus_resolve_reasoning_level codex)" low
    command_line="$(get_agent_command codex develop implementer)" || command_line=dispatch-failed
    expect "dispatch preserves active effort beside inactive mode $inactive_mode" "$([[ "$command_line" == *'model_reasoning_effort="low"'* ]] && echo yes || echo no)" yes
done
configure
edit_config '.providers["anthropic-api"] = {default:"claude-sonnet-5-5",reasoning_effort:"high"} | .tiers.budget["anthropic-api"] = {capability:"default",reasoning:"auto"}'
command_line="$(get_agent_command anthropic-api probe researcher)" || command_line=dispatch-failed
expect "API tier automatic effort stays automatic at dispatch" "$([[ "$command_line" == *'--effort auto'* ]] && echo yes || echo no)" yes
command_line="$(OCTOPUS_ANTHROPIC_API_REASONING=medium get_agent_command anthropic-api probe researcher)" || command_line=dispatch-failed
expect "explicit API effort wins over automatic tier effort" "$([[ "$command_line" == *'--effort medium'* ]] && echo yes || echo no)" yes
edit_config 'del(.tiers.budget["anthropic-api"].reasoning)'
command_line="$(get_agent_command anthropic-api probe researcher)" || command_line=dispatch-failed
expect "API tier without effort keeps its configured provider effort" "$([[ "$command_line" == *'--effort high'* ]] && echo yes || echo no)" yes
edit_config 'del(.providers["anthropic-api"].reasoning_effort)'
command_line="$(get_agent_command anthropic-api probe researcher)" || command_line=dispatch-failed
expect "API seat without configured effort retains the high default" "$([[ "$command_line" == *'--effort high'* ]] && echo yes || echo no)" yes
edit_config '.tiers.budget["anthropic-api"] = {capability:"claude-opus-5-5",reasoning:"low"}'
command_line="$(get_agent_model() { echo claude-sonnet-5-5; }; get_agent_command anthropic-api probe researcher)" || command_line=dispatch-failed
expect "API replacement model cannot inherit the discarded tier effort" "$([[ "$command_line" == *'--model claude-sonnet-5-5'* && "$command_line" == *'--effort high'* ]] && echo yes || echo no)" yes
test_summary
