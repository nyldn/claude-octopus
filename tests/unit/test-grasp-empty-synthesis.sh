#!/usr/bin/env bash
# Regression check: a zero-exit AGY call with no output is not a valid consensus.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "grasp empty synthesis fallback"

# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/workflows.sh"

RESULTS_DIR="$TEST_TMP_DIR/results"
LOGS_DIR="$TEST_TMP_DIR/logs"
mkdir -p "$RESULTS_DIR" "$LOGS_DIR"

CYAN=""
GREEN=""
MAGENTA=""
NC=""
DRY_RUN=false

log() { :; }
octopus_phase_banner() { :; }
display_workflow_cost_estimate() { return 0; }
octo_provider_allowed() { return 0; }
agy() { :; }
run_agent_sync() {
    local provider="$1"
    local role="${4:-}"
    local phase="${5:-}"
    if [[ "$provider" == "agy" && "$phase" == "grasp" ]]; then
        return 0
    fi
    if [[ "$provider" == "claude-sonnet" && "$role" == "synthesizer" && "${EMPTY_CLAUDE_SYNTHESIS:-false}" == "true" ]]; then
        return 0
    fi
    printf '%s\n' "Test perspective"
}

test_case "grasp falls back to Claude when agy succeeds with empty consensus"
if grasp_define "Define the requested feature" >/dev/null 2>&1; then
    consensus_file="$(ls -t "$RESULTS_DIR"/grasp-consensus-*.md 2>/dev/null | head -1)"
    consensus_content="$(cat "$consensus_file")"
    if [[ "$consensus_content" == *"synthesizer: claude-sonnet"* ]] && \
       [[ "$consensus_content" != *"Auto-consensus failed"* ]]; then
        test_pass
    else
        test_fail "empty successful agy synthesis did not fall back to Claude"
    fi
else
    test_fail "grasp_define returned non-zero for empty successful agy synthesis"
fi

test_case "grasp preserves perspectives when every synthesizer returns empty"
rm -f "$RESULTS_DIR"/grasp-consensus-*.md
if EMPTY_CLAUDE_SYNTHESIS=true grasp_define "Define the requested feature" >/dev/null 2>&1; then
    consensus_file="$(ls -t "$RESULTS_DIR"/grasp-consensus-*.md 2>/dev/null | head -1)"
    consensus_content="$(cat "$consensus_file")"
    if [[ "$consensus_content" == *"Auto-consensus failed - manual review required"* ]] && \
       [[ "$consensus_content" == *"Test perspective"* ]]; then
        test_pass
    else
        test_fail "empty synthesis from every provider produced an empty consensus"
    fi
else
    test_fail "grasp_define returned non-zero when every synthesizer returned empty"
fi

test_summary
