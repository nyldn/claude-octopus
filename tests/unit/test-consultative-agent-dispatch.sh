#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT/scripts/lib/agent-sync.sh"

test_suite "Consultative Agent Dispatch"

TEST_ROOT="/tmp/octopus-consultative-test-$$"
SOURCE_ROOT="$TEST_ROOT/source"
OBSERVED_FILE="$TEST_ROOT/observed"
mkdir -p "$SOURCE_ROOT"
printf '%s\n' original > "$SOURCE_ROOT/protected.txt"
trap 'rm -rf "$TEST_ROOT"' EXIT

_octopus_prepare_consultative_workspace() {
    local source_root="$1" temp_root workspace
    temp_root="$(mktemp -d "$TEST_ROOT/workspace.XXXXXX")"
    workspace="$temp_root/workspace"
    mkdir -p "$workspace"
    cp -a "$source_root/." "$workspace/"
    printf '%s\n' "$workspace"
}

STUB_RC=0
run_agent_sync() {
    printf '%s\n' "pwd=$PWD;codex=${OCTOPUS_CODEX_SANDBOX-unset};security=${OCTOPUS_SECURITY_V870-unset};gemini=${OCTOPUS_GEMINI_SANDBOX-unset};agy=${OCTOPUS_AGY_SANDBOX-unset};autonomy=${CLAUDE_OCTOPUS_AUTONOMY-unset};prompt=$2" > "$OBSERVED_FILE"
    printf '%s\n' changed > protected.txt
    return "$STUB_RC"
}

cd "$SOURCE_ROOT"

test_case "consultative dispatch uses dangerous mode inside a disposable workspace"
export OCTOPUS_SECURITY_V870="enabled"
export OCTOPUS_GEMINI_SANDBOX="workspace-write"
export OCTOPUS_AGY_SANDBOX="off"
export OCTOPUS_CODEX_SANDBOX="read-only"
export CLAUDE_OCTOPUS_AUTONOMY="autonomous"
STUB_RC=0
run_agent_sync_consultative codex "inspect $SOURCE_ROOT/protected.txt" 120 implementer ceremony
output=$(cat "$OBSERVED_FILE")
if [[ "$output" == *"codex=danger-full-access"* && "$output" == *"security=unset"* && "$output" == *"gemini=unset"* && "$output" == *"agy=unset"* && "$output" == *"autonomy=unset"* && "$output" == *"/workspace"* ]]; then
    test_pass
else
    test_fail "consultative isolation policy was not enforced: $output"
fi

test_case "consultative writes do not reach the source checkout"
if [[ "$(cat "$SOURCE_ROOT/protected.txt")" == "original" ]]; then
    test_pass
else
    test_fail "consultative write escaped into source checkout"
fi

test_case "prompt paths are rewritten to the disposable workspace"
if [[ "$output" != *"prompt=inspect $SOURCE_ROOT/protected.txt"* && "$output" == *"prompt=inspect "*"/workspace/protected.txt"* ]]; then
    test_pass
else
    test_fail "source checkout path remained in the agent task: $output"
fi

test_case "consultative dispatch restores existing environment after success"
if [[ "$OCTOPUS_SECURITY_V870" == "enabled" && "$OCTOPUS_GEMINI_SANDBOX" == "workspace-write" && "$OCTOPUS_AGY_SANDBOX" == "off" && "$OCTOPUS_CODEX_SANDBOX" == "read-only" && "$CLAUDE_OCTOPUS_AUTONOMY" == "autonomous" ]]; then
    test_pass
else
    test_fail "existing environment was not restored"
fi

test_case "consultative dispatch restores unset variables and source checkout after failure"
unset OCTOPUS_SECURITY_V870 OCTOPUS_GEMINI_SANDBOX OCTOPUS_AGY_SANDBOX OCTOPUS_CODEX_SANDBOX CLAUDE_OCTOPUS_AUTONOMY
STUB_RC=7
if run_agent_sync_consultative codex "inspect $SOURCE_ROOT/protected.txt" 120 implementer ceremony >/dev/null; then
    rc=0
else
    rc=$?
fi
if [[ "$rc" -eq 7 && "$(pwd -P)" == "$SOURCE_ROOT" && "$(cat "$SOURCE_ROOT/protected.txt")" == "original" && -z "${OCTOPUS_SECURITY_V870+x}" && -z "${OCTOPUS_GEMINI_SANDBOX+x}" && -z "${OCTOPUS_AGY_SANDBOX+x}" && -z "${OCTOPUS_CODEX_SANDBOX+x}" && -z "${CLAUDE_OCTOPUS_AUTONOMY+x}" ]]; then
    test_pass
else
    test_fail "failure cleanup/restoration incorrect: rc=$rc pwd=$(pwd -P)"
fi

test_case "council and quality load the shared consultative primitive"
if bash -c 'source "$1/scripts/lib/council.sh"; declare -F run_agent_sync_consultative >/dev/null' _ "$PROJECT_ROOT" && \
   bash -c 'source "$1/scripts/lib/quality.sh"; declare -F run_agent_sync_consultative >/dev/null' _ "$PROJECT_ROOT"; then
    test_pass
else
    test_fail "standalone libraries did not load consultative dependency"
fi

test_summary
