#!/usr/bin/env bash
# Tests for the SubagentStop gate hook (quality/cost/verdict pre-screen).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "SubagentStop gate"

HOOK="$PROJECT_ROOT/hooks/subagent-stop-gate.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

run_hook() {
    local payload="$1"; shift
    printf '%s\n' "$payload" | OCTOPUS_WORKSPACE="$TMP_DIR" "$@" bash "$HOOK"
}

USAGE_LOG="$TMP_DIR/usage/subagent-usage.jsonl"

test_case "logs usage record with provider attribution from agent_type"
run_hook '{"agent_id":"a1","agent_type":"codex-research","last_assistant_message":"## Findings\n- OAuth flow verified, SUCCESS"}' env >/dev/null
if [[ -f "$USAGE_LOG" ]] && grep -q '"provider": "codex"' "$USAGE_LOG"; then
    test_pass
else
    test_fail "expected usage log with provider codex, got: $(cat "$USAGE_LOG" 2>/dev/null || echo '<missing>')"
fi

test_case "quality score is a bounded integer"
score=$(python3 -c "
import json
r = [json.loads(l) for l in open('$USAGE_LOG')][-1]
print(r['quality'])")
if [[ "$score" =~ ^[0-9]+$ ]] && (( score >= 0 && score <= 100 )); then
    test_pass
else
    test_fail "expected 0-100 integer quality score, got: $score"
fi

test_case "claude-sdk agent_type attributes to claude-sdk, not claude"
run_hook '{"agent_id":"a2","agent_type":"claude-sdk-agent","last_assistant_message":"done"}' env >/dev/null
if grep -q '"provider": "claude-sdk"' "$USAGE_LOG"; then
    test_pass
else
    test_fail "expected provider claude-sdk in usage log"
fi

test_case "non-strict mode never blocks a malformed verdict"
output=$(run_hook '{"agent_id":"a3","agent_type":"agy","last_assistant_message":"## Verdict\nno clear outcome here"}' env)
if [[ -z "$output" ]]; then
    test_pass
else
    test_fail "expected empty output (allow), got: $output"
fi

test_case "strict mode blocks a verdict block without a verdict token"
output=$(run_hook '{"agent_id":"a4","agent_type":"agy","last_assistant_message":"## Verdict\nno clear outcome here"}' env OCTOPUS_SUBAGENT_GATE_STRICT=true)
if [[ "$output" == *'"decision": "block"'* && "$output" == *"verdict"* ]]; then
    test_pass
else
    test_fail "expected block decision for malformed verdict, got: ${output:-<empty>}"
fi

test_case "strict mode allows a well-formed verdict"
output=$(run_hook '{"agent_id":"a5","agent_type":"agy","last_assistant_message":"## Verdict\nAPPROVE — implementation is sound and tested."}' env OCTOPUS_SUBAGENT_GATE_STRICT=true)
if [[ -z "$output" ]]; then
    test_pass
else
    test_fail "expected allow for APPROVE verdict, got: $output"
fi

test_case "strict mode enforces the quality floor"
output=$(run_hook '{"agent_id":"a6","agent_type":"codex","last_assistant_message":"err"}' env OCTOPUS_SUBAGENT_GATE_STRICT=true OCTOPUS_SUBAGENT_MIN_QUALITY=50)
if [[ "$output" == *'"decision": "block"'* && "$output" == *"quality score"* ]]; then
    test_pass
else
    test_fail "expected block below quality floor, got: ${output:-<empty>}"
fi

test_case "empty stdin exits 0 without writing"
before=$(wc -l < "$USAGE_LOG")
printf '' | OCTOPUS_WORKSPACE="$TMP_DIR" bash "$HOOK"
after=$(wc -l < "$USAGE_LOG")
if [[ "$before" == "$after" ]]; then
    test_pass
else
    test_fail "empty input should not append usage records"
fi

test_summary
