#!/usr/bin/env bash
# Regression checks for #869: one wall-clock budget must cover all auth retries.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "agent timeout budget"

# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/spawn.sh"
log() { :; }

test_case "tangle implementers receive the phase timeout floor"
if declare -F octopus_effective_agent_timeout >/dev/null 2>&1 && \
   [[ "$(octopus_effective_agent_timeout 600 tangle implementer)" == "1200" ]] && \
   [[ "$(OCTOPUS_TANGLE_TIMEOUT=1500 octopus_effective_agent_timeout 600 tangle implementer)" == "1500" ]] && \
   [[ "$(OCTOPUS_TANGLE_TIMEOUT=invalid octopus_effective_agent_timeout 600 tangle implementer)" == "1200" ]] && \
   [[ "$(octopus_effective_agent_timeout 0 tangle implementer)" == "0" ]] && \
   [[ "$(octopus_effective_agent_timeout 600 probe researcher)" == "600" ]]; then
    test_pass
else
    test_fail "effective timeout helper is missing or does not preserve phase/unlimited semantics"
fi

test_case "retry attempts receive only the remaining wall-clock budget"
if declare -F octopus_timeout_remaining >/dev/null 2>&1 && \
   [[ "$(octopus_timeout_remaining 160 100)" == "60" ]] && \
   ! octopus_timeout_remaining 100 100 >/dev/null 2>&1 && \
   ! octopus_timeout_remaining 90 100 >/dev/null 2>&1; then
    test_pass
else
    test_fail "deadline helper did not shrink or expire the retry budget"
fi

test_case "spawn retry loop excludes timed-out attempts and reports effective timeout"
spawn_source="$(cat "$PROJECT_ROOT/scripts/lib/spawn.sh")"
if [[ "$spawn_source" == *'exit_code -ne 124'* ]] && \
   [[ "$spawn_source" == *'exit_code -ne 143'* ]] && \
   [[ "$spawn_source" == *'run_with_timeout "$_attempt_timeout"'* ]] && \
   [[ "$spawn_source" == *'update_agent_status "$agent_type" "running" 0 0.0 "$_eff_timeout"'* ]]; then
    test_pass
else
    test_fail "spawn does not yet enforce and report one shared effective timeout"
fi

test_summary
