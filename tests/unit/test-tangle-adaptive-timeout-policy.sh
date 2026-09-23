#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
log() { :; }
source "$PROJECT_ROOT/scripts/lib/heartbeat.sh"
source "$PROJECT_ROOT/scripts/lib/spawn.sh"
test_suite "Tangle adaptive timeout policy"
cleanup_env() { unset OCTOPUS_TANGLE_TIMEOUT OCTOPUS_TIMEOUT_EXPLICIT OCTOPUS_TANGLE_STALL_WINDOW OCTOPUS_TANGLE_STALL_POLL_SECS; }
trap cleanup_env EXIT INT TERM
cleanup_env

test_case "Tangle implementer is unbounded by default"
[[ "$(octopus_effective_agent_timeout 600 tangle implementer)" == 0 ]] && test_pass || test_fail "default Tangle timeout was not zero"

test_case "explicit CLI timeout remains bounded"
OCTOPUS_TIMEOUT_EXPLICIT=1
[[ "$(octopus_effective_agent_timeout 900 tangle implementer)" == 900 ]] && test_pass || test_fail "explicit timeout was ignored"
unset OCTOPUS_TIMEOUT_EXPLICIT

test_case "Tangle-specific timeout overrides default policy"
OCTOPUS_TANGLE_TIMEOUT=1500
[[ "$(octopus_effective_agent_timeout 600 tangle implementer)" == 1500 ]] && test_pass || test_fail "Tangle timeout override was ignored"
unset OCTOPUS_TANGLE_TIMEOUT

test_case "explicit Tangle timeout zero remains unbounded"
OCTOPUS_TANGLE_TIMEOUT=0
[[ "$(octopus_effective_agent_timeout 600 tangle implementer)" == 0 ]] && test_pass || test_fail "explicit zero timeout was not preserved"
unset OCTOPUS_TANGLE_TIMEOUT

test_case "non-Tangle workflow keeps configured timeout"
[[ "$(octopus_effective_agent_timeout 600 review reviewer)" == 600 ]] && test_pass || test_fail "non-Tangle timeout changed"

test_case "default implementer stall window is 900 seconds"
[[ "$(octopus_tangle_stall_window implementer)" == 900 ]] && test_pass || test_fail "unexpected implementer stall window"

test_case "default heavy implementer stall window is 1500 seconds"
[[ "$(octopus_tangle_stall_window implementer-heavy)" == 1500 ]] && test_pass || test_fail "unexpected heavy stall window"

test_case "stall window remains configurable"
OCTOPUS_TANGLE_STALL_WINDOW=42
[[ "$(octopus_tangle_stall_window implementer)" == 42 ]] && test_pass || test_fail "stall override was ignored"
unset OCTOPUS_TANGLE_STALL_WINDOW

test_case "zero stall window fails closed"
OCTOPUS_TANGLE_STALL_WINDOW=0
if octopus_tangle_stall_window implementer >/dev/null 2>&1; then test_fail "zero stall window was accepted"; else test_pass; fi
unset OCTOPUS_TANGLE_STALL_WINDOW

test_case "stall poll interval remains configurable"
OCTOPUS_TANGLE_STALL_POLL_SECS=7
[[ "$(octopus_tangle_stall_poll_secs)" == 7 ]] && test_pass || test_fail "stall poll override was ignored"
unset OCTOPUS_TANGLE_STALL_POLL_SECS

test_case "invalid Tangle timeout fails closed"
OCTOPUS_TANGLE_TIMEOUT=invalid
if octopus_effective_agent_timeout 600 tangle implementer >/dev/null 2>&1; then test_fail "invalid timeout was accepted"; else test_pass; fi
unset OCTOPUS_TANGLE_TIMEOUT

test_case "spawn fails closed when timeout policy resolution fails"
if grep -q 'if ! _eff_timeout=$(octopus_effective_agent_timeout' "$PROJECT_ROOT/scripts/lib/spawn.sh" \
   && grep -q 'Invalid timeout supervision configuration' "$PROJECT_ROOT/scripts/lib/spawn.sh"; then
    test_pass
else
    test_fail "spawn does not fail closed on invalid timeout policy"
fi

test_case "CLI parser marks explicit timeout"
grep -q 'OCTOPUS_TIMEOUT_EXPLICIT=1' "$PROJECT_ROOT/scripts/orchestrate.sh" && test_pass || test_fail "CLI explicit-timeout marker missing"

test_case "stall exit bypasses auth retry"
grep -q 'exit_code -ne 76' "$PROJECT_ROOT/scripts/lib/spawn.sh" && test_pass || test_fail "stall exit can consume auth retry"

test_case "spawn result reporting recognizes stalled exit code"
grep -q 'STALLED - PARTIAL RESULTS (exit code: 76)' "$PROJECT_ROOT/scripts/lib/spawn.sh" && test_pass || test_fail "stalled status reporting missing"

test_summary
