#!/usr/bin/env bash
# Regression checks for tangle [CODING] agent override routing.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_TMP_DIR="${TEST_TMP_DIR:-/tmp/octopus-tests-$$}"
trap 'rm -rf "$TEST_TMP_DIR"' EXIT INT TERM

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "tangle coding agent override"

WORKFLOWS="$PROJECT_ROOT/scripts/lib/workflows.sh"
AGENT_UTILS="$PROJECT_ROOT/scripts/lib/agent-utils.sh"

# Minimal environment/helpers referenced while sourcing agent-utils.sh in this focused unit test.
PLUGIN_DIR="$PROJECT_ROOT"
WORKSPACE_DIR="$TEST_TMP_DIR"
RESULTS_DIR="$WORKSPACE_DIR/results"
mkdir -p "$RESULTS_DIR"
log() { :; }

source "$AGENT_UTILS"

test_case "octopus_agent_override resolves tangle coding-specific env first"
if (
    export OCTOPUS_TANGLE_CODING_AGENT="gemini"
    export OCTOPUS_TANGLE_AGENT="codex"
    export OCTOPUS_CODING_AGENT="claude-sonnet"
    [[ "$(octopus_agent_override tangle coding codex)" == "gemini" ]]
); then
    test_pass
else
    test_fail "OCTOPUS_TANGLE_CODING_AGENT was not preferred"
fi

test_case "octopus_agent_override falls back to phase-level tangle agent"
if (
    unset OCTOPUS_TANGLE_CODING_AGENT || true
    export OCTOPUS_TANGLE_AGENT="gemini"
    export OCTOPUS_CODING_AGENT="claude-sonnet"
    [[ "$(octopus_agent_override tangle coding codex)" == "gemini" ]]
); then
    test_pass
else
    test_fail "OCTOPUS_TANGLE_AGENT was not used as coding fallback"
fi

test_case "octopus_agent_override falls back to role-level coding agent"
if (
    unset OCTOPUS_TANGLE_CODING_AGENT OCTOPUS_TANGLE_AGENT || true
    export OCTOPUS_CODING_AGENT="claude-sonnet"
    [[ "$(octopus_agent_override tangle coding codex)" == "claude-sonnet" ]]
); then
    test_pass
else
    test_fail "OCTOPUS_CODING_AGENT was not used as final coding fallback"
fi

test_case "tangle_develop resolves tangle_coding_agent through octopus_agent_override"
resolver_count=$(grep -c 'tangle_coding_agent=$(octopus_agent_override "tangle" "coding" "codex")' "$WORKFLOWS" || true)
if [[ "$resolver_count" -gt 0 ]]; then
    test_pass
else
    test_fail "tangle_develop does not resolve OCTOPUS_TANGLE_CODING_AGENT"
fi

test_case "[CODING] subtasks use configured tangle_coding_agent instead of hardcoded codex"
step2_block=$(sed -n '/Step 2: Parallel execution/,/fleet_dispatch_end/p' "$WORKFLOWS")
configured_agent_count=$(printf '%s
' "$step2_block" | grep -c 'local agent="$tangle_coding_agent"' || true)
hardcoded_codex_count=$(printf '%s
' "$step2_block" | grep -c 'local agent="codex"' || true)
if [[ "$configured_agent_count" -gt 0 ]] && [[ "$hardcoded_codex_count" -eq 0 ]]; then
    test_pass
else
    test_fail "tangle coding loop still hardcodes codex"
fi

test_summary
