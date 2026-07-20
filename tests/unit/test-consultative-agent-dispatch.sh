#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT/scripts/lib/agent-sync.sh"

test_suite "Consultative Agent Dispatch"

OBSERVED_FILE="/tmp/octopus-consultative-observed-$$"
trap 'rm -f "$OBSERVED_FILE"' EXIT
STUB_RC=0
run_agent_sync() {
    printf '%s\n' "codex=${OCTOPUS_CODEX_SANDBOX-unset};security=${OCTOPUS_SECURITY_V870-unset};gemini=${OCTOPUS_GEMINI_SANDBOX-unset};autonomy=${CLAUDE_OCTOPUS_AUTONOMY-unset};args=$*" > "$OBSERVED_FILE"
    return "$STUB_RC"
}

test_case "consultative dispatch enforces read-only and disables write-enabling overrides"
export OCTOPUS_SECURITY_V870="enabled"
export OCTOPUS_GEMINI_SANDBOX="workspace-write"
export OCTOPUS_CODEX_SANDBOX="danger-full-access"
export CLAUDE_OCTOPUS_AUTONOMY="autonomous"
STUB_RC=0
run_agent_sync_consultative codex prompt 120 implementer ceremony
output=$(cat "$OBSERVED_FILE")
if [[ "$output" == *"codex=read-only"* && "$output" == *"security=unset"* && "$output" == *"gemini=unset"* && "$output" == *"autonomy=unset"* ]]; then
    test_pass
else
    test_fail "consultative policy was not enforced: $output"
fi

test_case "consultative dispatch restores existing environment after success"
if [[ "$OCTOPUS_SECURITY_V870" == "enabled" && "$OCTOPUS_GEMINI_SANDBOX" == "workspace-write" && "$OCTOPUS_CODEX_SANDBOX" == "danger-full-access" && "$CLAUDE_OCTOPUS_AUTONOMY" == "autonomous" ]]; then
    test_pass
else
    test_fail "existing environment was not restored"
fi

test_case "consultative dispatch restores unset variables after failure"
unset OCTOPUS_SECURITY_V870 OCTOPUS_GEMINI_SANDBOX OCTOPUS_CODEX_SANDBOX CLAUDE_OCTOPUS_AUTONOMY
STUB_RC=7
set +e
run_agent_sync_consultative codex prompt 120 implementer ceremony >/dev/null
rc=$?
set -e
if [[ "$rc" -eq 7 && -z "${OCTOPUS_SECURITY_V870+x}" && -z "${OCTOPUS_GEMINI_SANDBOX+x}" && -z "${OCTOPUS_CODEX_SANDBOX+x}" && -z "${CLAUDE_OCTOPUS_AUTONOMY+x}" ]]; then
    test_pass
else
    test_fail "failure rc/environment restoration incorrect: rc=$rc"
fi

test_case "design review and council use the shared consultative primitive"
if grep -q 'run_agent_sync_consultative "$design_codex_agent"' "$PROJECT_ROOT/scripts/lib/quality.sh" && \
   grep -q 'run_agent_sync_consultative "$design_synthesis_agent"' "$PROJECT_ROOT/scripts/lib/quality.sh" && \
   grep -q 'run_agent_sync_consultative "$agent_type"' "$PROJECT_ROOT/scripts/lib/council.sh"; then
    test_pass
else
    test_fail "consultative callers do not share the primitive"
fi

test_summary
