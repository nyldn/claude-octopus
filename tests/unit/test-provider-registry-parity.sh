#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT/scripts/lib/provider-registry.sh"
source "$PROJECT_ROOT/scripts/lib/provider-allowlist.sh"
source "$PROJECT_ROOT/scripts/lib/council.sh"

test_suite "Provider registry parity and collision safety"

all_ids=$(octo_provider_ids)

test_case "every canonical provider round-trips exactly"
for id in $all_ids; do
    [[ "$(octo_provider_canonical "$id")" == "$id" ]] || { test_fail "$id canonicalized incorrectly"; exit 0; }
done
test_pass

test_case "every alias resolves to its declared provider without collisions"
while IFS='|' read -r id aliases command org caps; do
    old_ifs="$IFS"; IFS=','
    for alias in $aliases; do
        IFS="$old_ifs"
        [[ -n "$alias" ]] || { IFS=','; continue; }
        probe="$alias"
        case "$alias" in *'*') probe="${alias%\*}probe" ;; esac
        actual=$(octo_provider_canonical "$probe" || true)
        [[ "$actual" == "$id" ]] || { test_fail "alias $probe expected $id, got $actual"; exit 0; }
        IFS=','
    done
    IFS="$old_ifs"
done <<EOF
$(octo_provider_registry_rows)
EOF
test_pass

test_case "registry exports configured provider identity for every executor alias"
if declare -f octo_provider_identity_from_agent_type >/dev/null 2>&1 &&
   [[ "$(octo_provider_identity_from_agent_type codex-review)" == "codex" ]] &&
   [[ "$(octo_provider_identity_from_agent_type claude-sonnet)" == "anthropic" ]] &&
   [[ "$(octo_provider_identity_from_agent_type agy-research)" == "google" ]] &&
   [[ "$(octo_provider_identity_from_agent_type qwen-review)" == "qwen" ]] &&
   [[ "$(octo_provider_identity_from_agent_type not-registered)" == "unknown" ]]; then
    test_pass
else
    test_fail "configured provider identity is not registry-owned or complete"
fi

test_case "all providers expose command organization and capabilities metadata"
for id in $all_ids; do
    [[ -n "$(octo_provider_command "$id")" ]] || { test_fail "$id missing command"; exit 0; }
    [[ -n "$(octo_provider_org "$id")" ]] || { test_fail "$id missing organization"; exit 0; }
    [[ -n "$(octo_provider_field "$id" capabilities)" ]] || { test_fail "$id missing capabilities"; exit 0; }
done
test_pass

test_case "runtime metadata inventory exactly matches canonical provider inventory"
if declare -f octo_provider_runtime_ids >/dev/null 2>&1 &&
   [[ "$(octo_provider_runtime_ids | tr ' ' '\n' | LC_ALL=C sort)" == "$(printf '%s\n' "$all_ids" | tr ' ' '\n' | LC_ALL=C sort)" ]]; then
    test_pass
else
    test_fail "runtime metadata inventory is missing or differs from canonical IDs"
fi

test_case "every provider has complete and valid runtime metadata"
runtime_ok=true
if ! declare -f octo_provider_runtime_field >/dev/null 2>&1; then
    runtime_ok=false
    test_fail "runtime metadata API is missing"
else
    for id in $all_ids; do
        auth=$(octo_provider_auth_mode "$id" 2>/dev/null || true)
        health=$(octo_provider_health_handler "$id" 2>/dev/null || true)
        detect=$(octo_provider_detect_handler "$id" 2>/dev/null || true)
        model_env=$(octo_provider_model_env "$id" 2>/dev/null || true)
        resolver=$(octo_provider_default_model_resolver "$id" 2>/dev/null || true)
        context=$(octo_provider_context_tokens "$id" 2>/dev/null || true)
        cost=$(octo_provider_cost_class "$id" 2>/dev/null || true)
        sandbox=$(octo_provider_sandbox_class "$id" 2>/dev/null || true)
        independence=$(octo_provider_independence_org "$id" 2>/dev/null || true)
        case "$auth" in api-key|cli-session|api-key-or-cli-session|local-runtime|provider-config) ;; *) test_fail "$id has invalid auth mode '$auth'"; runtime_ok=false; break ;; esac
        case "$health" in check_provider_health|none) ;; *) test_fail "$id has invalid health handler '$health'"; runtime_ok=false; break ;; esac
        case "$detect" in detect_providers|none) ;; *) test_fail "$id has invalid detect handler '$detect'"; runtime_ok=false; break ;; esac
        [[ "$model_env" =~ ^[A-Z][A-Z0-9_]*$ ]] || { test_fail "$id has invalid model env '$model_env'"; runtime_ok=false; break; }
        [[ "$resolver" == "resolve_octopus_model" ]] || { test_fail "$id has invalid model resolver '$resolver'"; runtime_ok=false; break; }
        [[ "$context" =~ ^[0-9]+$ ]] && [[ "$context" -gt 0 ]] || { test_fail "$id has invalid context ceiling '$context'"; runtime_ok=false; break; }
        case "$cost" in bundled|metered|local|variable) ;; *) test_fail "$id has invalid cost class '$cost'"; runtime_ok=false; break ;; esac
        case "$sandbox" in host-managed|plugin-isolated|provider-managed|local-runtime) ;; *) test_fail "$id has invalid sandbox class '$sandbox'"; runtime_ok=false; break ;; esac
        [[ -n "$independence" ]] || { test_fail "$id missing independence organization"; runtime_ok=false; break; }
    done
fi
[[ "$runtime_ok" == true ]] && test_pass

test_case "aliases share the canonical provider runtime contract"
alias_runtime_ok=true
if ! declare -f octo_provider_runtime_field >/dev/null 2>&1; then
    alias_runtime_ok=false
    test_fail "runtime metadata API is missing"
else
    while IFS='|' read -r id aliases command org caps; do
        old_ifs="$IFS"; IFS=','
        for alias in $aliases; do
            IFS="$old_ifs"
            [[ -n "$alias" ]] || { IFS=','; continue; }
            probe="$alias"; case "$alias" in *'*') probe="${alias%\*}probe" ;; esac
            if [[ "$(octo_provider_runtime_field "$probe" model_env)" != "$(octo_provider_runtime_field "$id" model_env)" ]] ||
               [[ "$(octo_provider_runtime_field "$probe" independence_org)" != "$(octo_provider_runtime_field "$id" independence_org)" ]]; then
                test_fail "alias $probe does not share $id runtime metadata"
                alias_runtime_ok=false
                break 2
            fi
            IFS=','
        done
        IFS="$old_ifs"
    done <<EOF
$(octo_provider_registry_rows)
EOF
fi
[[ "$alias_runtime_ok" == true ]] && test_pass

test_case "shared context routing consumes registry metadata"
if grep -A35 '^get_provider_context_limit() {' "$PROJECT_ROOT/scripts/lib/dispatch.sh" | grep -c 'octo_provider_context_tokens' >/dev/null; then
    test_pass
else
    test_fail "dispatch context routing still owns a parallel provider list"
fi

test_case "sync health selection and model env resolution consume registry metadata"
health_body=$(sed -n '/# v8.49.0: Pre-dispatch health check/,/run_contract_transition .*authenticated/p' "$PROJECT_ROOT/scripts/lib/agent-sync.sh")
if grep -q 'octo_provider_health_handler' <<< "$health_body" &&
   ! grep -Eq 'codex\*\).*_provider_for_health|claude\*\).*_provider_for_health' <<< "$health_body" &&
   grep -q 'octo_provider_model_env' "$PROJECT_ROOT/scripts/lib/model-resolver.sh"; then
    test_pass
else
    test_fail "shared dispatch/model consumers still own parallel provider identity metadata"
fi

test_case "dispatch identity cost policy and Council independence consume registry metadata"
model_body=$(sed -n '/^get_agent_model() {/,/^}/p' "$PROJECT_ROOT/scripts/lib/dispatch.sh")
cost_body=$(sed -n '/^is_api_based_provider() {/,/^}/p' "$PROJECT_ROOT/scripts/lib/provider-routing.sh")
council_org_body=$(sed -n '/^council_provider_org() {/,/^}/p' "$PROJECT_ROOT/scripts/lib/council.sh")
if grep -q 'octo_provider_canonical' <<< "$model_body" &&
   ! grep -Eq 'codex\*\).*provider=|claude\*\).*provider=' <<< "$model_body" &&
   grep -q 'octo_provider_cost_class' <<< "$cost_body" &&
   grep -q 'octo_provider_independence_org' <<< "$council_org_body"; then
    test_pass
else
    test_fail "shared consumers still own provider identity, cost, or independence metadata"
fi

test_case "model-config consumers exactly match registry capability"
source "$PROJECT_ROOT/scripts/lib/provider-routing.sh"
expected=$(octo_provider_ids model-config)
[[ "$OCTO_MODEL_CONFIG_PROVIDERS" == "$expected" ]] || { test_fail "provider-routing model list drift"; exit 0; }
registry_home="$(mktemp -d)"
original_home="$HOME"
HOME="$registry_home"
source "$PROJECT_ROOT/scripts/helpers/octo-model-config.sh"
HOME="$original_home"
rm -rf "$registry_home"
[[ "$KNOWN_PROVIDERS" == "$expected" ]] || { test_fail "model-config helper list drift"; exit 0; }
test_pass

test_case "Council accepts every council-capable provider and rejects the rest"
failed=false
for id in $all_ids; do
    if octo_provider_has_capability "$id" council; then
        council_validate_provider_list "$id" >/dev/null 2>&1 || { test_fail "Council rejected $id"; exit 0; }
    else
        if council_validate_provider_list "$id" >/dev/null 2>&1; then test_fail "Council accepted unsupported $id"; failed=true; break; fi
    fi
done
[[ "$failed" == true ]] || test_pass

test_case "allowlist accepts every provider ID and declared alias"
had_allowlist=false; previous_allowlist=""; failed=false
if [[ ${OCTO_ALLOWED_PROVIDERS+x} ]]; then had_allowlist=true; previous_allowlist="$OCTO_ALLOWED_PROVIDERS"; fi
for id in $all_ids; do
    OCTO_ALLOWED_PROVIDERS="$id"
    if ! octo_provider_allowed "$id"; then test_fail "allowlist rejected $id"; failed=true; break; fi
done
if [[ "$failed" == false ]]; then
    while IFS='|' read -r id aliases command org caps; do
        old_ifs="$IFS"; IFS=','
        for alias in $aliases; do
            IFS="$old_ifs"; [[ -n "$alias" ]] || { IFS=','; continue; }
            probe="$alias"; case "$alias" in *'*') probe="${alias%\*}probe" ;; esac
            OCTO_ALLOWED_PROVIDERS="$probe"
            if ! octo_provider_allowed "$id"; then test_fail "allowlist alias $probe rejected canonical $id"; failed=true; break 2; fi
            IFS=','
        done
        IFS="$old_ifs"
    done <<EOF
$(octo_provider_registry_rows)
EOF
fi
if [[ "$had_allowlist" == true ]]; then OCTO_ALLOWED_PROVIDERS="$previous_allowlist"; else unset OCTO_ALLOWED_PROVIDERS; fi
[[ "$failed" == true ]] || test_pass

test_case "compound provider IDs are not truncated by router or bridge"
if grep -q 'split("-")\[0\]' "$PROJECT_ROOT/scripts/provider-router.sh" "$PROJECT_ROOT/scripts/agent-teams-bridge.sh" || \
   grep -q '\${candidate%%-\*}' "$PROJECT_ROOT/scripts/provider-router.sh"; then
    test_fail "unsafe first-hyphen provider parsing remains"
else
    test_pass
fi

test_case "Council default policy is configurable without changing registry support"
defaults=$(bash -c 'source "'$PROJECT_ROOT'/scripts/lib/council.sh"; printf "%s" "$COUNCIL_DEFAULT_PROVIDERS"')
override=$(env "OCTOPUS_COUNCIL_DEFAULT_PROVIDERS=commandcode,claude" bash -c 'source "'$PROJECT_ROOT'/scripts/lib/council.sh"; printf "%s" "$COUNCIL_DEFAULT_PROVIDERS"')
if [[ "$defaults" == "claude,codex,agy,qwen,opencode,openrouter,openai-compatible,openai-tools" && "$override" == "commandcode,claude" ]]; then
    test_pass
else
    test_fail "Council default/override mismatch"
fi


test_case "shared provider policy removes duplicated ordered defaults"
source "$PROJECT_ROOT/scripts/lib/provider-policy.sh"
if grep -q 'octo_council_default_providers' "$PROJECT_ROOT/scripts/lib/council.sh" && \
   grep -q 'octo_council_default_providers' "$PROJECT_ROOT/scripts/lib/usage-help.sh" && \
   grep -q 'octo_smoke_routing_providers' "$PROJECT_ROOT/scripts/lib/smoke.sh"; then
    for id in $(printf '%s' "$OCTOPUS_COUNCIL_DEFAULT_PROVIDERS_DEFAULT" | tr ',' ' ') $OCTOPUS_SMOKE_ROUTING_PROVIDERS_DEFAULT; do
        octo_provider_valid "$id" || { test_fail "policy references unknown provider $id"; exit 0; }
    done
    test_pass
else
    test_fail "provider policy still duplicated or hardcoded"
fi

test_summary
