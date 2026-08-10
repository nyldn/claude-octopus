#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Provider router canonical compound IDs"

TEST_TMP_DIR="${TEST_TMP_DIR:-/tmp/octopus-tests-$$}"
trap 'rm -rf "$TEST_TMP_DIR"' EXIT INT TERM
export HOME="$TEST_TMP_DIR/home"
export WORKSPACE_DIR="$TEST_TMP_DIR/workspace"
export OCTO_CB_COOLDOWN_SECS=300
mkdir -p "$HOME" "$WORKSPACE_DIR"
source "$PROJECT_ROOT/scripts/provider-router.sh"

test_case "metrics preserve compound provider identities"
cat > "$WORKSPACE_DIR/metrics-session.json" <<'EOF'
{
  "phases": [{"agents": [
    {"status":"completed","agent_type":"claude-sdk-reviewer","duration_ms":100,"estimated_cost_usd":1},
    {"status":"completed","agent_type":"openai-compatible-agent","duration_ms":200,"estimated_cost_usd":2},
    {"status":"completed","agent_type":"cursor-agent","duration_ms":300,"estimated_cost_usd":3},
    {"status":"completed","agent_type":"commandcode-research","duration_ms":400,"estimated_cost_usd":4}
  ]}]
}
EOF
if build_provider_stats && \
   [[ "$(jq -r '.providers | keys | sort | join(",")' "$WORKSPACE_DIR/.provider-stats.json")" == "claude-sdk,commandcode,cursor-agent,openai-compatible-agent" ]]; then
    test_pass
else
    test_fail "compound provider metrics were collapsed: $(cat "$WORKSPACE_DIR/.provider-stats.json" 2>/dev/null || true)"
fi

test_case "cooldown filtering canonicalizes compound agent variants"
is_provider_available() {
    [[ "$1" != "claude-sdk" ]]
}
filtered=$(filter_available_providers claude-sdk-reviewer commandcode-research)
if [[ "$filtered" == "commandcode-research" ]]; then
    test_pass
else
    test_fail "compound cooldown filtering failed: $filtered"
fi

test_case "circuit breaker reports registry-backed dispatch providers at runtime"
source "$PROJECT_ROOT/scripts/lib/provider-registry.sh"
mkdir -p "$_PROVIDER_STATE_DIR"
printf '%s\n' "$(( $(date +%s) + 60 ))" > "$_PROVIDER_STATE_DIR/agy.cooldown"
status=$(get_circuit_breaker_status)
rm -f "$_PROVIDER_STATE_DIR/agy.cooldown"
if [[ "$status" == *"agy: OPEN"* || "$status" == *"agy: half-open"* ]] && [[ -n "$(octo_provider_ids dispatch)" ]]; then test_pass; else test_fail "runtime circuit breaker omitted Antigravity: $status"; fi

test_summary
