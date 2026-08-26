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
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/agent-sync.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/heartbeat.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/state-root.sh"
log() { :; }

test_case "native Agent Teams requires terminal result-capture support"
TIMEOUT=0
OCTOPUS_AGENT_TEAMS=auto
OCTOPUS_FORCE_LEGACY_DISPATCH=false
SUPPORTS_STABLE_AGENT_TEAMS=true
SUPPORTS_HOOK_LAST_MESSAGE=false
is_claude_agent_type() { [[ "$1" == claude* ]]; }
if ! should_use_agent_teams "claude-sonnet" &&
   SUPPORTS_HOOK_LAST_MESSAGE=true should_use_agent_teams "claude-sonnet"; then
    test_pass
else
    test_fail "native dispatch can leave a permanent running row without SubagentStop capture"
fi
TIMEOUT=600

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
heartbeat_source="$(cat "$PROJECT_ROOT/scripts/lib/heartbeat.sh")"
if [[ "$spawn_source" == *'exit_code -ne 124'* ]] && \
   [[ "$spawn_source" == *'exit_code -ne 143'* ]] && \
   [[ "$spawn_source" == *'"$enhanced_prompt" "$_attempt_timeout" "$temp_input"'* ]] && \
   [[ "$heartbeat_source" == *'run_with_timeout "$timeout_secs" "$@" < "$temp_input" > "$raw_output"'* ]] && \
   [[ "$spawn_source" == *'update_agent_status "$agent_type" "running" 0 '*' "$_eff_timeout"'* ]]; then
    test_pass
else
    test_fail "spawn does not yet enforce and report one shared effective timeout"
fi

test_case "bounded agents use the supervised subprocess instead of native Agent Teams"
agent_sync_source="$(cat "$PROJECT_ROOT/scripts/lib/agent-sync.sh")"
agent_utils_source="$(cat "$PROJECT_ROOT/scripts/lib/agent-utils.sh")"
if declare -F octopus_agent_teams_can_honor_timeout >/dev/null 2>&1 && \
   octopus_agent_teams_can_honor_timeout 0 && \
   ! octopus_agent_teams_can_honor_timeout 600 && \
   [[ "$agent_sync_source" == *'octopus_agent_teams_can_honor_timeout "${TIMEOUT:-0}"'* ]] && \
   [[ "$agent_utils_source" == *'octopus_agent_teams_can_honor_timeout "${TIMEOUT:-0}"'* ]] && \
   [[ "$spawn_source" == *'octopus_agent_teams_can_honor_timeout "$_eff_timeout"'* ]] && \
   [[ "$spawn_source" == *'write_agent_status "$agent_type" "running" "$tokens_in" 0 "Dispatched via Agent Teams" "$_eff_timeout"'* ]]; then
    test_pass
else
    test_fail "bounded Agent Teams dispatch can bypass the enforceable provider watchdog"
fi

test_case "isolated non-persistence executor enforces an effective phase budget"
fallback_provider="$TEST_TMP_DIR/fallback-timeout-provider.sh"
cat > "$fallback_provider" <<'EOF'
#!/usr/bin/env bash
sleep 2
printf 'FALLBACK_COMPLETED\n'
EOF
chmod +x "$fallback_provider"
build_provider_env() { PROVIDER_ENV_ARRAY=(); }
octopus_persistence_diagnostic() { :; }
fallback_timeout=$(OCTOPUS_TANGLE_TIMEOUT=4 octopus_effective_agent_timeout 1 tangle implementer)
fallback_started=$(date +%s)
set +e
fallback_output=$(octopus_run_provider_without_persistence \
    claude "fallback prompt" "$fallback_timeout" "$fallback_provider")
fallback_rc=$?
set -e
fallback_elapsed=$(( $(date +%s) - fallback_started ))
if [[ "$fallback_timeout" == "4" ]] && [[ "$fallback_rc" -eq 0 ]] && \
   [[ "$fallback_output" == "FALLBACK_COMPLETED" ]] && [[ "$fallback_elapsed" -ge 2 ]]; then
    test_pass
else
    test_fail "isolated non-persistence executor bypassed the effective tangle timeout floor"
fi

test_case "non-persistence fallback terminates work beyond the effective timeout"
timeout_provider="$TEST_TMP_DIR/fallback-timeout-enforcement.sh"
cat > "$timeout_provider" <<'EOF'
#!/usr/bin/env bash
sleep 6
printf 'SHOULD_NOT_COMPLETE\n'
EOF
chmod +x "$timeout_provider"
timeout_rc=0
octopus_run_provider_without_persistence \
    claude "timeout prompt" "$fallback_timeout" "$timeout_provider" \
    >/dev/null 2>&1 || timeout_rc=$?
if [[ "$timeout_rc" -eq 124 || "$timeout_rc" -eq 143 ]]; then
    test_pass
else
    test_fail "fallback executor did not enforce the effective timeout (rc=$timeout_rc)"
fi

test_summary
