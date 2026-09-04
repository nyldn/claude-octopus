#!/usr/bin/env bash
# v10 durable manifest and offline status/explain contract.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "v10 run observability"

source "$PROJECT_ROOT/scripts/lib/run-contract.sh"
source "$PROJECT_ROOT/scripts/lib/error-tracking.sh"

export WORKSPACE_DIR="$TEST_TMP_DIR/observability-workspace"
export OCTOPUS_RUN_ID="observable-run"
mkdir -p "$WORKSPACE_DIR"

good_output="$TEST_TMP_DIR/good.md"
degraded_output="$TEST_TMP_DIR/degraded.md"
printf 'complete implementation evidence\n' > "$good_output"
printf 'useful but degraded review evidence\n' > "$degraded_output"

run_contract_transition implement planned \
    requested_provider=codex requested_model=gpt-pin requested_effort=low \
    phase=develop role=implementer isolation=worktree worktree=/tmp/worktree \
    source_sha=abc123 source_dirty=clean checkpoint=develop attempt_id=impl-1
run_contract_transition implement starting \
    resolved_provider=codex resolved_model=gpt-resolved resolved_effort=medium \
    estimated_cost_usd=0.12
run_contract_transition implement authenticated
run_contract_transition implement running pid=123 pgid=123
run_contract_transition implement output_received output_file="$good_output" stderr_file=/tmp/impl.err diff_file=/tmp/impl.diff tokens_in=100 tokens_out=50 duration_ms=1200
run_contract_transition implement validated contribution=eligible
run_contract_transition implement contributed contribution=eligible cleanup_result=already-exited

run_contract_transition verifier planned \
    requested_provider=claude requested_model=fable requested_effort=high \
    phase=deliver role=verifier isolation=background attempt_id=verify-1
run_contract_transition verifier starting \
    resolved_provider=claude resolved_model=claude-fable-5 resolved_effort=high
run_contract_transition verifier authenticated
run_contract_transition verifier running
run_contract_transition verifier output_received output_file="$degraded_output" duration_ms=900
run_contract_transition verifier validated contribution=eligible
run_contract_transition verifier degraded contribution=eligible-with-warning reason=independent-verifier-unavailable

run_contract_transition failed-seat planned requested_provider=agy requested_model=default phase=discover attempt_id=failed-1
run_contract_transition failed-seat failed reason=authentication-failed cleanup_result=no-process

run_dir="$WORKSPACE_DIR/runs/$OCTOPUS_RUN_ID"
manifest="$run_dir/run.json"

test_case "atomic run manifest and latest pointer exist"
if [[ -s "$manifest" && -L "$WORKSPACE_DIR/runs/latest" ]] &&
   jq empty "$manifest" >/dev/null 2>&1; then
    test_pass
else
    test_fail "run.json or latest pointer missing"
fi

test_case "manifest reconstructs identities, timeline, metrics, artifacts, and cleanup"
if jq -e '
    .schema_version == "10.0" and .run_id == "observable-run" and
    (.seats | length == 3) and
    (.seats[] | select(.seat_id == "implement") |
      .requested == {provider:"codex", model:"gpt-pin", effort:"low"} and
      .resolved == {provider:"codex", model:"gpt-resolved", effort:"medium"} and
      .source == {sha:"abc123", dirty_decision:"clean"} and
      .execution.worktree == "/tmp/worktree" and
      .execution.cleanup_result == "already-exited" and
      .metrics.tokens_in == "100" and .metrics.tokens_out == "50" and
      .artifacts.output != "" and .artifacts.diff == "/tmp/impl.diff" and
      .started_at != "" and .updated_at != "" and
      ([.timeline[].transition] == ["planned","starting","authenticated","running","output_received","validated","contributed"]))
  ' "$manifest" >/dev/null 2>&1; then
    test_pass
else
    test_fail "manifest cannot reconstruct the implementation seat"
fi

test_case "manifest summarizes contribution and degraded coverage truthfully"
if jq -e '
    .summary.total_seats == 3 and
    .summary.contributed == 1 and
    .summary.degraded == 1 and
    .summary.failed == 1 and
    .summary.eligible_contributions == 2 and
    .summary.degraded_coverage == true and
    (.phases.develop.contributed == 1) and
    (.phases.deliver.degraded == 1) and
    (.phases.discover.failed == 1)
  ' "$manifest" >/dev/null 2>&1; then
    test_pass
else
    test_fail "manifest summary or phase rollup is untruthful"
fi

test_case "status and explain read durable artifacts without dispatch"
status_json=""
explanation=""
if declare -f run_contract_status >/dev/null 2>&1; then
    status_json="$(run_contract_status "$OCTOPUS_RUN_ID" json 2>/dev/null || true)"
fi
if declare -f run_contract_explain >/dev/null 2>&1; then
    explanation="$(run_contract_explain "$OCTOPUS_RUN_ID" 2>/dev/null || true)"
fi
if jq -e '.run_id == "observable-run" and .summary.failed == 1' <<< "$status_json" >/dev/null 2>&1 &&
   [[ "$explanation" == *"implement"*"contributed"* && "$explanation" == *"verifier"*"independent-verifier-unavailable"* && "$explanation" == *"failed-seat"*"authentication-failed"* ]]; then
    test_pass
else
    test_fail "status=$status_json explain=$explanation"
fi

test_case "compatibility status snapshots preserve the latest run pointer contract"
write_agent_status codex ok 100 50 "" 1200 "$good_output" researcher \
    implement contributed eligible
latest_status="$(run_contract_status latest json 2>/dev/null || true)"
if [[ -L "$WORKSPACE_DIR/runs/latest" ]] &&
   jq -e '.run_id == "observable-run" and .summary.contributed == 1' \
      <<< "$latest_status" >/dev/null 2>&1; then
    test_pass
else
    test_fail "compatibility writer broke status --run latest: ${latest_status:-<empty>}"
fi

test_case "unknown and corrupt runs fail closed"
mkdir -p "$WORKSPACE_DIR/runs/corrupt"
printf '{broken\n' > "$WORKSPACE_DIR/runs/corrupt/run.json"
set +e
run_contract_status missing json >/dev/null 2>&1; missing_rc=$?
run_contract_status corrupt json >/dev/null 2>&1; corrupt_rc=$?
set -e
if [[ "$missing_rc" -ne 0 && "$corrupt_rc" -ne 0 ]]; then
    test_pass
else
    test_fail "missing_rc=$missing_rc corrupt_rc=$corrupt_rc"
fi

test_case "orchestrator status and explain remain offline"
fake_bin="$TEST_TMP_DIR/fake-bin"
provider_ledger="$TEST_TMP_DIR/provider-ledger"
mkdir -p "$fake_bin"
for provider in claude codex agy qwen; do
    printf '#!/usr/bin/env bash\nprintf "%s\\n" "%s" >> "%s"\nexit 99\n' \
        "$provider" "$provider" "$provider_ledger" > "$fake_bin/$provider"
    chmod 755 "$fake_bin/$provider"
done
set +e
cli_status=$(env HOME="$TEST_TMP_DIR/cli-home" PATH="$fake_bin:$PATH" \
    CLAUDE_PLUGIN_DATA="$WORKSPACE_DIR" OCTOPUS_PROJECT_DIR="$PROJECT_ROOT" \
    bash "$PROJECT_ROOT/scripts/orchestrate.sh" status --run "$OCTOPUS_RUN_ID" --json 2>/dev/null)
cli_status_rc=$?
cli_explain=$(env HOME="$TEST_TMP_DIR/cli-home" PATH="$fake_bin:$PATH" \
    CLAUDE_PLUGIN_DATA="$WORKSPACE_DIR" OCTOPUS_PROJECT_DIR="$PROJECT_ROOT" \
    bash "$PROJECT_ROOT/scripts/orchestrate.sh" explain --run "$OCTOPUS_RUN_ID" 2>/dev/null)
cli_explain_rc=$?
set -e
if [[ "$cli_status_rc" -eq 0 && "$cli_explain_rc" -eq 0 && ! -e "$provider_ledger" ]] &&
   jq -e '.run_id == "observable-run"' <<< "$cli_status" >/dev/null 2>&1 &&
   [[ "$cli_explain" == *"authentication-failed"* ]]; then
    test_pass
else
    test_fail "status_rc=$cli_status_rc explain_rc=$cli_explain_rc ledger=$(<"$provider_ledger" 2>/dev/null || true)"
fi

test_case "proof-disabled compatibility records share the stable run-contract identity"
proof_disabled_result="$(
    unset OCTOPUS_RUN_ID OCTOPUS_SESSION_ID CLAUDE_CODE_SESSION_ID \
        CLAUDE_SESSION_ID CLAUDE_CODE_SESSION OCTO_RUN_CONTRACT_FALLBACK_ID
    export WORKSPACE_DIR="$TEST_TMP_DIR/proof-disabled-workspace"
    export OCTOPUS_PROOF_PACKET=0
    source "$PROJECT_ROOT/scripts/lib/run-contract.sh"
    source "$PROJECT_ROOT/scripts/lib/error-tracking.sh"
    first_id="$(octo_run_contract_id)"
    second_id="$(octo_current_run_id)"
    record_oversize_event codex 100 40 summarized implementation-verifier review 12
    write_agent_status codex ok 25 10 "" 10 "$good_output" \
        implementation-verifier verifier-seat contributed eligible
    if [[ "$first_id" == "$second_id" ]] &&
       [[ -s "$WORKSPACE_DIR/runs/$first_id/oversize.jsonl" ]] &&
       [[ -s "$WORKSPACE_DIR/runs/$first_id/agents.jsonl" ]] &&
       jq -e --arg run_id "$first_id" '
           .run_id == $run_id and .agent == "codex" and
           .role == "implementation-verifier" and .phase == "review" and
           .budget == 12 and .original_chars == 100 and .final_chars == 40 and
           (.ts | length) > 0
       ' "$WORKSPACE_DIR/runs/$first_id/oversize.jsonl" >/dev/null 2>&1; then
        printf 'pass\n'
    else
        printf 'fail:%s:%s\n' "$first_id" "$second_id"
    fi
)"
if [[ "$proof_disabled_result" == pass ]]; then
    test_pass
else
    test_fail "proof-disabled records diverged: $proof_disabled_result"
fi

test_case "no-jq oversize writer JSON-escapes arbitrary string fields"
no_jq_run_id=$'run"id\\tail\nnext'
no_jq_agent=$'codex"agent\\tail\nnext'
no_jq_role=$'review"role\\tail\nnext'
no_jq_phase=$'review"phase\\tail\nnext'
no_jq_outcome=$'summarized"outcome\\tail\nnext'
(
    export OCTOPUS_RUN_ID="$no_jq_run_id"
    command() {
        if [[ "${1:-}" == "-v" && "${2:-}" == "jq" ]]; then
            return 1
        fi
        builtin command "$@"
    }
    record_oversize_event "$no_jq_agent" 00100 00040 "$no_jq_outcome" \
        "$no_jq_role" "$no_jq_phase" 00012
)
no_jq_record="$WORKSPACE_DIR/runs/$no_jq_run_id/oversize.jsonl"
if jq -e \
    --arg run_id "$no_jq_run_id" \
    --arg agent "$no_jq_agent" \
    --arg role "$no_jq_role" \
    --arg phase "$no_jq_phase" \
    --arg outcome "$no_jq_outcome" '
      .run_id == $run_id and .agent == $agent and .role == $role and
      .phase == $phase and .outcome == $outcome and
      .budget == 12 and .original_chars == 100 and .final_chars == 40
    ' "$no_jq_record" >/dev/null 2>&1; then
    test_pass
else
    test_fail "no-jq writer emitted invalid or lossy JSON: $(cat "$no_jq_record" 2>/dev/null || true)"
fi

test_summary
