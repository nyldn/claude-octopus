#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Codex sandbox mode dispatch"

log() { :; }
migrate_provider_config() { :; }
resolve_octopus_model() { echo "test-model"; }
export _BARE_OPT=""
export OCTOPUS_PLATFORM="${OCTOPUS_PLATFORM:-Linux}"
export PLUGIN_DIR="${PLUGIN_DIR:-$PROJECT_ROOT}"

source "$PROJECT_ROOT/scripts/lib/dispatch.sh"

test_case "danger-full-access sandbox is accepted for codex dispatch"
export OCTOPUS_CODEX_SANDBOX=danger-full-access
cmd="$(get_agent_command codex tangle implementer)"
if [[ "$cmd" == *"--sandbox danger-full-access"* ]]; then
    test_pass
else
    test_fail "expected danger-full-access sandbox, got: $cmd"
fi

test_case "invalid codex sandbox falls back to workspace-write"
export OCTOPUS_CODEX_SANDBOX=invalid-mode
cmd="$(get_agent_command codex tangle implementer)"
if [[ "$cmd" == *"--sandbox workspace-write"* ]]; then
    test_pass
else
    test_fail "expected workspace-write fallback, got: $cmd"
fi

test_summary
