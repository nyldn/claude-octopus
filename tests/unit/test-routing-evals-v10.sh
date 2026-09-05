#!/usr/bin/env bash
# Deterministic v10 routing and Fable dispatch-gate evaluations.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "v10 routing evaluations"

PROFILE_LIB="$PROJECT_ROOT/scripts/lib/execution-profile.sh"
FABLE_LIB="$PROJECT_ROOT/scripts/lib/fable5.sh"
DISPATCH_LIB="$PROJECT_ROOT/scripts/lib/dispatch.sh"
CASES="$PROJECT_ROOT/data/routing/v10-eval-cases.json"

test_case "routing evaluation fixture is valid v10 JSON"
if jq -e '.schema_version == "10.0" and (.cases | length >= 9)' "$CASES" >/dev/null; then
    test_pass
else
    test_fail "routing fixture is missing or invalid"
fi

while IFS= read -r case_json; do
    id="$(jq -r '.id' <<< "$case_json")"
    prompt="$(jq -r '.prompt' <<< "$case_json")"
    role="$(jq -r '.role' <<< "$case_json")"
    phase="$(jq -r '.phase' <<< "$case_json")"
    policy="$(jq -r '.policy' <<< "$case_json")"
    user_pin="$(jq -r '.user_pin // ""' <<< "$case_json")"
    project_pin="$(jq -r '.project_pin // ""' <<< "$case_json")"
    author_model="$(jq -r '.author_model // ""' <<< "$case_json")"
    candidate_verifier="$(jq -r '.candidate_verifier // ""' <<< "$case_json")"
    requires_independent="$(jq -r '.requires_independent // false' <<< "$case_json")"
    expected_class="$(jq -r '.expected_class' <<< "$case_json")"
    expected_provider="$(jq -r '.expected_provider' <<< "$case_json")"
    expected_model="$(jq -r '.expected_model' <<< "$case_json")"
    expected_reason="$(jq -r '.expected_reason' <<< "$case_json")"
    expected_coverage="$(jq -r '.expected_coverage // "not-required"' <<< "$case_json")"

    test_case "eval case: $id"
    actual_class="$(bash -c 'source "$1"; octo_route_task_class "$2" "$3" "$4"' _ "$PROFILE_LIB" "$prompt" "$role" "$phase")"
    actual_decision="$(bash -c 'source "$1"; octo_route_decision "$2" "$3" "$4" "$5" "$6" "$7" "$8"' _ \
        "$PROFILE_LIB" "$actual_class" "$policy" "$user_pin" "$project_pin" \
        "$requires_independent" "$author_model" "$candidate_verifier")"
    if [[ "$actual_class" == "$expected_class" ]] &&
       jq -e --arg provider "$expected_provider" --arg model "$expected_model" \
         --arg reason "$expected_reason" --arg coverage "$expected_coverage" \
         '.provider == $provider and .model == $model and .reason == $reason and .coverage == $coverage' \
         <<< "$actual_decision" >/dev/null; then
        test_pass
    else
        test_fail "expected $expected_class/$expected_provider/$expected_model/$expected_reason/$expected_coverage; got $actual_class/$actual_decision"
    fi
done < <(jq -c '.cases[]' "$CASES")

test_case "Fable input gate accepts the default byte ceiling exactly"
if bash -c 'source "$1"; fable5_prompt_within_budget 524288' _ "$FABLE_LIB"; then
    test_pass
else
    test_fail "524288 bytes must be accepted by the default ceiling"
fi

test_case "Fable input gate rejects a prompt one byte over the ceiling"
set +e
bash -c 'source "$1"; fable5_prompt_within_budget 524289' _ "$FABLE_LIB"
over_rc=$?
set -e
if [[ "$over_rc" -eq 1 ]]; then
    test_pass
else
    test_fail "524289 bytes must be rejected with status 1, got $over_rc"
fi

test_case "Fable input gate rejects an invalid configured ceiling"
set +e
OCTOPUS_FABLE5_MAX_INPUT_BYTES=invalid bash -c 'source "$1"; fable5_prompt_within_budget 1' _ "$FABLE_LIB"
gate_rc=$?
set -e
if [[ "$gate_rc" -eq 2 ]]; then
    test_pass
else
    test_fail "invalid ceiling must return 2, got $gate_rc"
fi

test_case "dispatch prompt measurement counts UTF-8 bytes rather than characters"
byte_count="$(bash -c 'source "$1"; octo_prompt_byte_length "éé"' _ "$DISPATCH_LIB")"
if [[ "$byte_count" == 4 ]]; then
    test_pass
else
    test_fail "expected two UTF-8 characters to measure 4 bytes, got ${byte_count:-<empty>}"
fi

test_case "prompt byte measurement is owned by the shared agent spec"
agent_spec_bytes="$(bash -c 'source "$1/scripts/lib/agent-spec.sh"; octo_prompt_byte_length "éé"' _ "$PROJECT_ROOT")"
if [[ "$agent_spec_bytes" == 4 ]]; then
    test_pass
else
    test_fail "expected agent-spec to measure two UTF-8 characters as 4 bytes, got ${agent_spec_bytes:-<empty>}"
fi

test_case "retain-current never claims independent review coverage"
retain_decision="$(bash -c 'source "$1"; octo_route_decision review off "" "" true gpt-5.6-sol ""' _ "$PROFILE_LIB")"
if jq -e '.model == "retain-current" and .coverage == "degraded-verifier-unresolved"' <<< "$retain_decision" >/dev/null; then
    test_pass
else
    test_fail "unresolved verifier claimed coverage: $retain_decision"
fi

for route_case in \
    'composer-2.5|cursor-agent' \
    'cursor-agent-auto|cursor-agent' \
    'cursor-grok-4.6-high|cursor-agent' \
    'grok-4-fast|grok'; do
    route_model="${route_case%%|*}"
    expected_provider="${route_case#*|}"
    test_case "model route: $route_model uses $expected_provider"
    route_decision="$(bash -c 'source "$1"; octo_route_decision balanced off "$2" "" false "" ""' _ "$PROFILE_LIB" "$route_model")"
    if jq -e --arg provider "$expected_provider" --arg model "$route_model" \
        '.provider == $provider and .model == $model' <<< "$route_decision" >/dev/null; then
        test_pass
    else
        test_fail "expected $route_model to use $expected_provider, got $route_decision"
    fi
done

test_case "both synchronous and background dispatch pass byte counts to command routing"
if grep -q 'octo_prompt_byte_length.*enhanced_prompt' "$PROJECT_ROOT/scripts/lib/agent-sync.sh" &&
   grep -q 'octo_prompt_byte_length.*enhanced_prompt' "$PROJECT_ROOT/scripts/lib/spawn.sh"; then
    test_pass
else
    test_fail "one or more dispatch paths still use a character count"
fi

test_case "oversized Fable escalation falls back before dispatch"
decision="$(OCTOPUS_FABLE5_ROUTING=escalate bash -c '
  source "$1"
  fable5_resolve_dispatch_model claude-opus-5 architect claude-opus define 524289
' _ "$FABLE_LIB")"
if jq -e '.requested_model == "claude-fable-5-1" and .resolved_model == "claude-opus-5" and .reason == "prompt-budget-fallback"' <<< "$decision" >/dev/null; then
    test_pass
else
    test_fail "oversized Fable decision was not a pre-dispatch Opus fallback: $decision"
fi

test_case "refusal recovery selects the non-Fable fallback"
decision="$(bash -c 'source "$1"; fable5_recovery_decision claude-fable-5 refusal' _ "$FABLE_LIB")"
if jq -e '.resolved_model == "claude-opus-5" and .reason == "refusal-fallback"' <<< "$decision" >/dev/null; then
    test_pass
else
    test_fail "refusal recovery was not auditable: $decision"
fi

test_case "quota exhaustion selects the non-Fable fallback"
decision="$(bash -c 'source "$1"; fable5_recovery_decision claude-fable-5 quota-exhausted' _ "$FABLE_LIB")"
if jq -e '.resolved_model == "claude-opus-5" and .reason == "quota-fallback"' <<< "$decision" >/dev/null; then
    test_pass
else
    test_fail "quota recovery was not auditable: $decision"
fi

test_case "model resolver applies eval class only when no higher-precedence route exists"
empty_home="$TEST_TMP_DIR/empty-home"
mkdir -p "$empty_home"
resolved="$(HOME="$empty_home" OCTOPUS_ROUTING_POLICY=eval OCTOPUS_TASK_CLASS=mechanical \
  PLUGIN_DIR="$PROJECT_ROOT" bash -c '
    log(){ :; }
    source "$1/scripts/lib/models.sh"
    source "$1/scripts/lib/model-resolver.sh"
    resolve_octopus_model codex codex-standard develop implementer
  ' _ "$PROJECT_ROOT")"
if [[ "$resolved" == "gpt-5.6-luna" ]]; then
    test_pass
else
    test_fail "mechanical eval route should resolve Luna, got $resolved"
fi

test_case "explicit provider model pin outranks eval class in the resolver"
resolved="$(HOME="$empty_home" OCTOPUS_ROUTING_POLICY=eval OCTOPUS_TASK_CLASS=mechanical \
  OCTOPUS_CODEX_MODEL=gpt-5.6-sol PLUGIN_DIR="$PROJECT_ROOT" bash -c '
    log(){ :; }
    source "$1/scripts/lib/models.sh"
    source "$1/scripts/lib/model-resolver.sh"
    resolve_octopus_model codex codex-standard develop implementer
  ' _ "$PROJECT_ROOT")"
if [[ "$resolved" == "gpt-5.6-sol" ]]; then
    test_pass
else
    test_fail "explicit model pin must outrank eval route, got $resolved"
fi

test_case "recorded project eval policy applies before generic model defaults"
policy_home="$TEST_TMP_DIR/policy-home"
mkdir -p "$policy_home/.claude-octopus/config"
printf '%s\n' '{"routing":{"policy":"eval"},"providers":{"codex":{"default":"gpt-5.6-sol"}}}' \
  > "$policy_home/.claude-octopus/config/providers.json"
resolved="$(HOME="$policy_home" OCTOPUS_TASK_CLASS=mechanical PLUGIN_DIR="$PROJECT_ROOT" bash -c '
    log(){ :; }
    source "$1/scripts/lib/models.sh"
    source "$1/scripts/lib/model-resolver.sh"
    resolve_octopus_model codex codex-standard develop implementer
  ' _ "$PROJECT_ROOT")"
if [[ "$resolved" == "gpt-5.6-luna" ]]; then
    test_pass
else
    test_fail "recorded eval policy did not select Luna before generic default: $resolved"
fi

test_case "explicit project role route outranks recorded eval policy"
printf '%s\n' '{"routing":{"policy":"eval","roles":{"implementer":{"provider":"codex","model":"gpt-5.6-sol"}}},"providers":{"codex":{"default":"gpt-5.6-terra"}}}' \
  > "$policy_home/.claude-octopus/config/providers.json"
resolved="$(HOME="$policy_home" OCTOPUS_TASK_CLASS=mechanical PLUGIN_DIR="$PROJECT_ROOT" bash -c '
    log(){ :; }
    source "$1/scripts/lib/models.sh"
    source "$1/scripts/lib/model-resolver.sh"
    resolve_octopus_model codex codex-standard develop implementer
  ' _ "$PROJECT_ROOT")"
if [[ "$resolved" == "gpt-5.6-sol" ]]; then
    test_pass
else
    test_fail "explicit project role route must outrank eval policy: $resolved"
fi

test_case "oversized Fable prompt is absent from the generated provider command"
command="$(env OCTOPUS_FABLE5_ROUTING=escalate SUPPORTS_SDK_MODEL_CAPS=false \
  SUPPORTS_OPUS_5=true SUPPORTS_OPUS_4_8=true SUPPORTS_OPUS_4_7=true \
  SUPPORTS_EFFORT_COMMAND=false SUPPORTS_XHIGH_EFFORT=false \
  PLUGIN_DIR="$PROJECT_ROOT" bash -c '
    log(){ :; }
    export _BARE_OPT= OCTOPUS_PLATFORM=Linux
    source "$1/scripts/lib/model-resolver.sh"
    source "$1/scripts/lib/agents.sh"
    source "$1/scripts/lib/dispatch.sh"
    get_agent_command claude-opus define architect 524289
  ' _ "$PROJECT_ROOT" 2>/dev/null)"
if [[ "$command" == *"--model claude-opus-5"* && "$command" != *"claude-fable-5"* ]]; then
    test_pass
else
    test_fail "oversized prompt serialized a Fable dispatch: $command"
fi

test_case "single Fable seat cap survives command substitutions in one durable run"
cap_workspace="$TEST_TMP_DIR/fable-cap-workspace"
mkdir -p "$cap_workspace"
cap_decisions="$(WORKSPACE_DIR="$cap_workspace" OCTOPUS_RUN_ID=cap-run \
  OCTOPUS_FABLE5_ROUTING=escalate bash -c '
    source "$1/scripts/lib/run-contract.sh"
    source "$1/scripts/lib/fable5.sh"
    first="$(fable5_resolve_dispatch_model claude-opus-5 architect claude-opus define 100)"
    second="$(fable5_resolve_dispatch_model claude-opus-5 strategist claude-opus define 100)"
    printf "%s\n%s\n" "$first" "$second"
  ' _ "$PROJECT_ROOT")"
if [[ "$(sed -n '1p' <<< "$cap_decisions" | jq -r '.resolved_model + ":" + .reason')" == "claude-fable-5-1:fable-selected" ]] &&
   [[ "$(sed -n '2p' <<< "$cap_decisions" | jq -r '.resolved_model + ":" + .reason')" == "claude-opus-5:seat-cap-fallback" ]]; then
    test_pass
else
    test_fail "durable one-seat cap was not enforced: $cap_decisions"
fi

test_case "Fable dispatch preview does not consume the durable one-seat claim"
preview_workspace="$TEST_TMP_DIR/fable-preview-workspace"
mkdir -p "$preview_workspace"
preview_decisions="$(WORKSPACE_DIR="$preview_workspace" OCTOPUS_RUN_ID=preview-run \
  OCTOPUS_FABLE5_ROUTING=escalate bash -c '
    source "$1/scripts/lib/run-contract.sh"
    source "$1/scripts/lib/fable5.sh"
    preview="$(OCTOPUS_DISPATCH_PREVIEW=true fable5_resolve_dispatch_model claude-opus-5 architect claude-opus define 100)"
    actual="$(fable5_resolve_dispatch_model claude-opus-5 architect claude-opus define 100)"
    printf "%s\n%s\n" "$preview" "$actual"
  ' _ "$PROJECT_ROOT")"
if [[ "$(sed -n '1p' <<< "$preview_decisions" | jq -r '.resolved_model + ":" + .reason')" == "claude-fable-5-1:fable-preview" ]] &&
   [[ "$(sed -n '2p' <<< "$preview_decisions" | jq -r '.resolved_model + ":" + .reason')" == "claude-fable-5-1:fable-selected" ]]; then
    test_pass
else
    test_fail "preview consumed or misreported the Fable seat: $preview_decisions"
fi

test_summary
