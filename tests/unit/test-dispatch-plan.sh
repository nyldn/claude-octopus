#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT_SOURCE="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Immutable dispatch plan"

log() { :; }
PROJECT_ROOT="$TEST_TMP_DIR/project"
PLUGIN_DIR="$TEST_TMP_DIR/plugin"
RESULTS_DIR="$TEST_TMP_DIR/results"
mkdir -p "$PROJECT_ROOT" "$PLUGIN_DIR" "$RESULTS_DIR"
EXPECTED_PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd -P)"
EXPECTED_PLUGIN_ROOT="$(cd "$PLUGIN_DIR" && pwd -P)"

source "$PROJECT_ROOT_SOURCE/scripts/lib/models.sh"
source "$PROJECT_ROOT_SOURCE/scripts/lib/agent-spec.sh"
source "$PROJECT_ROOT_SOURCE/scripts/lib/provider-registry.sh"
source "$PROJECT_ROOT_SOURCE/scripts/lib/execution-profile.sh"
source "$PROJECT_ROOT_SOURCE/scripts/lib/dispatch-plan.sh"

get_provider_context_limit() { printf '198500\n'; }
get_tool_policy() { printf 'read_exec\n'; }
octo_tool_loop_requires_no_tools() { return 0; }
_octo_usage_billing_mode() { printf 'metered\n'; }

PROVIDER_ENV_ARRAY=(env -i "PATH=$PATH" "HOME=$HOME" "OPENAI_API_KEY=super-secret" "TRACEPARENT=trace")

test_case "plan contains one redacted resolved dispatch decision"
plan="$(octo_dispatch_plan_create \
  'codex:openai/gpt-6-astra' review code-reviewer \
  'codex exec --model openai/gpt-6-astra' 'openai/gpt-6-astra' 123456 4096)"
if jq -e \
  --arg project "$EXPECTED_PROJECT_ROOT" --arg plugin "$EXPECTED_PLUGIN_ROOT" '
    .schema_version == 1 and
    .agent_spec == "codex:openai/gpt-6-astra" and
    .provider == "codex" and
    .requested_model == "openai/gpt-6-astra" and
    .canonical_model == "gpt-6-astra" and
    .model_family == "openai" and
    .selection_source == "explicit-agent-spec" and
    .project_root == $project and .plugin_root == $plugin and
    .argv == ["codex","exec","--model","openai/gpt-6-astra"] and
    .credential_names == ["OPENAI_API_KEY"] and
    .environment_names == ["PATH","HOME","OPENAI_API_KEY","TRACEPARENT"] and
    .tool_policy == "none" and
    .budgets.available_input_tokens == 198500 and
    .budgets.prompt_bytes == 4096 and
    .deadline_epoch == 123456 and
    .billing_mode == "metered"
  ' <<<"$plan" >/dev/null && [[ "$plan" != *super-secret* ]]; then
  test_pass
else
  test_fail "dispatch plan omitted, changed, or exposed a secret: $plan"
fi

test_case "consumers load argv without reinterpreting shell syntax"
octo_dispatch_plan_load_argv "$plan"
if [[ "${#OCTO_DISPATCH_PLAN_ARGV[@]}" -eq 4 ]] &&
   [[ "${OCTO_DISPATCH_PLAN_ARGV[0]}" == codex ]] &&
   [[ "${OCTO_DISPATCH_PLAN_ARGV[3]}" == openai/gpt-6-astra ]]; then
  test_pass
else
  test_fail "plan argv did not round-trip"
fi

test_case "headless providers retain the required empty prompt argument"
headless_plan="$(octo_dispatch_plan_create codex review code-reviewer \
  'codex exec' gpt-5.6-sol 0 1 true)"
if jq -e '.argv == ["codex","exec","-p",""]' <<<"$headless_plan" >/dev/null; then
  test_pass
else
  test_fail "empty provider argument was lost: $headless_plan"
fi

test_case "Antigravity model labels remain one environment argv element"
PROVIDER_ENV_ARRAY=(env -i "PATH=$PATH" "OCTOPUS_AGY_MODEL=stale")
octo_dispatch_plan_bind_model_env 'agy:Gemini 3.5 Flash (High)' 'Gemini 3.5 Flash (High)'
agy_plan="$(octo_dispatch_plan_create 'agy:Gemini 3.5 Flash (High)' review reviewer \
  "$PLUGIN_DIR/scripts/helpers/agy-exec.sh" 'Gemini 3.5 Flash (High)' 0 1)"
if [[ "${PROVIDER_ENV_ARRAY[3]}" == 'OCTOPUS_AGY_MODEL=Gemini 3.5 Flash (High)' ]] &&
   jq -e --arg command "$PLUGIN_DIR/scripts/helpers/agy-exec.sh" \
     '.argv == [$command] and .requested_model == "Gemini 3.5 Flash (High)"' \
     <<<"$agy_plan" >/dev/null; then
  test_pass
else
  test_fail "Antigravity model was split between command and environment argv"
fi

test_case "commands cannot embed credential values in the recorded argv"
if octo_dispatch_plan_create codex review code-reviewer \
  'env OPENAI_API_KEY=secret codex exec' gpt-5.6-sol 0 1 >/dev/null 2>&1; then
  test_fail "credential-bearing argv was admitted"
else
  test_pass
fi

test_case "recorded explanation remains valid JSON and secret-free"
trace_file="$RESULTS_DIR/dispatch-plans.jsonl"
octo_dispatch_plan_record "$plan" "$trace_file"
if [[ "$(wc -l < "$trace_file" | tr -d ' ')" == 1 ]] &&
   jq -e -s 'length == 1 and .[0].event == "dispatch-plan" and .[0].plan.schema_version == 1' "$trace_file" >/dev/null &&
   ! grep -q 'super-secret' "$trace_file"; then
  test_pass
else
  test_fail "explanation record is malformed or sensitive"
fi

test_case "a dead dispatch-plan writer cannot wedge later dispatches"
stale_trace="$RESULTS_DIR/stale-dispatch-plans.jsonl"
mkdir "${stale_trace}.lock"
printf '99999999\n' > "${stale_trace}.lock/pid"
printf '1\n' > "${stale_trace}.lock/ts"
if OCTOPUS_DISPATCH_PLAN_LOCK_STALE_SECS=1 \
   octo_dispatch_plan_record "$plan" "$stale_trace" &&
   [[ ! -e "${stale_trace}.lock" ]] &&
   jq -e -s 'length == 1 and .[0].event == "dispatch-plan"' "$stale_trace" >/dev/null; then
  test_pass
else
  test_fail "stale dispatch-plan lock was not reclaimed"
fi

test_case "unsafe project authority fails closed"
PROJECT_ROOT=relative/path
if octo_dispatch_plan_create codex review reviewer 'codex exec' gpt-5.6-sol 0 1 >/dev/null 2>&1; then
  test_fail "relative project root was admitted"
else
  test_pass
fi

test_case "model-only and agent-spec family APIs are distinct"
if [[ "$(octo_model_family 'gpt-5.6-luna')" == openai ]] &&
   [[ "$(octo_agent_spec_model_family 'commandcode:minimaxai/minimax-m3')" == minimax ]] &&
   [[ "$(octo_agent_spec_model_family 'codex:gpt-5.6-luna')" == openai ]]; then
  test_pass
else
  test_fail "model and spec family classification diverged"
fi

test_summary
