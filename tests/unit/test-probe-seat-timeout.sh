#!/usr/bin/env bash
# Regression checks for probe seats killed at the 600s TIMEOUT default while
# OCTOPUS_AGENT_TIMEOUT asked for more: the probe seat budget, the probe-single
# runner and the probe progress watchdog must resolve one budget with the
# precedence run_agent_sync uses. test-spawn-run-contract.sh covers the
# spawn_agent seat itself.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "probe seat timeout"

# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/spawn.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/agent-sync.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/heartbeat.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/workflows.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/session.sh"
log() { :; }

unset OCTOPUS_AGENT_TIMEOUT OCTOPUS_TIMEOUT_EXPLICIT OCTOPUS_TIMEOUT_EXPLICIT_SECS OCTOPUS_TANGLE_TIMEOUT

test_case "probe seats resolve OCTOPUS_AGENT_TIMEOUT, then --timeout, then TIMEOUT"
if [[ "$(octopus_effective_agent_timeout 600 probe researcher)" == "600" ]] && \
   [[ "$(OCTOPUS_AGENT_TIMEOUT=1200 octopus_effective_agent_timeout 600 probe researcher)" == "1200" ]] && \
   [[ "$(OCTOPUS_TIMEOUT_EXPLICIT=1 OCTOPUS_TIMEOUT_EXPLICIT_SECS=900 octopus_effective_agent_timeout 600 probe researcher)" == "900" ]] && \
   [[ "$(OCTOPUS_TIMEOUT_EXPLICIT=1 OCTOPUS_TIMEOUT_EXPLICIT_SECS=900 OCTOPUS_AGENT_TIMEOUT=1200 octopus_effective_agent_timeout 600 probe researcher)" == "1200" ]] && \
   [[ "$(OCTOPUS_AGENT_TIMEOUT=01200 octopus_effective_agent_timeout 600 probe researcher)" == "1200" ]] && \
   [[ "$(OCTOPUS_AGENT_TIMEOUT=abc octopus_effective_agent_timeout 600 probe researcher)" == "600" ]] && \
   ! OCTOPUS_AGENT_TIMEOUT=99999999999 octopus_effective_agent_timeout 600 probe researcher >/dev/null 2>&1; then
    test_pass
else
    test_fail "probe seat budget is not OCTOPUS_AGENT_TIMEOUT > --timeout > TIMEOUT"
fi

test_case "workflows that wait on TIMEOUT keep it"
# Their collectors stop seats at TIMEOUT, so a larger seat budget would only
# move the kill from the provider watchdog to the collector.
if [[ "$(OCTOPUS_AGENT_TIMEOUT=1200 octopus_effective_agent_timeout 600 review reviewer)" == "600" ]] && \
   [[ "$(OCTOPUS_AGENT_TIMEOUT=1200 octopus_effective_agent_timeout 600 tangle implementer)" == "0" ]] && \
   [[ "$(OCTOPUS_AGENT_TIMEOUT=1200 octopus_effective_agent_timeout 600 tangle reviewer)" == "600" ]]; then
    test_pass
else
    test_fail "OCTOPUS_AGENT_TIMEOUT leaked into a workflow whose collector waits on TIMEOUT"
fi

probe_single_budget_fixture() (
    local fixture_root="$TEST_TMP_DIR/probe-single-budget"
    RESULTS_DIR="$fixture_root/results"; LOGS_DIR="$fixture_root/logs"
    mkdir -p "$fixture_root/project" "$RESULTS_DIR" "$LOGS_DIR"
    PROJECT_ROOT="$fixture_root/project"
    budgets="$fixture_root/budgets"; : > "$budgets"
    SUPPORTS_AGENT_TYPE_ROUTING=false; SUPPORTS_STABLE_AUTH=true
    OCTOPUS_PERSONA_PACKS=off; OCTOPUS_BACKEND=api
    PROVIDER_ENV_ARRAY=()
    preflight_check() { return 0; }
    classify_task() { printf 'research'; }; match_routing_rule() { return 1; }
    apply_persona() { printf '%s' "$2"; }
    enforce_context_budget() { printf '%s' "$1"; }
    octo_routing_policy() { printf 'off'; }
    get_agent_model() { printf 'fixture-model'; }
    get_agent_command() { printf '/bin/true'; }
    validate_agent_command() { return 0; }; record_agent_call() { :; }
    update_metrics() { :; }; bridge_register_task() { :; }
    write_agent_status() { :; }
    build_provider_env() { PROVIDER_ENV_ARRAY=(); }
    octo_prompt_byte_length() { printf '1'; }
    record_outcome() { :; }; record_run_pattern() { :; }
    octo_estimate_tokens_for_file() { printf '1'; }
    classify_agent_output() { printf 'ok:'; }
    update_agent_status() { printf 'status:%s:%s\n' "$2" "$5" >> "$budgets"; }
    octopus_capture_provider_output() {
        printf 'provider:%s\n' "$2" >> "$budgets"
        printf 'fixture output\n' > "$4"
        : > "$5"
    }
    probe_single_agent claude-sonnet 'Probe fixture' budget original >/dev/null || return 1
    cat "$budgets"
)

test_case "probe-single gives the provider and its status rows the resolved budget"
budget_rows="$(TIMEOUT=600 OCTOPUS_AGENT_TIMEOUT=1200 probe_single_budget_fixture 2>/dev/null || true)"
if [[ "$budget_rows" == $'status:running:1200\nprovider:1200\nstatus:completed:1200' ]]; then
    test_pass
else
    test_fail "probe-single used another budget: $(tr '\n' ' ' <<< "${budget_rows:-<none>}")"
fi

test_case "the probe progress watchdog waits for the seat budget"
CYAN=""; GREEN=""; YELLOW=""; RED=""; MAGENTA=""; NC=""
_BOX_TOP=""; _BOX_BOT=""; _DASH=""
RESULTS_DIR="$TEST_TMP_DIR/watchdog-results"
mkdir -p "$RESULTS_DIR"
sleep 30 &
straggler_pid=$!
watchdog_started=$(date +%s)
watchdog_output="$(TIMEOUT=1 OCTOPUS_PROGRESS_GRACE=0 OCTOPUS_AGENT_TIMEOUT=3 \
    display_rich_progress watchdog 1 "$watchdog_started" "$straggler_pid" 2>&1)"
watchdog_elapsed=$(( $(date +%s) - watchdog_started ))
kill "$straggler_pid" 2>/dev/null || true
wait "$straggler_pid" 2>/dev/null || true
if [[ "$watchdog_output" == *"after 3s (timeout 3s + grace)"* && "$watchdog_elapsed" -ge 3 ]]; then
    test_pass
else
    test_fail "watchdog stopped after ${watchdog_elapsed}s instead of the 3s seat budget"
fi

test_summary
