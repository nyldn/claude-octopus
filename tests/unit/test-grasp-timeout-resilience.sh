#!/usr/bin/env bash
# Regression checks for grasp runs where every seat hit a hardcoded 300s cap:
# --timeout must reach run_agent_sync, one failed seat must not abort the phase,
# and a quota-dead agy must not be re-dispatched for each seat.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "grasp timeout resilience"

# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/agent-sync.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/workflows.sh"

test_case "explicit --timeout replaces caller-hardcoded sync timeouts"
unset OCTOPUS_AGENT_TIMEOUT OCTOPUS_TIMEOUT_EXPLICIT OCTOPUS_TIMEOUT_EXPLICIT_SECS
if ! OCTOPUS_TIMEOUT_EXPLICIT_SECS=900 octopus_sync_timeout_override 300 >/dev/null && \
   [[ "$(OCTOPUS_TIMEOUT_EXPLICIT=1 OCTOPUS_TIMEOUT_EXPLICIT_SECS=900 octopus_sync_timeout_override 300)" == "900" ]] && \
   [[ "$(OCTOPUS_TIMEOUT_EXPLICIT=1 OCTOPUS_TIMEOUT_EXPLICIT_SECS=900 octopus_sync_timeout_override 120)" == "900" ]] && \
   ! OCTOPUS_TIMEOUT_EXPLICIT=1 OCTOPUS_TIMEOUT_EXPLICIT_SECS=900 octopus_sync_timeout_override 0 >/dev/null && \
   [[ "$(OCTOPUS_TIMEOUT_EXPLICIT=1 OCTOPUS_TIMEOUT_EXPLICIT_SECS=900 OCTOPUS_AGENT_TIMEOUT=1200 octopus_sync_timeout_override 300)" == "1200" ]] && \
   ! OCTOPUS_TIMEOUT_EXPLICIT=1 OCTOPUS_TIMEOUT_EXPLICIT_SECS=abc octopus_sync_timeout_override 300 >/dev/null && \
   ! OCTOPUS_TIMEOUT_EXPLICIT=1 OCTOPUS_TIMEOUT_EXPLICIT_SECS=0 octopus_sync_timeout_override 300 >/dev/null && \
   ! OCTOPUS_TIMEOUT_EXPLICIT=1 OCTOPUS_TIMEOUT_EXPLICIT_SECS=000 octopus_sync_timeout_override 300 >/dev/null && \
   [[ "$(OCTOPUS_TIMEOUT_EXPLICIT=1 OCTOPUS_TIMEOUT_EXPLICIT_SECS=0600 octopus_sync_timeout_override 300)" == "600" ]]; then
    test_pass
else
    test_fail "sync timeout precedence is not OCTOPUS_AGENT_TIMEOUT > --timeout > caller, with 0 kept unbounded"
fi

test_case "council seats keep their own budget under an explicit --timeout"
# council_seat_timeout also keys the seat reaper; overriding it here would turn
# clean 124 timeouts into watchdog kills and beat per-provider council config.
if ! OCTOPUS_TIMEOUT_EXPLICIT=1 OCTOPUS_TIMEOUT_EXPLICIT_SECS=900 octopus_sync_timeout_override 120 council >/dev/null && \
   [[ "$(OCTOPUS_TIMEOUT_EXPLICIT=1 OCTOPUS_TIMEOUT_EXPLICIT_SECS=900 octopus_sync_timeout_override 300 grasp)" == "900" ]]; then
    test_pass
else
    test_fail "explicit --timeout overrides council's resolved per-seat timeout"
fi

test_case "internal TIMEOUT rewrites do not change the explicit sync budget"
# review.sh sets TIMEOUT=0 for progress supervision; quality.sh resets it to
# 600 in nested processes. Neither may replace the user's --timeout value.
if [[ "$(TIMEOUT=0 OCTOPUS_TIMEOUT_EXPLICIT=1 OCTOPUS_TIMEOUT_EXPLICIT_SECS=900 octopus_sync_timeout_override 120)" == "900" ]] && \
   [[ "$(TIMEOUT=600 OCTOPUS_TIMEOUT_EXPLICIT=1 OCTOPUS_TIMEOUT_EXPLICIT_SECS=900 octopus_sync_timeout_override 300)" == "900" ]]; then
    test_pass
else
    test_fail "the sync override reads the mutable TIMEOUT global instead of the captured --timeout value"
fi

test_case "--timeout parsing exports the captured value"
orchestrate_source="$(cat "$PROJECT_ROOT/scripts/orchestrate.sh")"
if [[ "$orchestrate_source" == *'OCTOPUS_TIMEOUT_EXPLICIT_SECS="$2"; export OCTOPUS_TIMEOUT_EXPLICIT OCTOPUS_TIMEOUT_EXPLICIT_SECS'* ]]; then
    test_pass
else
    test_fail "--timeout does not export OCTOPUS_TIMEOUT_EXPLICIT_SECS"
fi

test_case "run_agent_sync resolves its timeout through the override helper"
agent_sync_source="$(cat "$PROJECT_ROOT/scripts/lib/agent-sync.sh")"
if [[ "$agent_sync_source" == *'_timeout_override="$(octopus_sync_timeout_override "$timeout_secs" "$phase")"'* ]]; then
    test_pass
else
    test_fail "run_agent_sync bypasses octopus_sync_timeout_override"
fi

RESULTS_DIR="$TEST_TMP_DIR/results"
LOGS_DIR="$TEST_TMP_DIR/logs"
CALLS_FILE="$TEST_TMP_DIR/calls"
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

# Mock seats: FAIL_SEATS lists "provider:role" pairs that time out (exit 124).
run_agent_sync() {
    local provider="$1" role="${4:-}"
    printf '%s:%s\n' "$provider" "$role" >> "$CALLS_FILE"
    if [[ " ${FAIL_SEATS:-} " == *" ${provider}:${role} "* ]]; then
        # The real health gate prints a placeholder before failing.
        printf '[Provider %s unavailable: fixture]\n' "$provider"
        return 124
    fi
    printf 'Perspective from %s as %s\n' "$provider" "$role"
}

latest_consensus() {
    ls -t "$RESULTS_DIR"/grasp-consensus-*.md 2>/dev/null | head -1
}

reset_run() {
    rm -f "$RESULTS_DIR"/grasp-consensus-*.md "$CALLS_FILE"
    : > "$CALLS_FILE"
}

test_case "a timed-out constraints seat does not abort grasp under errexit"
reset_run
octo_quota_is_dead() { return 1; }
FAIL_SEATS="claude-sonnet:researcher"
# Run in a subshell with errexit on, matching standalone orchestrate.sh grasp.
# The subshell must be a plain statement: bash ignores set -e inside anything
# that is part of an if/&&/|| condition, which would make this test vacuous.
set +e
(set -e; grasp_define "Define the feature" >/dev/null 2>&1)
grasp_rc=$?
set -e
if [[ "$grasp_rc" -eq 0 && -n "$(latest_consensus)" ]]; then
    test_pass
else
    test_fail "one failed seat discarded the gathered perspectives and wrote no consensus"
fi

test_case "grasp fails loudly when every perspective fails"
reset_run
FAIL_SEATS="codex:backend-architect claude-sonnet:backend-architect agy:researcher claude-sonnet:researcher"
set +e
(set -e; grasp_define "Define the feature" >/dev/null 2>&1)
grasp_rc=$?
set -e
if [[ "$grasp_rc" -eq 1 && -z "$(latest_consensus)" ]]; then
    test_pass
else
    test_fail "grasp wrote a consensus with no perspectives or returned success"
fi

test_case "quota-dead agy is skipped for every grasp seat and Claude synthesizes"
reset_run
FAIL_SEATS=""
octo_quota_is_dead() { [[ "$1" == "agy" ]]; }
if grasp_define "Define the feature" >/dev/null 2>&1 && \
   ! grep -q '^agy:' "$CALLS_FILE" && \
   grep -qx 'claude-sonnet:synthesizer' "$CALLS_FILE" && \
   grep -q 'synthesizer: claude-sonnet' "$(latest_consensus)"; then
    test_pass
else
    test_fail "grasp dispatched a quota-dead agy or skipped Claude consensus: $(tr '\n' ' ' < "$CALLS_FILE")"
fi

test_case "agy is still used when it is not quota-dead"
reset_run
octo_quota_is_dead() { return 1; }
if grasp_define "Define the feature" >/dev/null 2>&1 && \
   grep -qx 'agy:researcher' "$CALLS_FILE" && \
   grep -qx 'agy:synthesizer' "$CALLS_FILE" && \
   grep -q 'synthesizer: agy' "$(latest_consensus)"; then
    test_pass
else
    test_fail "healthy agy was not dispatched: $(tr '\n' ' ' < "$CALLS_FILE")"
fi

test_case "failed agy consensus falls back to Claude synthesis"
reset_run
FAIL_SEATS="agy:synthesizer"
if grasp_define "Define the feature" >/dev/null 2>&1 && \
   grep -qx 'claude-sonnet:synthesizer' "$CALLS_FILE" && \
   grep -q 'synthesizer: claude-sonnet' "$(latest_consensus)"; then
    test_pass
else
    test_fail "agy consensus failure did not fall back to Claude"
fi

test_case "timeout hint names the control that applies"
heartbeat_source="$(cat "$PROJECT_ROOT/scripts/lib/heartbeat.sh")"
if [[ "$heartbeat_source" == *'OCTOPUS_AGENT_TIMEOUT=${recommended_timeout} (${recommended_mins}m; overrides --timeout)'* ]]; then
    test_pass
else
    test_fail "timeout hint still recommends --timeout when OCTOPUS_AGENT_TIMEOUT outranks it"
fi

test_summary
