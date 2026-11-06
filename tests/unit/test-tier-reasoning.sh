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
edit_config '.tiers.budget.codex = {reasoning:"low"}'
test_case "missing capability fails closed"
if resolve_octopus_model codex codex >/dev/null 2>&1; then test_fail "missing capability admitted"; else test_pass; fi
test_summary
