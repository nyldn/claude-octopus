#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT/scripts/lib/agent-sync.sh"

test_suite "Consultative Agent Dispatch"

SOURCE_ROOT="$TEST_TMP_DIR/consultative-source"
OBSERVED_FILE="$TEST_TMP_DIR/observed"
mkdir -p "$SOURCE_ROOT"
printf '%s\n' original > "$SOURCE_ROOT/protected.txt"

_octopus_prepare_consultative_workspace() {
    local source_root="$1" workspace_result_var="${2:-}" temp_root_result_var="${3:-}"
    local stub_temp_root stub_workspace
    stub_temp_root="$(mktemp -d "$TEST_TMP_DIR/octopus-consultative.XXXXXX")"
    stub_temp_root="$(cd "$stub_temp_root" && pwd -P)"
    stub_workspace="$stub_temp_root/workspace"
    mkdir -p "$stub_workspace"
    cp -a "$source_root/." "$stub_workspace/"
    if [[ -n "$workspace_result_var" && -n "$temp_root_result_var" ]]; then
        printf -v "$workspace_result_var" '%s' "$stub_workspace"
        printf -v "$temp_root_result_var" '%s' "$stub_temp_root"
    else
        printf '%s\n' "$stub_workspace"
    fi
}

STUB_RC=0
STUB_RESPONSE=""
run_agent_sync() {
    printf '%s\n' "pwd=$PWD;codex=${OCTOPUS_CODEX_SANDBOX-unset};security=${OCTOPUS_SECURITY_V870-unset};agy=${OCTOPUS_AGY_SANDBOX-unset};autonomy=${CLAUDE_OCTOPUS_AUTONOMY-unset};prompt=$2" > "$OBSERVED_FILE"
    printf '%s\n' changed > protected.txt
    [[ -z "$STUB_RESPONSE" ]] || printf '%s\n' "$STUB_RESPONSE"
    return "$STUB_RC"
}

cd "$SOURCE_ROOT"

test_case "consultative dispatch uses dangerous mode inside a disposable workspace"
export OCTOPUS_SECURITY_V870="enabled"
export OCTOPUS_AGY_SANDBOX="off"
export OCTOPUS_CODEX_SANDBOX="read-only"
export CLAUDE_OCTOPUS_AUTONOMY="autonomous"
STUB_RC=0
run_agent_sync_consultative codex "inspect $SOURCE_ROOT/protected.txt" 120 implementer ceremony
output=$(cat "$OBSERVED_FILE")
if [[ "$output" == *"codex=danger-full-access"* && "$output" == *"security=unset"* && "$output" == *"agy=unset"* && "$output" == *"autonomy=unset"* && "$output" == *"/workspace"* ]]; then
    test_pass
else
    test_fail "consultative isolation policy was not enforced: $output"
fi

test_case "relative consultative writes remain in the disposable workspace"
if [[ "$(cat "$SOURCE_ROOT/protected.txt")" == "original" ]]; then
    test_pass
else
    test_fail "consultative write escaped into source checkout"
fi

test_case "prompt paths are rewritten to the disposable workspace"
physical_source_root="$(cd "$SOURCE_ROOT" && pwd -P)"
if [[ "$output" != *"prompt=inspect $SOURCE_ROOT/protected.txt"* && "$output" != *"prompt=inspect $physical_source_root/protected.txt"* && "$output" == *"prompt=inspect "*"/workspace/protected.txt"* ]]; then
    test_pass
else
    test_fail "source checkout path remained in the agent task: $output"
fi

test_case "consultative output is marked unverified and non-deliverable"
STUB_RESPONSE="Implemented files in /tmp/disposable and verified 417 tests plus live probes."
consultative_output=$(run_agent_sync_consultative codex "design only" 120 implementer ceremony)
STUB_RESPONSE=""
if [[ "$consultative_output" == *"Implemented files in /tmp/disposable"* \
   && "$consultative_output" == *"UNVERIFIED CONSULTATIVE OUTPUT"* \
   && "$consultative_output" == *"non-deliverable"* \
   && "$consultative_output" == *"test counts"* \
   && "$consultative_output" == *"live probes"* ]]; then
    test_pass
else
    test_fail "consultative claims lacked durable provenance: $consultative_output"
fi

test_case "consultative output does not claim deletion when workspace cleanup fails"
cleanup_attempt="$TEST_TMP_DIR/cleanup-attempt"
cleanup_test_root="$(cd "$TEST_TMP_DIR" && pwd -P)"
rm() {
    if [[ "${1:-}" == "-rf" && "${2:-}" == "$cleanup_test_root"/octopus-consultative.* ]]; then
        printf '%s\n' "$2" > "$cleanup_attempt"
        return 1
    fi
    command rm "$@"
}
STUB_RESPONSE="Advisory result from disposable workspace."
cleanup_failure_output=$(run_agent_sync_consultative codex "design only" 120 implementer ceremony 2>/dev/null)
STUB_RESPONSE=""
unset -f rm
failed_temp_root="$(cat "$cleanup_attempt")"
command rm -rf "$failed_temp_root"
if [[ "$cleanup_failure_output" == *"could not confirm deletion"* \
   && "$cleanup_failure_output" != *"deleted before returning"* ]]; then
    test_pass
else
    test_fail "cleanup failure produced false provenance: $cleanup_failure_output"
fi

test_case "consultative dispatch restores existing environment after success"
if [[ "$OCTOPUS_SECURITY_V870" == "enabled" && "$OCTOPUS_AGY_SANDBOX" == "off" && "$OCTOPUS_CODEX_SANDBOX" == "read-only" && "$CLAUDE_OCTOPUS_AUTONOMY" == "autonomous" ]]; then
    test_pass
else
    test_fail "existing environment was not restored"
fi

test_case "consultative dispatch restores unset variables and source checkout after failure"
unset OCTOPUS_SECURITY_V870 OCTOPUS_AGY_SANDBOX OCTOPUS_CODEX_SANDBOX CLAUDE_OCTOPUS_AUTONOMY
STUB_RC=7
if run_agent_sync_consultative codex "inspect $SOURCE_ROOT/protected.txt" 120 implementer ceremony >/dev/null; then
    rc=0
else
    rc=$?
fi
if [[ "$rc" -eq 7 && "$(pwd -P)" == "$physical_source_root" && "$(cat "$SOURCE_ROOT/protected.txt")" == "original" && -z "${OCTOPUS_SECURITY_V870+x}" && -z "${OCTOPUS_AGY_SANDBOX+x}" && -z "${OCTOPUS_CODEX_SANDBOX+x}" && -z "${CLAUDE_OCTOPUS_AUTONOMY+x}" ]]; then
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
