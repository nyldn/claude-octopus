#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "spawn agent PID capture"

# Load only the helper under test so the fixture controls spawn_agent and log.
eval "$(sed -n '/^spawn_agent_capture_pid() {/,/^}/p' "$PROJECT_ROOT/scripts/lib/spawn.sh")"

TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT INT TERM

log() { printf '%s %s\n' "${1:-}" "${2:-}" >> "$TMP_ROOT/log"; }

# The wrapper does meaningful setup before it can print the provider PID.
# Capture must wait for that PID rather than returning the wrapper PID.
test_case "returns delayed provider PID rather than wrapper PID"
spawn_agent() {
    sleep 0.3
    printf '%s\n' 424242
}
export OCTOPUS_SPAWN_PID_WAIT_ATTEMPTS=20
pid=$(spawn_agent_capture_pid codex prompt delayed-task implementer tangle)
if [[ "$pid" == "424242" ]]; then
    test_pass
else
    test_fail "expected provider PID 424242, got: ${pid:-empty}"
fi

# A failed setup must fail dispatch. Returning the short-lived wrapper PID would
# make downstream wait loops report a false missing completion marker.
test_case "fails when spawn_agent exits without provider PID"
spawn_agent() {
    printf '%s\n' "setup failed before provider launch"
    return 1
}
export OCTOPUS_SPAWN_PID_WAIT_ATTEMPTS=20
if pid=$(spawn_agent_capture_pid codex prompt failed-task implementer tangle 2>/dev/null); then
    test_fail "expected failure, got wrapper/provider PID: ${pid:-empty}"
else
    test_pass
fi

test_case "implementation has no wrapper PID fallback"
if grep -q 'tracking wrapper PID' "$PROJECT_ROOT/scripts/lib/spawn.sh"; then
    test_fail "unsafe wrapper PID fallback still present"
else
    test_pass
fi

test_summary
