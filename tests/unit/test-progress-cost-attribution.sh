#!/usr/bin/env bash
# Regression checks for #872: progress costs reflect API usage, not seat fiction.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKSPACE_DIR="${TEST_TMP_DIR:-/tmp/octopus-progress-cost-$$}"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "progress cost attribution"

# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/cost.sh"

DRY_RUN=false
get_model_pricing() { printf '%s\n' "1.00:2.00"; }
is_api_based_provider() { [[ "$1" == "codex-api" ]]; }

test_case "API-backed calls receive a positive estimated cost"
if ! declare -F estimate_agent_call_cost >/dev/null 2>&1; then
    test_fail "estimate_agent_call_cost is missing"
elif awk 'BEGIN { exit !(ARGV[1] > 0) }' "$(estimate_agent_call_cost "codex-api" "gpt-test" "A prompt long enough to have tokens")"; then
    test_pass
else
    test_fail "API-backed call was recorded as zero cost"
fi

test_case "subscription-backed calls remain zero rather than fabricating spend"
if declare -F estimate_agent_call_cost >/dev/null 2>&1 &&
   awk 'BEGIN { exit !(ARGV[1] == 0) }' "$(estimate_agent_call_cost "claude" "claude-test" "A prompt")"; then
    test_pass
else
    test_fail "subscription call received a fabricated per-call cost"
fi

test_summary
