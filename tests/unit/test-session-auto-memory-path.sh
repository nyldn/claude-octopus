#!/usr/bin/env bash
# Session hooks must never treat the project root as Claude's memory storage.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Project-scoped session auto-memory (#1183)"

fixture="$TEST_TMP_DIR/session-memory"
mkdir -p "$fixture"

prepare_case() {
    case_root="$fixture/$1"
    case_home="$case_root/home"
    case_project="$case_root/project.with spaces"
    mkdir -p "$case_home/.claude-octopus" "$case_project"
    touch "$case_home/.claude-octopus/.setup-complete"
    printf '%s\n' '{"autonomy":"supervised","providers":"codex","workflow":"review","total_agent_calls":1,"errors":[]}' \
        > "$case_home/.claude-octopus/session.json"
    encoded="${case_project//[^a-zA-Z0-9]/-}"
    case_memory="$case_home/.claude/projects/$encoded/memory"
}

run_hook() {
    local hook="$1"; shift
    (
        cd "$case_project" || exit 1
        env -u CLAUDE_CONFIG_DIR HOME="$case_home" CLAUDE_PROJECT_DIR="$case_project" \
            CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" OCTOPUS_SESSION_MEMORY=on \
            "$@" bash "$PROJECT_ROOT/hooks/$hook.sh" </dev/null
    ) > "$case_root/$hook.out" 2> "$case_root/$hook.err"
}

test_case "no auto-memory directory means no project-tree memory writes"
prepare_case missing
if run_hook session-end && [[ ! -e "$case_project/memory" ]]; then
    test_pass
else
    test_fail "session-end created memory in the user's working tree"
fi

test_case "preferences and learnings go to this project's existing memory directory"
prepare_case existing
mkdir -p "$case_memory"
if run_hook session-end && [[ ! -e "$case_project/memory" ]] \
    && grep -q 'Preferred autonomy: supervised' "$case_memory/octopus-preferences.md" \
    && grep -q 'Workflow: review' "$case_memory/octopus-learnings.md"; then
    test_pass
else
    test_fail "preferences or learnings missed the matching auto-memory directory"
fi

test_case "an unrelated project's memory is never used as fallback"
prepare_case unrelated
other_memory="$case_home/.claude/projects/other-project/memory"
mkdir -p "$other_memory"
printf 'unrelated preferences\n' > "$other_memory/octopus-preferences.md"
if run_hook session-end && [[ ! -e "$case_project/memory" ]] \
    && [[ "$(cat "$other_memory/octopus-preferences.md")" == 'unrelated preferences' ]] \
    && [[ ! -e "$other_memory/octopus-learnings.md" ]]; then
    test_pass
else
    test_fail "session memory escaped to the repository or another project"
fi

test_case "CWD selects the same memory directory when CLAUDE_PROJECT_DIR is absent"
prepare_case cwd
mkdir -p "$case_memory"
if run_hook session-end env -u CLAUDE_PROJECT_DIR \
    && [[ -f "$case_memory/octopus-preferences.md" && ! -e "$case_project/memory" ]]; then
    test_pass
else
    test_fail "CWD fallback did not resolve the exact project"
fi

test_case "custom CLAUDE_CONFIG_DIR is honored without writing to the project"
prepare_case custom-config
custom_config="$case_root/custom config"
custom_memory="$custom_config/projects/$encoded/memory"
mkdir -p "$custom_memory"
if run_hook session-end env "CLAUDE_CONFIG_DIR=$custom_config" \
    && [[ -f "$custom_memory/octopus-preferences.md" && ! -e "$case_project/memory" ]]; then
    test_pass
else
    test_fail "custom Claude configuration root was ignored"
fi

test_case "SessionStart restores from the same directory and ignores repository memory"
prepare_case restore
mkdir -p "$case_memory" "$case_project/memory"
printf '%s\n' '- Preferred autonomy: supervised' '- Provider config: codex' > "$case_memory/octopus-preferences.md"
printf '%s\n' '- Preferred autonomy: autonomous' > "$case_project/memory/octopus-preferences.md"
if run_hook session-start-memory \
    && jq -e '.autonomy == "supervised" and .restored_from_memory == true' \
        "$case_home/.claude-octopus/session.json" >/dev/null; then
    test_pass
else
    test_fail "SessionStart restored repository-local preferences instead of project auto-memory"
fi

test_case "SessionStart also honors a custom Claude configuration root"
prepare_case restore-custom
custom_config="$case_root/custom config"
mkdir -p "$custom_config/projects/$encoded/memory"
printf '%s\n' '- Preferred autonomy: manual' > "$custom_config/projects/$encoded/memory/octopus-preferences.md"
if run_hook session-start-memory env "CLAUDE_CONFIG_DIR=$custom_config" \
    && jq -e '.autonomy == "manual" and .restored_from_memory == true' \
        "$case_home/.claude-octopus/session.json" >/dev/null; then
    test_pass
else
    test_fail "SessionStart used a different memory mapping than SessionEnd"
fi

# Literal fixtures independently pin Claude Code's project-key convention.
# Dots, underscores, spaces and parentheses become dashes, not only slashes.
source "$PROJECT_ROOT/hooks/helpers/claude-project-memory.sh"
while IFS='|' read -r native_project native_key; do
    test_case "native Claude project key for $native_project"
    prepare_case "native-$native_key"
    native_memory="$case_home/.claude/projects/$native_key/memory"
    mkdir -p "$native_memory"
    native_result="$(CLAUDE_PROJECT_DIR="$native_project" \
        CLAUDE_CONFIG_DIR="$case_home/.claude" octo_claude_project_memory_dir)"
    if [[ "$native_result" == "$native_memory" ]]; then
        test_pass
    else
        test_fail "literal Claude project-key fixture did not resolve"
    fi
done <<'NATIVE_PROJECT_KEYS'
/home/octopus/my.app|-home-octopus-my-app
/home/octopus/proj_v2|-home-octopus-proj-v2
/home/octopus/work (copy)|-home-octopus-work--copy-
NATIVE_PROJECT_KEYS

test_case "slash-only punctuation key is not an auto-memory fallback"
prepare_case slash-only
mkdir -p "$case_home/.claude/projects/-home-octopus-my.app/memory"
if native_result="$(CLAUDE_PROJECT_DIR=/home/octopus/my.app \
    CLAUDE_CONFIG_DIR="$case_home/.claude" octo_claude_project_memory_dir)"; then
    test_fail "resolved a directory that preserves punctuation in the project key"
else
    test_pass
fi

test_summary
