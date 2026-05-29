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
if [[ "$(HOME="$TEST_HOME" USER="octo-test-$$" CLAUDE_CODE_SESSION="opencode-default" resolve_octopus_model opencode opencode 2>/dev/null)" == "opencode/deepseek-v4-flash-free" ]]; then
    test_pass
else
    test_fail "expected opencode/deepseek-v4-flash-free"
fi

test_case "opencode-fast default uses opencode namespace"
if [[ "$(HOME="$TEST_HOME" USER="octo-test-$$" CLAUDE_CODE_SESSION="opencode-fast" resolve_octopus_model opencode opencode-fast 2>/dev/null)" == "opencode/deepseek-v4-flash-free" ]]; then
    test_pass
else
    test_fail "expected opencode/deepseek-v4-flash-free"
fi

test_case "opencode-research default uses opencode namespace"
if [[ "$(HOME="$TEST_HOME" USER="octo-test-$$" CLAUDE_CODE_SESSION="opencode-research" resolve_octopus_model opencode opencode-research 2>/dev/null)" == "opencode/glm-5.1" ]]; then
    test_pass
else
    test_fail "expected opencode/glm-5.1"
fi

test_case "model catalog includes current opencode namespace"
if is_known_model "opencode/deepseek-v4-flash-free" &&
   is_known_model "opencode/glm-5.1" &&
   [[ "$(get_model_capability "opencode/glm-5.1" provider)" == "opencode" ]]; then
    test_pass
else
    test_fail "expected opencode namespaced models in catalog"
fi

test_case "claude-opus default prefers Opus 4.8 when supported"
if [[ "$(HOME="$TEST_HOME" USER="octo-test-$$" CLAUDE_CODE_SESSION="opus48" SUPPORTS_OPUS_4_8=true SUPPORTS_OPUS_4_7=true resolve_octopus_model claude claude-opus 2>/dev/null)" == "claude-opus-4.8" ]]; then
    test_pass
else
    test_fail "expected claude-opus-4.8"
fi

test_case "claude-opus default falls back to Opus 4.7 before 4.8"
if [[ "$(HOME="$TEST_HOME" USER="octo-test-$$" CLAUDE_CODE_SESSION="opus47" SUPPORTS_OPUS_4_8=false SUPPORTS_OPUS_4_7=true resolve_octopus_model claude claude-opus 2>/dev/null)" == "claude-opus-4.7" ]]; then
    test_pass
else
    test_fail "expected claude-opus-4.7 fallback"
fi

test_case "model catalog includes Opus 4.8 and marks 4.7 legacy"
if is_known_model "claude-opus-4.8" &&
   [[ "$(get_model_capability "claude-opus-4.8" context_k)" == "1000" ]] &&
   [[ "$(get_model_capability "claude-opus-4.8" status)" == "active" ]] &&
   [[ "$(get_model_capability "claude-opus-4.7" status)" == "legacy" ]]; then
    test_pass
else
    test_fail "expected Opus 4.8 active catalog entry and Opus 4.7 legacy status"
fi

test_case "model config catalog does not expose stale opencode metadata"
catalog_output=$(HOME="$TEST_HOME" USER="octo-test-$$" CLAUDE_CODE_SESSION="opencode-catalog" "$MODEL_CONFIG" models opencode 2>/dev/null)
if assert_contains "$catalog_output" "opencode/deepseek-v4-flash-free" "opencode default should be listed" &&
   assert_contains "$catalog_output" "opencode/glm-5.1" "opencode research model should be listed" &&
   assert_not_contains "$catalog_output" "google/gemini-2.5-flash" "stale google model should not be listed as opencode" &&
   assert_not_contains "$catalog_output" "z-ai/glm-5.1" "stale openrouter namespace should not be listed as opencode"; then
    test_pass
fi

test_summary
