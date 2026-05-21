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

if bash -n "$MODEL_RESOLVER"; then
    pass "model resolver has valid bash syntax"
else
    fail "model resolver has valid bash syntax" "syntax error"
fi

TEST_HOME="$TEST_TMP_DIR/home"
mkdir -p "$TEST_HOME"

source "$MODEL_RESOLVER"

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

test_summary
