#!/bin/bash
# tests/smoke/test-retro-command.sh
# Smoke tests for /octo:retro engineering retrospective command

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Retro Command (Smoke)"

COMMAND_FILE="$PROJECT_ROOT/commands/retro.md"
PLUGIN_JSON="$PROJECT_ROOT/.claude-plugin/plugin.json"

test_command_file_exists() {
    test_case "retro.md command file exists"

    if [[ -f "$COMMAND_FILE" ]]; then
        test_pass
    else
        test_fail "retro.md not found at $COMMAND_FILE"
        return 1
    fi
}

test_valid_frontmatter() {
    test_case "retro.md has valid YAML frontmatter"

    if grep -q "^---$" "$COMMAND_FILE" && \
       grep -q "^command: retro$" "$COMMAND_FILE" && \
       grep -q "^description:" "$COMMAND_FILE"; then
        test_pass
    else
        test_fail "retro.md missing required YAML frontmatter (command/description)"
        return 1
    fi
}

test_allowed_tools_declared() {
    test_case "retro.md declares allowed-tools in frontmatter"

    if grep -q "^allowed-tools:" "$COMMAND_FILE"; then
        test_pass
    else
        test_fail "retro.md missing allowed-tools declaration"
        return 1
    fi
}

test_registered_in_plugin_json() {
    test_case "retro.md is registered in plugin.json commands array"

    if grep -q '"./commands/retro.md"' "$PLUGIN_JSON"; then
        test_pass
    else
        test_fail "retro.md not found in plugin.json commands array"
        return 1
    fi
}

test_contains_git_log_commands() {
    test_case "retro.md references git log commands for data gathering"

    if grep -q "git log --oneline" "$COMMAND_FILE" && \
       grep -q "git log --numstat" "$COMMAND_FILE" && \
       grep -q "git shortlog -sn" "$COMMAND_FILE"; then
        test_pass
    else
        test_fail "retro.md missing expected git log commands"
        return 1
    fi
}

test_mentions_session_detection() {
    test_case "retro.md mentions session detection with 45-min gap"

    if grep -q "session" "$COMMAND_FILE" && \
       grep -q "45" "$COMMAND_FILE"; then
        test_pass
    else
        test_fail "retro.md missing session detection logic (45-min gap)"
        return 1
    fi
}

test_mentions_hotspot_analysis() {
    test_case "retro.md mentions hotspot analysis"

    if grep -qi "hotspot" "$COMMAND_FILE"; then
        test_pass
    else
        test_fail "retro.md missing hotspot analysis section"
        return 1
    fi
}

test_mentions_json_snapshot() {
    test_case "retro.md specifies JSON snapshot output"

    if grep -q "\.claude-octopus/retros/" "$COMMAND_FILE" && \
       grep -q "\.json" "$COMMAND_FILE"; then
        test_pass
    else
        test_fail "retro.md missing JSON snapshot specification"
        return 1
    fi
}

test_mentions_comparison() {
    test_case "retro.md includes prior snapshot comparison"

    if grep -Eqi "prior snapshot|comparison|compare" "$COMMAND_FILE"; then
        test_pass
    else
        test_fail "retro.md missing prior snapshot comparison logic"
        return 1
    fi
}

test_mentions_ai_assisted_commits() {
    test_case "retro.md tracks AI-assisted commits via Co-Authored-By"

    if grep -q "Co-Authored-By" "$COMMAND_FILE" && \
       grep -qi "ai.assisted" "$COMMAND_FILE"; then
        test_pass
    else
        test_fail "retro.md missing AI-assisted commit detection"
        return 1
    fi
}

test_mentions_conventional_commits() {
    test_case "retro.md parses conventional commit prefixes"

    if grep -q "feat:" "$COMMAND_FILE" && \
       grep -q "fix:" "$COMMAND_FILE" && \
       grep -q "refactor:" "$COMMAND_FILE"; then
        test_pass
    else
        test_fail "retro.md missing conventional commit prefix parsing"
        return 1
    fi
}

test_no_gstack_attribution() {
    test_case "retro.md has no gstack attribution references"

    if grep -qi "gstack" "$COMMAND_FILE"; then
        test_fail "retro.md contains prohibited 'gstack' reference"
        return 1
    else
        test_pass
    fi
}

# Run all tests
test_command_file_exists
test_valid_frontmatter
test_allowed_tools_declared
test_registered_in_plugin_json
test_contains_git_log_commands
test_mentions_session_detection
test_mentions_hotspot_analysis
test_mentions_json_snapshot
test_mentions_comparison
test_mentions_ai_assisted_commits
test_mentions_conventional_commits
test_no_gstack_attribution

test_summary
