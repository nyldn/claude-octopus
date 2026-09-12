#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Installed command discovery"

test_case "guide lists only commands declared by the installed manifest"
output="$(HOME="$TEST_TMP_DIR" "$PROJECT_ROOT/bin/octopus" guide --json 2>/dev/null || true)"
if jq -e --slurpfile manifest "$PROJECT_ROOT/.claude-plugin/plugin.json" '
    .commands | length == ($manifest[0].commands | length)' <<<"$output" >/dev/null 2>&1 &&
    [[ ! -d "$TEST_TMP_DIR/.claude-octopus" ]]; then test_pass; else test_fail "guide missing, incomplete, or initialized state"; fi

test_case "automatic help uses the same provider-free catalog"
auto_output="$(HOME="$TEST_TMP_DIR" "$PROJECT_ROOT/scripts/orchestrate.sh" auto help 2>/dev/null || true)"
if [[ "$auto_output" == *"/octo:setup"* && "$auto_output" == *"/octo:auto"* && ! -d "$TEST_TMP_DIR/.claude-octopus" ]]; then
    test_pass
else test_fail "auto help did not return the installed catalog without workflow state"; fi

test_case "public explain command reaches its runtime parser"
output="$(HOME="$TEST_TMP_DIR" "$PROJECT_ROOT/bin/octopus" explain --help 2>&1 || true)"
if [[ "$output" != *"Unknown octopus command"* && "$output" == *"explain"* ]]; then test_pass; else test_fail "explain is not dispatched"; fi

test_case "legacy setup alias reaches setup"
output="$(HOME="$TEST_TMP_DIR" CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$PROJECT_ROOT/hooks/user-prompt-submit.sh" <<< '{"prompt":"/octo:sys-setup"}' 2>/dev/null || true)"
if [[ "$output" == *"Alias resolved: /octo:sys-setup -> /octo:setup"* ]]; then test_pass; else test_fail "sys-setup does not resolve to setup"; fi
test_summary
