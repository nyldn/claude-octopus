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

# Issue #746: `codex exec review` has no --sandbox flag, so the seat used to
# silently inherit sandbox_mode from ~/.codex/config.toml regardless of
# OCTOPUS_CODEX_SANDBOX. It must thread the resolved sandbox through -c
# sandbox_mode=... instead.
test_case "codex-review threads OCTOPUS_CODEX_SANDBOX via -c sandbox_mode"
export OCTOPUS_CODEX_SANDBOX=read-only
cmd="$(get_agent_command codex-review tangle reviewer)"
if [[ " $cmd " == *" -c sandbox_mode=read-only "* ]]; then
    test_pass
else
    test_fail "expected -c sandbox_mode=read-only, got: $cmd"
fi

test_case "codex-review defaults to workspace-write when unset"
unset OCTOPUS_CODEX_SANDBOX
cmd="$(get_agent_command codex-review tangle reviewer)"
if [[ " $cmd " == *" -c sandbox_mode=workspace-write "* ]]; then
    test_pass
else
    test_fail "expected -c sandbox_mode=workspace-write default, got: $cmd"
fi

test_case "codex-review never passes bare --sandbox (unsupported by codex exec review)"
export OCTOPUS_CODEX_SANDBOX=danger-full-access
cmd="$(get_agent_command codex-review tangle reviewer)"
if [[ " $cmd " != *" --sandbox "* ]]; then
    test_pass
else
    test_fail "codex-review must not pass --sandbox, got: $cmd"
fi

# `codex exec review` takes its custom review instructions as a positional
# argument, where `-` means stdin. Dispatch pipes the prompt on stdin, so
# without the trailing `-` codex sees neither a review target nor instructions
# and exits 1 with "Specify --uncommitted, --base, --commit, or provide custom
# review instructions". That made codex-review unusable as a fallback for
# text-review roles such as the Tangle decomposition adequacy gate.
test_case "codex-review reads review instructions from stdin via trailing -"
unset OCTOPUS_CODEX_SANDBOX
cmd="$(get_agent_command codex-review tangle reviewer)"
if [[ "$cmd" == *" -" ]]; then
    test_pass
else
    test_fail "expected command to end with ' -' so codex reads stdin, got: $cmd"
fi

test_summary
