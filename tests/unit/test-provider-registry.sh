#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT/scripts/lib/provider-registry.sh"

test_suite "Canonical provider registry"

test_case "commandcode is a canonical provider"
if [[ "$(octo_provider_canonical commandcode-research)" == "commandcode" ]]; then test_pass; else test_fail "commandcode alias not canonicalized"; fi

test_case "commandcode exposes CLI and organization metadata"
if [[ "$(octo_provider_command commandcode)" == "command-code" ]] && [[ "$(octo_provider_org commandcode)" == "commandcode" ]]; then test_pass; else test_fail "commandcode metadata missing"; fi

test_case "Provider Registry 2.0 exposes every runtime metadata accessor"
runtime_accessors="octo_provider_auth_mode octo_provider_health_handler octo_provider_detect_handler octo_provider_model_env octo_provider_default_model_resolver octo_provider_context_tokens octo_provider_cost_class octo_provider_sandbox_class octo_provider_independence_org"
missing_accessor=""
for accessor in $runtime_accessors; do
    if ! declare -f "$accessor" >/dev/null 2>&1; then
        missing_accessor="$accessor"
        break
    fi
done
if [[ -z "$missing_accessor" ]]; then test_pass; else test_fail "missing runtime accessor: $missing_accessor"; fi

test_case "commandcode runtime contract is explicit and stable"
if declare -f octo_provider_runtime_field >/dev/null 2>&1 &&
   [[ "$(octo_provider_auth_mode command-code-probe)" == "api-key-or-cli-session" ]] &&
   [[ "$(octo_provider_health_handler commandcode)" == "check_provider_health" ]] &&
   [[ "$(octo_provider_detect_handler commandcode)" == "detect_providers" ]] &&
   [[ "$(octo_provider_model_env commandcode)" == "OCTOPUS_COMMANDCODE_MODEL" ]] &&
   [[ "$(octo_provider_default_model_resolver commandcode)" == "resolve_octopus_model" ]] &&
   [[ "$(octo_provider_context_tokens commandcode)" == "12000" ]] &&
   [[ "$(octo_provider_cost_class commandcode)" == "variable" ]] &&
   [[ "$(octo_provider_sandbox_class commandcode)" == "provider-managed" ]] &&
   [[ "$(octo_provider_independence_org commandcode)" == "commandcode" ]]; then
    test_pass
else
    test_fail "commandcode runtime contract missing or drifted"
fi

test_case "commandcode declares all core capabilities"
failed=false
for cap in model-config council health detect dispatch env; do
    if ! octo_provider_has_capability commandcode "$cap"; then test_fail "missing capability $cap"; failed=true; break; fi
done
[[ "$failed" == true ]] || test_pass

test_case "registry remains Bash 3.2 compatible"
if grep -qE 'declare[[:space:]]+-A|\$\{[^}]*,,[^}]*\}' "$PROJECT_ROOT/scripts/lib/provider-registry.sh"; then test_fail "non-portable construct found"; else test_pass; fi

test_case "model-config provider list derives from registry"
source "$PROJECT_ROOT/scripts/lib/provider-routing.sh"
if [[ " $OCTO_MODEL_CONFIG_PROVIDERS " == *" commandcode "* ]] && [[ "$OCTO_MODEL_CONFIG_PROVIDERS" == "$(octo_provider_ids model-config)" ]]; then test_pass; else test_fail "model config list drift"; fi

test_case "registry context defaults and provider overrides drive dispatch"
default_context=$(env -u OCTOPUS_CONTEXT_BUDGET -u OCTOPUS_COMMANDCODE_CONTEXT_BUDGET \
    bash -c 'source "$1/scripts/lib/dispatch.sh"; get_provider_context_limit commandcode-review' _ "$PROJECT_ROOT")
override_context=$(env -u OCTOPUS_CONTEXT_BUDGET "OCTOPUS_COMMANDCODE_CONTEXT_BUDGET=54321" \
    bash -c 'source "$1/scripts/lib/dispatch.sh"; get_provider_context_limit commandcode-review' _ "$PROJECT_ROOT")
sdk_context=$(env -u OCTOPUS_CONTEXT_BUDGET -u OCTOPUS_CLAUDE_SDK_CONTEXT_BUDGET \
    bash -c 'source "$1/scripts/lib/dispatch.sh"; get_provider_context_limit claude-sdk-review' _ "$PROJECT_ROOT")
if [[ "$default_context" == "12000" && "$override_context" == "54321" && "$sdk_context" == "1000000" ]]; then
    test_pass
else
    test_fail "unexpected context routing: default=$default_context override=$override_context sdk=$sdk_context"
fi

test_case "smoke source order preserves Claude context override"
source_order_context=$(env -u OCTOPUS_CONTEXT_BUDGET "OCTOPUS_CLAUDE_CONTEXT_BUDGET=200000" \
    bash -c '
        source "$1/scripts/lib/dispatch.sh"
        source "$1/scripts/lib/smoke.sh"
        get_provider_context_limit claude-opus
    ' _ "$PROJECT_ROOT")
if [[ "$source_order_context" == "200000" ]]; then
    test_pass
else
    test_fail "smoke source order changed Claude context override: $source_order_context"
fi

test_case "registry cost classes preserve dynamic authentication billing"
bundled_costs=$(env -u OPENAI_API_KEY -u COMMAND_CODE_API_KEY -u QWEN_API_KEY -u OPENAI_BASE_URL bash -c '
    source "$1/scripts/lib/provider-routing.sh"
    for provider in codex commandcode claude ollama qwen; do
        if is_api_based_provider "$provider"; then printf "%s:metered " "$provider"; else printf "%s:included " "$provider"; fi
    done
' _ "$PROJECT_ROOT")
metered_costs=$(env "OPENAI_API_KEY=test" "COMMAND_CODE_API_KEY=test" "QWEN_API_KEY=test" bash -c '
    source "$1/scripts/lib/provider-routing.sh"
    for provider in codex commandcode openrouter qwen; do
        if is_api_based_provider "$provider"; then printf "%s:metered " "$provider"; else printf "%s:included " "$provider"; fi
    done
' _ "$PROJECT_ROOT")
oauth_qwen_cost=$(env -u QWEN_API_KEY -u OPENAI_API_KEY -u OPENAI_BASE_URL bash -c '
    source "$1/scripts/lib/provider-routing.sh"
    qwen_auth_method() { printf "%s\n" oauth; }
    if is_api_based_provider qwen; then printf "%s" metered; else printf "%s" included; fi
' _ "$PROJECT_ROOT")
if [[ "$bundled_costs" == "codex:included commandcode:included claude:included ollama:included qwen:metered " ]] &&
   [[ "$metered_costs" == "codex:metered commandcode:metered openrouter:metered qwen:metered " ]] &&
   [[ "$oauth_qwen_cost" == "included" ]]; then
    test_pass
else
    test_fail "unexpected cost classification: bundled='$bundled_costs' metered='$metered_costs' oauth-qwen='$oauth_qwen_cost'"
fi

test_case "Council support derives from registry while default policy is preserved"
source "$PROJECT_ROOT/scripts/lib/council.sh"
if [[ "$COUNCIL_DEFAULT_PROVIDERS" == "claude,codex,agy,qwen,opencode,openrouter,openai-compatible,openai-tools" ]] && council_validate_provider_list commandcode; then
    test_pass
else
    test_fail "Council provider support or default policy drift"
fi

test_case "Council default provider policy is configurable"
overridden=$(env "OCTOPUS_COUNCIL_DEFAULT_PROVIDERS=commandcode,claude" \
    bash -c 'source "$1/scripts/lib/council.sh"; printf "%s" "$COUNCIL_DEFAULT_PROVIDERS"' _ "$PROJECT_ROOT")
if [[ "$overridden" == "commandcode,claude" ]]; then test_pass; else test_fail "Council default override ignored: $overridden"; fi

test_case "Council command and organization use registry"
if [[ "$(council_provider_command commandcode)" == "command-code" ]] && [[ "$(council_provider_org commandcode)" == "commandcode" ]]; then test_pass; else test_fail "Council metadata drift"; fi

test_summary
