#!/usr/bin/env bash
# Tests for the OrcaRouter provider: registry capabilities, model resolution,
# model catalog entries, dispatch command, and API-key detection.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "OrcaRouter provider"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

source "$PROJECT_ROOT/scripts/lib/provider-registry.sh"

test_case "registry declares orcarouter with full provider capabilities"
if octo_provider_valid "orcarouter" &&
   octo_provider_has_capability "orcarouter" dispatch &&
   octo_provider_has_capability "orcarouter" health &&
   octo_provider_has_capability "orcarouter" detect &&
   octo_provider_has_capability "orcarouter" model-config &&
   octo_provider_has_capability "orcarouter" env; then
    test_pass
else
    test_fail "orcarouter registry capabilities incomplete"
fi

test_case "registry command and organization resolve for orcarouter"
if [[ "$(octo_provider_command "orcarouter")" == "orcarouter" ]] &&
   [[ "$(octo_provider_org "orcarouter")" == "orcarouter" ]]; then
    test_pass
else
    test_fail "orcarouter command/org metadata missing"
fi

MODEL_RESOLVER="$PROJECT_ROOT/scripts/lib/model-resolver.sh"
MODEL_CATALOG="$PROJECT_ROOT/scripts/lib/models.sh"

if bash -n "$MODEL_RESOLVER" "$MODEL_CATALOG"; then
    pass "orcarouter model scripts have valid bash syntax"
else
    fail "orcarouter model scripts have valid bash syntax" "syntax error"
fi

TEST_HOME="$TEST_TMP_DIR/orca-home"
mkdir -p "$TEST_HOME"

source "$MODEL_RESOLVER"
source "$MODEL_CATALOG"

test_case "bare orcarouter resolves to a namespaced OrcaRouter ID"
if [[ "$(HOME="$TEST_HOME" USER="octo-test-$$" CLAUDE_CODE_SESSION="orcarouter-default" resolve_octopus_model orcarouter orcarouter 2>/dev/null)" == "anthropic/claude-sonnet-4.6" ]]; then
    test_pass
else
    test_fail "expected anthropic/claude-sonnet-4.6"
fi

test_case "model catalog includes the orcarouter fallback models"
if is_known_model "anthropic/claude-sonnet-4.6" &&
   is_known_model "anthropic/claude-opus-4.8" &&
   is_known_model "anthropic/claude-haiku-4.5" &&
   [[ "$(get_model_capability "anthropic/claude-sonnet-4.6" provider)" == "orcarouter" ]] &&
   [[ "$(get_model_capability "anthropic/claude-opus-4.8" context_k)" == "1000" ]]; then
    test_pass
else
    test_fail "orcarouter models missing or mislabeled in catalog"
fi

# Dispatch: the command builder must emit the shell-function executor for the
# orcarouter agent type, the same shape openrouter uses.
source "$PROJECT_ROOT/scripts/lib/dispatch.sh"
test_case "get_agent_command emits orcarouter_execute"
cmd="$(get_agent_command orcarouter tangle implementer 2>/dev/null)" || cmd=""
if [[ "$cmd" == "orcarouter_execute" ]]; then
    test_pass
else
    test_fail "expected 'orcarouter_execute', got: '$cmd'"
fi

# Detection: an ORCAROUTER_API_KEY alone must surface orcarouter in the
# provider inventory, mirroring the openrouter api-key detection.
test_case "detect_providers surfaces orcarouter with an API key"
stub_dir=$(mktemp -d)
set +e
detected=$(env "HOME=$stub_dir" "PATH=$PATH" "ORCAROUTER_API_KEY=sk-orca-test" OCTO_ALLOWED_PROVIDERS=orcarouter bash -c 'log(){ :; }; source "'$PROJECT_ROOT'/scripts/lib/providers.sh"; detect_providers')
set -e
rm -rf "$stub_dir"
if [[ "$detected" == *"orcarouter:api-key"* ]]; then
    test_pass
else
    test_fail "orcarouter not detected: $detected"
fi

test_summary
