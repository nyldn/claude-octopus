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

test_case "Council support derives from registry while default policy is preserved"
source "$PROJECT_ROOT/scripts/lib/council.sh"
if [[ "$COUNCIL_DEFAULT_PROVIDERS" == "claude,codex,agy,qwen,opencode,openrouter,openai-compatible,openai-tools" ]] && council_validate_provider_list commandcode; then
    test_pass
else
    test_fail "Council provider support or default policy drift"
fi

test_case "Council default provider policy is configurable"
overridden=$(env "OCTOPUS_COUNCIL_DEFAULT_PROVIDERS=commandcode,claude" bash -c 'source "'$PROJECT_ROOT'/scripts/lib/council.sh"; printf "%s" "$COUNCIL_DEFAULT_PROVIDERS"')
if [[ "$overridden" == "commandcode,claude" ]]; then test_pass; else test_fail "Council default override ignored: $overridden"; fi

test_case "Council command and organization use registry"
if [[ "$(council_provider_command commandcode)" == "command-code" ]] && [[ "$(council_provider_org commandcode)" == "commandcode" ]]; then test_pass; else test_fail "Council metadata drift"; fi

test_summary
