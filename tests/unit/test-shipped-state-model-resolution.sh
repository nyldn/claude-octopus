#!/bin/bash
# tests/unit/test-shipped-state-model-resolution.sh
# Regression coverage for #797: in the shipped no-config state (fresh HOME,
# no ~/.claude-octopus/config/providers.json), several providers fell through
# the Tier-7 hardcoded-default case in model-resolver.sh to codex_default_model
# ("gpt-5.6-sol") because they had no explicit case arm. That handed an OpenAI
# model ID to non-OpenAI CLIs (grok-exec.sh --model gpt-5.6-sol against the xAI
# CLI, an unnamespaced ID to OpenRouter) with no error — just wrong output.
#
# tests/unit/test-grok-provider.sh did not catch this because it always seeds
# a providers.json before resolving, so it never exercises the no-config path
# every fresh install actually starts from.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Shipped no-config state: model resolution"

# Stub log() — model-resolver.sh calls it outside orchestrate.sh.
log() { :; }

_resolve_in_empty_home() {
    local provider="$1" agent_type="$2"
    local empty_home="$TEST_TMP_DIR/empty-home-$$-$RANDOM"
    local provider_model_env
    mkdir -p "$empty_home"
    provider_model_env="OCTOPUS_$(printf '%s' "$provider" | tr '[:lower:]' '[:upper:]' | tr '-' '_')_MODEL"
    (
        HOME="$empty_home"
        unset "$provider_model_env"
        resolve_octopus_model "$provider" "$agent_type" "" ""
    )
}

source "$PROJECT_ROOT/scripts/lib/provider-registry.sh"
source "$PROJECT_ROOT/scripts/lib/utils.sh"
source "$PROJECT_ROOT/scripts/lib/model-resolver.sh"
source "$PROJECT_ROOT/scripts/lib/provider-routing.sh"
source "$PROJECT_ROOT/scripts/lib/dispatch.sh"

_get_agent_model_in_empty_home() {
    local empty_home="$TEST_TMP_DIR/empty-agent-home-$$-$RANDOM"
    mkdir -p "$empty_home"
    (
        HOME="$empty_home"
        unset OCTOPUS_GROK_MODEL
        _PROVIDER_CONFIG_MIGRATED=false
        get_agent_model grok probe researcher
    )
}

test_grok_no_config() {
    test_case "grok resolves to its own default, not an OpenAI model, with no config"
    local resolved
    resolved="$(_resolve_in_empty_home grok grok)"
    if [[ "$resolved" == "default" ]]; then
        test_pass
    else
        test_fail "expected grok to resolve to 'default' (xAI's own default), got: '$resolved'"
    fi
}

test_grok_dispatch_resolution_no_config() {
    test_case "get_agent_model keeps grok off the OpenAI model family with no config"
    local resolved
    resolved="$(_get_agent_model_in_empty_home)"
    if [[ "$resolved" == "default" && "$resolved" != gpt-* ]]; then
        test_pass
    else
        test_fail "expected grok's own default, got: '$resolved'"
    fi
}

test_bare_openrouter_no_config() {
    test_case "bare openrouter resolves to a namespaced OpenRouter ID with no config"
    local resolved
    resolved="$(_resolve_in_empty_home openrouter openrouter)"
    if [[ "$resolved" == "anthropic/claude-sonnet-4" ]]; then
        test_pass
    else
        test_fail "expected anthropic/claude-sonnet-4, got: '$resolved'"
    fi
}

test_bare_orcarouter_no_config() {
    test_case "bare orcarouter resolves to a namespaced OrcaRouter ID with no config"
    local resolved
    resolved="$(_resolve_in_empty_home orcarouter orcarouter)"
    if [[ "$resolved" == "anthropic/claude-sonnet-4.6" ]]; then
        test_pass
    else
        test_fail "expected anthropic/claude-sonnet-4.6, got: '$resolved'"
    fi
}

test_vibe_no_config() {
    test_case "vibe resolves to its own default (config lives in ~/.vibe/config.toml), not an OpenAI model"
    local resolved
    resolved="$(_resolve_in_empty_home vibe vibe)"
    if [[ "$resolved" == "default" ]]; then
        test_pass
    else
        test_fail "expected vibe to resolve to 'default', got: '$resolved'"
    fi
}

test_atlascloud_no_config_fails_closed() {
    test_case "atlascloud fails closed with no config instead of guessing an OpenAI model"
    local rc out
    rc=0
    out="$(_resolve_in_empty_home atlascloud atlascloud 2>/dev/null)" || rc=$?
    if [[ "$rc" -ne 0 && "$out" != "$(codex_default_model)" ]]; then
        test_pass
    else
        test_fail "expected atlascloud resolution to fail closed with no config, got rc=$rc out='$out'"
    fi
}

test_registry_providers_do_not_inherit_codex_default() {
    test_case "registry providers outside OpenAI never silently inherit codex's default model"
    local provider organization resolved bad=""
    for provider in $(octo_provider_ids model-config); do
        organization="$(octo_provider_org "$provider")"
        [[ "$organization" == "openai" ]] && continue
        resolved="$(_resolve_in_empty_home "$provider" "$provider" 2>/dev/null)" || continue
        [[ "$resolved" == "$(codex_default_model)" ]] && bad="$bad $provider($organization)"
    done
    if [[ -z "$bad" ]]; then
        test_pass
    else
        test_fail "these providers still inherit codex_default_model with no config:$bad"
    fi
}

test_grok_no_config
test_grok_dispatch_resolution_no_config
test_bare_openrouter_no_config
test_bare_orcarouter_no_config
test_vibe_no_config
test_atlascloud_no_config_fails_closed
test_registry_providers_do_not_inherit_codex_default

test_summary
