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
source "$PROJECT_ROOT/scripts/lib/heartbeat.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/state-root.sh"
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

test_case "non-persistence fallback receives and enforces the effective phase budget"
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
if [[ "$spawn_source" == *'"$agent_type" "$enhanced_prompt" "$_eff_timeout" "$cmd"'* ]] && \
   [[ "$fallback_timeout" == "4" ]] && [[ "$fallback_rc" -eq 0 ]] && \
   [[ "$fallback_output" == "FALLBACK_COMPLETED" ]] && [[ "$fallback_elapsed" -ge 2 ]]; then
    test_pass
else
    test_fail "non-persistence dispatch bypassed the effective tangle timeout floor"
fi

test_summary
