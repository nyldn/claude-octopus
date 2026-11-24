#!/usr/bin/env bash
# Tests for OpenCode hardcoded model defaults.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "OpenCode model defaults"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

MODEL_RESOLVER="$PROJECT_ROOT/scripts/lib/model-resolver.sh"
MODEL_CATALOG="$PROJECT_ROOT/scripts/lib/models.sh"
MODEL_CONFIG="$PROJECT_ROOT/scripts/helpers/octo-model-config.sh"

if bash -n "$MODEL_RESOLVER"; then
    pass "model resolver has valid bash syntax"
else
    fail "model resolver has valid bash syntax" "syntax error"
fi

if bash -n "$MODEL_CATALOG" "$MODEL_CONFIG"; then
    pass "model catalog scripts have valid bash syntax"
else
    fail "model catalog scripts have valid bash syntax" "syntax error"
fi

TEST_HOME="$TEST_TMP_DIR/home"
mkdir -p "$TEST_HOME"

source "$MODEL_RESOLVER"
source "$MODEL_CATALOG"

test_case "opencode default uses opencode namespace"
if [[ "$(HOME="$TEST_HOME" USER="octo-test-$$" CLAUDE_CODE_SESSION="opencode-default" resolve_octopus_model opencode opencode 2>/dev/null)" == "opencode/deepseek-v4.1-flash-free" ]]; then
    test_pass
else
    test_fail "expected opencode/deepseek-v4.1-flash-free"
fi

test_case "opencode-fast default uses opencode namespace"
if [[ "$(HOME="$TEST_HOME" USER="octo-test-$$" CLAUDE_CODE_SESSION="opencode-fast" resolve_octopus_model opencode opencode-fast 2>/dev/null)" == "opencode/deepseek-v4.1-flash-free" ]]; then
    test_pass
else
    test_fail "expected opencode/deepseek-v4.1-flash-free"
fi

test_case "opencode-research default uses opencode namespace"
if [[ "$(HOME="$TEST_HOME" USER="octo-test-$$" CLAUDE_CODE_SESSION="opencode-research" resolve_octopus_model opencode opencode-research 2>/dev/null)" == "opencode/glm-5.3" ]]; then
    test_pass
else
    test_fail "expected opencode/glm-5.3"
fi

test_case "model catalog includes current opencode namespace"
if is_known_model "opencode/deepseek-v4.1-flash-free" &&
   is_known_model "opencode/glm-5.3" &&
   [[ "$(get_model_capability "opencode/glm-5.3" provider)" == "opencode" ]]; then
    test_pass
else
    test_fail "expected opencode namespaced models in catalog"
fi

test_case "claude-opus default prefers Opus 5 when supported"
if [[ "$(HOME="$TEST_HOME" USER="octo-test-$$" CLAUDE_CODE_SESSION="opus5" SUPPORTS_OPUS_5=true SUPPORTS_OPUS_4_8=true SUPPORTS_OPUS_4_7=true resolve_octopus_model claude claude-opus 2>/dev/null)" == "claude-opus-5" ]]; then
    test_pass
else
    test_fail "expected claude-opus-5"
fi

test_case "claude-opus default falls back to Opus 4.8 before 4.7"
if [[ "$(HOME="$TEST_HOME" USER="octo-test-$$" CLAUDE_CODE_SESSION="opus48" SUPPORTS_OPUS_5=false SUPPORTS_OPUS_4_8=true SUPPORTS_OPUS_4_7=true resolve_octopus_model claude claude-opus 2>/dev/null)" == "claude-opus-4.8" ]]; then
    test_pass
else
    test_fail "expected claude-opus-4.8 fallback"
fi

test_case "model catalog includes Opus 5 and marks 4.7 legacy"
if is_known_model "claude-opus-5" &&
   [[ "$(get_model_capability "claude-opus-5" context_k)" == "1000" ]] &&
   [[ "$(get_model_capability "claude-opus-5" status)" == "active" ]] &&
   [[ "$(get_model_capability "claude-opus-4.7" status)" == "legacy" ]]; then
    test_pass
else
    test_fail "expected Opus 5 active catalog entry and Opus 4.7 legacy status"
fi

test_case "fresh model config adopts frontier defaults"
HOME="$TEST_HOME" USER="octo-test-$$" "$MODEL_CONFIG" list >/dev/null
fresh_config="$TEST_HOME/.claude-octopus/config/providers.json"
if jq -e '
    .providers.codex.default == "gpt-5.6-sol" and
    .providers.codex.fallback == "gpt-5.6-terra" and
    .providers.codex.mini == "gpt-5.6-luna" and
    .providers.claude.default == "claude-sonnet-5" and
    .providers.claude.opus == "claude-opus-5" and
    (.providers.claude | has("fable") | not) and
    .providers.opencode.default == "opencode/deepseek-v4.1-flash-free" and
    .providers.opencode.fast == "opencode/deepseek-v4.1-flash-free" and
    .providers.opencode.research == "opencode/glm-5.3"
' "$fresh_config" >/dev/null; then
    test_pass
else
    test_fail "fresh providers.json did not contain frontier defaults"
fi

test_case "existing model config pins are not silently migrated"
jq '.providers.codex.default = "gpt-5.5" | .providers.claude.default = "claude-sonnet-4.6" | .providers.opencode.default = "opencode/deepseek-v4-flash-free" | .providers.opencode.research = "opencode/glm-5.1"' \
    "$fresh_config" > "${fresh_config}.tmp" && mv "${fresh_config}.tmp" "$fresh_config"
HOME="$TEST_HOME" USER="octo-test-$$" "$MODEL_CONFIG" list >/dev/null
if jq -e '
    .providers.codex.default == "gpt-5.5" and
    .providers.claude.default == "claude-sonnet-4.6" and
    .providers.opencode.default == "opencode/deepseek-v4-flash-free" and
    .providers.opencode.research == "opencode/glm-5.1"
' "$fresh_config" >/dev/null; then
    test_pass
else
    test_fail "existing provider pins were changed"
fi

test_case "model config catalog does not expose stale opencode metadata"
catalog_output=$(HOME="$TEST_HOME" USER="octo-test-$$" CLAUDE_CODE_SESSION="opencode-catalog" "$MODEL_CONFIG" models opencode 2>/dev/null)
if assert_contains "$catalog_output" "opencode/deepseek-v4.1-flash-free" "opencode default should be listed" &&
   assert_contains "$catalog_output" "opencode/glm-5.3" "opencode research model should be listed" &&
   assert_not_contains "$catalog_output" "google/gemini-2.5-flash" "stale google model should not be listed as opencode" &&
   assert_not_contains "$catalog_output" "z-ai/glm-5.1" "stale openrouter namespace should not be listed as opencode"; then
    test_pass
fi

test_case "pre-upgrade resolver caches cannot restore retired shipped defaults"
if (
    source "$PROJECT_ROOT/scripts/lib/provider-registry.sh"
    source "$PROJECT_ROOT/scripts/lib/model-cache-path.sh"
    export HOME="$TEST_TMP_DIR/cache-home" TMPDIR="$TEST_TMP_DIR/cache-tmp" USER="octo-cache-$$"
    mkdir -p "$HOME" "$TMPDIR"
    unset OCTOPUS_OPENCODE_MODEL OCTOPUS_OPENROUTER_MODEL OCTOPUS_PROVIDERS_CONFIG
    export OCTOPUS_COST_MODE=standard OCTOPUS_ROUTING_POLICY=off
    for seat in openrouter opencode opencode-fast opencode-research; do
        export CLAUDE_CODE_SESSION="$seat-upgrade"
        provider=opencode
        old=opencode/deepseek-v4-flash-free
        expected=opencode/deepseek-v4.1-flash-free
        case "$seat" in
            openrouter) provider=openrouter; old=anthropic/claude-sonnet-4; expected=anthropic/claude-sonnet-4.6 ;;
            opencode-research) old=opencode/glm-5.1; expected=opencode/glm-5.3 ;;
        esac
        initial="$(resolve_octopus_model "$provider" "$seat")" || exit 1
        [[ "$initial" == "$expected" ]] || exit 1
        cache="$(octo_model_cache_file)" || exit 1
        [[ -f "$cache" ]] || exit 1
        # Before this upgrade the key had no defaults revision component.
        jq --arg old "$old" 'with_entries(.key |= sub("^MC_V[0-9]+_"; "MC_") | .value = $old)' \
            "$cache" > "$cache.old" || exit 1
        mv "$cache.old" "$cache" || exit 1
        actual="$(resolve_octopus_model "$provider" "$seat")"
        [[ "$actual" == "$expected" ]] || { echo "$seat restored $actual"; exit 1; }
    done
); then
    test_pass
else
    test_fail "pre-upgrade cached default survived the catalog update"
fi

test_summary
