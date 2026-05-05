#!/usr/bin/env bash
# Tests for Octopus auto-router hook behavior.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Octopus auto-router hooks"

HOOK="$PROJECT_ROOT/hooks/user-prompt-submit.sh"
SESSION_HOOK="$PROJECT_ROOT/hooks/auto-router-inject.sh"

run_prompt_hook() {
    local prompt="$1"
    local mode="${2:-invoke}"
    local home_dir="$TEST_TMP_DIR/home-${RANDOM}"
    mkdir -p "$home_dir/.claude-octopus"
    printf '{"hook_event_name":"UserPromptSubmit","session_id":"test-session","cwd":"/tmp","prompt":%s}\n' \
        "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$prompt")" |
        HOME="$home_dir" \
        CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" \
        OCTOPUS_AUTO_ROUTER_MODE="$mode" \
        "$HOOK"
}

run_cursor_prompt_hook() {
    local prompt="$1"
    local home_dir="$TEST_TMP_DIR/home-cursor-${RANDOM}"
    mkdir -p "$home_dir/.claude-octopus"
    printf '{"hook_event_name":"UserPromptSubmit","session_id":"test-session","cwd":"/tmp","prompt":%s}\n' \
        "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$prompt")" |
        HOME="$home_dir" \
        CURSOR_PLUGIN_ROOT="$PROJECT_ROOT" \
        OCTOPUS_AUTO_ROUTER_MODE="invoke" \
        "$HOOK"
}

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

test_case "routes decision prompts to debate"
output="$(run_prompt_hook "should we use Redis or Memcached for session state?")"
if [[ "$output" == *'Skill(skill: \"octo:debate\"'* ]]; then
    test_pass
else
    test_fail "expected octo:debate auto-invoke, got: ${output:-<empty>}"
fi

test_case "routes research prompts to discover skill"
output="$(run_prompt_hook "research options for OAuth authentication patterns")"
if [[ "$output" == *'Skill(skill: \"octo:discover\"'* ]] && [[ "$output" != *'octo:research'* ]]; then
    test_pass
else
    test_fail "expected octo:discover and no octo:research, got: ${output:-<empty>}"
fi

test_case "suggest mode does not inject mandatory skill call"
output="$(run_prompt_hook "review this PR for regressions" "suggest")"
if [[ "$output" == *"Detected intent: review"* ]] && [[ "$output" != *"MANDATORY: Invoke Skill"* ]]; then
    test_pass
else
    test_fail "expected suggest-only context, got: ${output:-<empty>}"
fi

test_case "off mode leaves prompt untouched"
output="$(run_prompt_hook "review this PR for regressions" "off")"
if [[ -z "$output" ]]; then
    test_pass
else
    test_fail "expected empty output when off, got: $output"
fi

test_case "Cursor output uses additional_context without Claude hookSpecificOutput"
output="$(run_cursor_prompt_hook "review this PR for regressions")"
if [[ "$output" == *'"additional_context"'* ]] && [[ "$output" != *'hookSpecificOutput'* ]]; then
    test_pass
else
    test_fail "expected Cursor-style additional_context only, got: ${output:-<empty>}"
fi

test_case "SessionStart auto-router injection hook exists and emits routing contract"
if [[ -x "$SESSION_HOOK" ]]; then
    output="$(HOME="$TEST_TMP_DIR/home-session" CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" "$SESSION_HOOK" <<< '{"hook_event_name":"SessionStart"}')"
    if [[ "$output" == *"OCTOPUS-AUTO-ROUTER"* ]] && [[ "$output" == *"octo:debate"* ]]; then
        test_pass
    else
        test_fail "expected routing contract output, got: ${output:-<empty>}"
    fi
else
    test_fail "missing executable hook: $SESSION_HOOK"
fi

test_summary
