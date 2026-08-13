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
if [[ "$output" == *'Opt-in auto-route: debate'* ]] && [[ "$output" == *'/commands/debate.md'* ]]; then
    test_pass
else
    test_fail "expected opt-in debate command route, got: ${output:-<empty>}"
fi

test_case "routes research prompts to discover command"
output="$(run_prompt_hook "research options for OAuth authentication patterns")"
if [[ "$output" == *'Opt-in auto-route: discover'* ]] && [[ "$output" == *'/commands/discover.md'* ]] && [[ "$output" != *'/commands/research.md'* ]]; then
    test_pass
else
    test_fail "expected discover command and no research command, got: ${output:-<empty>}"
fi

test_case "resolves setup aliases before session title"
output="$(run_prompt_hook "/octo:configure providers")"
if [[ "$output" == *'Alias resolved: /octo:configure -> /octo:setup'* ]] && [[ "$output" == *'/commands/setup.md'* ]]; then
    test_pass
else
    test_fail "expected configure alias to setup, got: ${output:-<empty>}"
fi

test_case "suggests fuzzy matches for mistyped explicit commands"
output="$(run_prompt_hook "/octo:reseach agent routing")"
if [[ "$output" == *'Unknown command /octo:reseach'* ]] && [[ "$output" == *'/octo:research'* ]]; then
    test_pass
else
    test_fail "expected research fuzzy suggestion, got: ${output:-<empty>}"
fi

test_case "promotes named option prompts to debate"
output="$(run_prompt_hook "Redis or Memcached for session state?")"
if [[ "$output" == *'Opt-in auto-route: debate'* ]] && [[ "$output" == *'/commands/debate.md'* ]]; then
    test_pass
else
    test_fail "expected proper-noun option prompt to route to debate, got: ${output:-<empty>}"
fi

test_case "suggest mode does not inject a command route"
output="$(run_prompt_hook "review this PR for regressions" "suggest")"
if [[ "$output" == *"Detected intent: review"* ]] && [[ "$output" != *"Opt-in auto-route"* ]]; then
    test_pass
else
    test_fail "expected suggest-only context, got: ${output:-<empty>}"
fi

test_case "opt-in routing wording is advisory, never mandatory"
output="$(run_prompt_hook "should we use Redis or Memcached for session state?")"
if [[ "$output" == *"Opt-in auto-route: debate"* ]] && [[ "$output" != *"MANDATORY"* ]]; then
    test_pass
else
    test_fail "expected advisory auto-route without MANDATORY, got: ${output:-<empty>}"
fi

test_case "system notification prompts are never routed"
output="$(run_prompt_hook "[SYSTEM NOTIFICATION - NOT USER INPUT] should we use Redis or Memcached?")"
if [[ -z "$output" ]]; then
    test_pass
else
    test_fail "expected no routing for system notification, got: $output"
fi

test_case "task-notification prompts are never routed"
output="$(run_prompt_hook "<task-notification>research OAuth options for the deploy task</task-notification>")"
if [[ -z "$output" ]]; then
    test_pass
else
    test_fail "expected no routing for task-notification, got: $output"
fi

test_case "system-reminder prompts are never routed"
output="$(run_prompt_hook "<system-reminder>review this PR for regressions</system-reminder>")"
if [[ -z "$output" ]]; then
    test_pass
else
    test_fail "expected no routing for system-reminder, got: $output"
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

test_case "SessionStart auto-router is silent by default"
if [[ -x "$SESSION_HOOK" ]]; then
    output="$(HOME="$TEST_TMP_DIR/home-session" CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" "$SESSION_HOOK" <<< '{"hook_event_name":"SessionStart"}')"
    if [[ -z "$output" ]]; then
        test_pass
    else
        test_fail "expected no default routing contract, got: ${output:-<empty>}"
    fi
else
    test_fail "missing executable hook: $SESSION_HOOK"
fi

test_case "SessionStart auto-router emits a contract after explicit opt-in"
output="$(HOME="$TEST_TMP_DIR/home-session-opt-in" CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" OCTOPUS_AUTO_ROUTER_MODE=invoke "$SESSION_HOOK" <<< '{"hook_event_name":"SessionStart"}')"
if [[ "$output" == *"OCTOPUS-AUTO-ROUTER"* ]] && [[ "$output" == *"commands/debate.md"* ]]; then
    test_pass
else
    test_fail "expected opt-in routing contract output, got: ${output:-<empty>}"
fi

test_summary
