#!/usr/bin/env bash
# Tests for OpenAI-compatible tool-loop agent dispatch.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "OpenAI-compatible tool-loop agent"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

MODEL_RESOLVER="$PROJECT_ROOT/scripts/lib/model-resolver.sh"
DISPATCH="$PROJECT_ROOT/scripts/lib/dispatch.sh"
HELPER="$PROJECT_ROOT/scripts/helpers/openai-compatible-agent.py"

log() { :; }
migrate_provider_config() { :; }
validate_model_allowed() { return 0; }
opus_default_model() { echo "claude-opus-4.8"; }
PROVIDER_CODEX_INSTALLED="false"

if bash -n "$DISPATCH" "$MODEL_RESOLVER" && python3 -m py_compile "$HELPER"; then
    pass "agent scripts have valid syntax"
else
    fail "agent scripts have valid syntax" "syntax error"
fi

TEST_HOME="$TEST_TMP_DIR/home"
mkdir -p "$TEST_HOME"

source "$MODEL_RESOLVER"
source "$DISPATCH"

export PLUGIN_DIR="$PROJECT_ROOT"

test_case "openai-compatible-agent honors OPENAI_COMPAT_MODEL"
model=$(HOME="$TEST_HOME" USER="octo-test-$$" CLAUDE_CODE_SESSION="compat-agent" OPENAI_COMPAT_MODEL="vendor/model-pro" get_agent_model openai-compatible-agent 2>/dev/null)
if [[ "$model" == "vendor/model-pro" ]]; then
    test_pass
else
    test_fail "expected vendor/model-pro, got ${model:-<empty>}"
fi

test_case "openai-compatible-agent is available with default OPENAI_API_KEY"
if OPENAI_COMPAT_BASE_URL="https://example.invalid/v1" OPENAI_API_KEY="test-key" is_agent_available_v2 openai-compatible-agent; then
    test_pass
else
    test_fail "expected default OPENAI_API_KEY configuration to be available"
fi

test_case "openai-compatible-agent dispatch uses generic helper and cwd"
cmd=$(HOME="$TEST_HOME" USER="octo-test-$$" CLAUDE_CODE_SESSION="compat-cmd" PWD="/tmp/octo-cwd" OPENAI_COMPAT_MODEL="vendor/model-fast" get_agent_command openai-compatible-agent 2>/dev/null)
if assert_contains "$cmd" "scripts/helpers/openai-compatible-agent.py" "helper path" &&
   assert_contains "$cmd" "--provider generic" "generic provider" &&
   assert_contains "$cmd" "--model vendor/model-fast" "configured model" &&
   assert_contains "$cmd" "--cwd /tmp/octo-cwd" "cwd flag"; then
    test_pass
fi

test_summary
