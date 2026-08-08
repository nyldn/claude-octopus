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
    mkdir -p "$empty_home"
    local old_home="$HOME"
    HOME="$empty_home"
    local out=""
    out="$(resolve_octopus_model "$provider" "$agent_type" "" "" 2>/dev/null)" || true
    HOME="$old_home"
    printf '%s' "$out"
}

source "$PROJECT_ROOT/scripts/lib/model-resolver.sh" 2>/dev/null || true

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

test_bare_openrouter_no_config() {
    test_case "bare openrouter resolves to a namespaced OpenRouter ID with no config"
    local resolved
    resolved="$(_resolve_in_empty_home openrouter openrouter)"
    if [[ "$resolved" == */* && "$resolved" != "gpt-5.6-sol" ]]; then
        test_pass
    else
        test_fail "expected a namespaced OpenRouter model ID (vendor/model), got: '$resolved'"
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
    local empty_home rc out
    empty_home="$TEST_TMP_DIR/empty-home-atlascloud-$$"
    mkdir -p "$empty_home"
    local old_home="$HOME"
    HOME="$empty_home"
    rc=0
    out="$(resolve_octopus_model atlascloud atlascloud "" "" 2>/dev/null)" || rc=$?
    HOME="$old_home"
    if [[ "$rc" -ne 0 && "$out" != "gpt-5.6-sol" ]]; then
        test_pass
    else
        test_fail "expected atlascloud resolution to fail closed with no config, got rc=$rc out='$out'"
    fi
}

test_no_provider_silently_inherits_codex_default() {
    test_case "grok/openrouter/vibe/atlascloud never silently resolve to codex's default model"
    local p resolved bad=""
    for p in "grok grok" "openrouter openrouter" "vibe vibe"; do
        resolved="$(_resolve_in_empty_home $p)"
        [[ "$resolved" == "gpt-5.6-sol" ]] && bad="$bad $p"
    done
    if [[ -z "$bad" ]]; then
        test_pass
    else
        test_fail "these providers still inherit codex_default_model with no config:$bad"
    fi
}

test_grok_no_config
test_bare_openrouter_no_config
test_vibe_no_config
test_atlascloud_no_config_fails_closed
test_no_provider_silently_inherits_codex_default

test_summary
