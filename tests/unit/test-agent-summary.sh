#!/usr/bin/env bash
# Tests for agent run status ledger and summary rendering.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Agent summary ledger"

source "$PROJECT_ROOT/scripts/lib/error-tracking.sh"

export WORKSPACE_DIR="$TEST_TMP_DIR/agent-summary-workspace"
export OCTOPUS_RUN_ID="test-run"
mkdir -p "$WORKSPACE_DIR/results"
printf 'codex output\n' > "$WORKSPACE_DIR/results/codex.md"
printf 'agy output\n' > "$WORKSPACE_DIR/results/agy.md"

test_case "write_agent_status creates jsonl and snapshot"
write_agent_status "codex" "ok" 100 50 "" 1200 "$WORKSPACE_DIR/results/codex.md" "researcher"
write_agent_status "agy" "failed" 100 0 "Prompt rejected by provider (oversize)" 900 "$WORKSPACE_DIR/results/agy.md" "researcher"

if [[ -s "$WORKSPACE_DIR/runs/test-run/agents.jsonl" && -s "$WORKSPACE_DIR/runs/test-run/agents.json" ]]; then
    test_pass
else
    test_fail "expected agents.jsonl and agents.json snapshot"
fi

test_case "legacy status rows retain keys and expose v10 projection fields"
if jq -e -s '
    .[0] as $row |
    ($row | has("agent") and has("role") and has("status") and
      has("tokens_in") and has("tokens_out") and has("duration_ms") and
      has("reason") and has("output_file") and has("ts")) and
    ($row | has("schema_version") and has("seat_id") and
      has("transition") and has("contribution"))
' "$WORKSPACE_DIR/runs/test-run/agents.jsonl" >/dev/null; then
    test_pass
else
    test_fail "legacy or v10 compatibility projection keys are missing"
fi

test_case "agent_status_output_files excludes failed providers"
files="$(agent_status_output_files)"
if [[ "$files" == *"codex.md"* && "$files" != *"agy.md"* ]]; then
    test_pass
else
    test_fail "expected only usable output files, got: ${files:-<empty>}"
fi

test_case "render_agent_summary shows provider table"
summary="$(render_agent_summary)"
if [[ "$summary" == *"codex"* && "$summary" == *"agy"* && "$summary" == *"failed"* ]]; then
    test_pass
else
    test_fail "expected provider status table, got: ${summary:-<empty>}"
fi

test_case "render_agent_summary reconciles stale running row from output file"
running_file="$WORKSPACE_DIR/results/copilot-running.md"
cat > "$running_file" <<'EOF'
# Agent: copilot

## Output
```
Provider produced a complete answer after the status ledger was written.
```

## Status: SUCCESS
EOF
write_agent_status "copilot" "running" 100 0 "" 0 "$running_file" "researcher"
summary="$(render_agent_summary)"
copilot_row="$(printf '%s\n' "$summary" | grep '^copilot[[:space:]]*|' || true)"
if [[ "$copilot_row" == *" ok"* && "$copilot_row" != *"running"* ]]; then
    test_pass
else
    test_fail "expected stale running provider to reconcile from result file, got row: ${copilot_row:-<empty>}"
fi

test_case "agent_status_output_files includes stale running row with usable output"
files="$(agent_status_output_files)"
if [[ "$files" == *"copilot-running.md"* ]]; then
    test_pass
else
    test_fail "expected usable stale running output to be listed, got: ${files:-<empty>}"
fi

test_case "agent_status_output_files excludes timed-out partial output"
timeout_file="$WORKSPACE_DIR/results/timed-out-partial.md"
printf '%s\n' 'partial provider output before timeout' > "$timeout_file"
write_agent_status "timeout-provider" "timeout" 100 20 "Timed out before completion" 5000 "$timeout_file" "researcher"
files="$(agent_status_output_files)"
if [[ "$files" != *"timed-out-partial.md"* ]]; then
    test_pass
else
    test_fail "timed-out partial output was incorrectly eligible for synthesis"
fi

test_case "classify_agent_output detects Codex closed stdin tool error"
codex_empty_output="$WORKSPACE_DIR/results/codex-empty.out"
codex_stderr="$WORKSPACE_DIR/results/codex-stderr.err"
> "$codex_empty_output"
printf '%s\n' '2026-05-15T10:03:10Z ERROR codex_core::tools::router: error=write_stdin failed: stdin is closed for this session; rerun exec_command with tty=true to keep stdin open' > "$codex_stderr"
classification="$(classify_agent_output "$codex_empty_output" 0 "codex" "$codex_stderr")"
if [[ "$classification" == "failed:Codex tool stdin closed"* ]]; then
    test_pass
else
    test_fail "expected Codex stdin-closed classification, got: ${classification:-<empty>}"
fi

test_case "classify_agent_output treats Codex stderr transcript as degraded"
codex_stderr_transcript="$WORKSPACE_DIR/results/codex-stderr-transcript.err"
> "$codex_empty_output"
cat > "$codex_stderr_transcript" <<'EOF'
OpenAI Codex v0.130.0
--------
assistant
## Worktree Changes
- src/app/page.tsx

## Verification
- npm test
# Completed: Tue May 19 15:06:36 CEST 2026
tokens used
12345
EOF
classification="$(classify_agent_output "$codex_empty_output" 0 "codex" "$codex_stderr_transcript")"
if [[ "$classification" == "degraded:Codex response captured on stderr" ]]; then
    test_pass
else
    test_fail "expected Codex stderr transcript to be degraded, got: ${classification:-<empty>}"
fi

test_case "classify_agent_output keeps empty non-Codex output failed"
classification="$(classify_agent_output "$codex_empty_output" 0 "agy" "$codex_stderr_transcript")"
if [[ "$classification" == "failed:Empty output" ]]; then
    test_pass
else
    test_fail "expected non-Codex empty output to fail, got: ${classification:-<empty>}"
fi

test_case "OCTOPUS_REQUIRE_ALL fails when any provider failed"
set +e
OCTOPUS_REQUIRE_ALL=true render_agent_summary >/tmp/octopus-agent-summary-test.out 2>/dev/null
rc=$?
set -e
if [[ $rc -eq 78 ]]; then
    test_pass
else
    test_fail "expected exit 78 when all providers required, got: $rc"
fi

seat_statuses() {
    printf '%s\n' "$1" | grep "^$2 " | awk -F '|' '{ gsub(/[^a-z]/, "", $2); print $2 }' | sort | paste -sd, -
}

test_case "a later seat of the same provider does not replace an earlier seat's result"
export OCTOPUS_RUN_ID="multi-seat-run"
seat_one="$WORKSPACE_DIR/results/claude-sonnet-probe-7-1.md"
seat_three="$WORKSPACE_DIR/results/claude-sonnet-probe-7-3.md"
printf 'partial output before timeout\n' > "$seat_one"
printf 'complete probe answer\n' > "$seat_three"
write_agent_status "claude-sonnet" "running" 100 0 "" 0 "$seat_one" "researcher"
write_agent_status "claude-sonnet" "running" 100 0 "" 0 "$seat_three" "researcher" "spawn-probe-7-3"
write_agent_status "claude-sonnet" "ok" 100 50 "" 557000 "$seat_three" "researcher" "spawn-probe-7-3"
write_agent_status "claude-sonnet" "timeout" 100 0 "Timed out before completion" 603000 "$seat_one" "researcher"
summary="$(render_agent_summary)"
files="$(agent_status_output_files)"
snapshot_statuses="$(jq -r '[.agents[].status] | sort | join(",")' "$WORKSPACE_DIR/runs/multi-seat-run/agents.json")"
if [[ "$(seat_statuses "$summary" claude-sonnet)" == "ok,timeout" ]] && \
   [[ "$summary" == *"1 of 2 agents failed or timed out"* ]] && \
   [[ "$files" == "$seat_three" && "$snapshot_statuses" == "ok,timeout" ]]; then
    test_pass
else
    test_fail "seat results collapsed per provider: rows=[$(seat_statuses "$summary" claude-sonnet)] files=[${files:-<none>}] snapshot=[$snapshot_statuses]"
fi

test_case "a filtered summary counts only the seats of that probe"
write_agent_status "codex" "failed" 100 0 "Exit code 1" 1000 "$WORKSPACE_DIR/results/codex-probe-8-0.md" "researcher"
write_agent_status "claude-sonnet" "ok" 100 50 "" 1000 "$WORKSPACE_DIR/results/sync-result-8.md" "synthesizer" "sync-probe-claude-sonnet-8"
summary="$(render_agent_summary "-probe-7-")"
if [[ "$(seat_statuses "$summary" claude-sonnet)" == "ok,timeout" ]] && \
   [[ "$summary" != *"codex"* && "$summary" == *"1 of 2 agents failed or timed out"* ]] && \
   [[ "$(seat_statuses "$(render_agent_summary)" claude-sonnet)" == "ok,ok,timeout" ]]; then
    test_pass
else
    test_fail "filtered summary included other seats: $(tr '\n' ' ' <<< "$summary")"
fi

test_case "available-output count excludes timed-out partial files"
summary="$(render_agent_summary "-probe-7-")"
if [[ "$summary" == *"use 1 available outputs"* ]]; then
    test_pass
else
    test_fail "expected only the completed seat to count: $summary"
fi

test_case "task-group summary retains a rejected prompt without an output file"
write_agent_status "codex" "failed" 100 0 "Prompt exceeded context budget" 0 "" "researcher" "spawn-summary-budget-subtask-1"
summary="$(render_agent_summary "summary-budget-subtask-")"
if [[ "$summary" == *"codex"* && "$summary" == *"1 of 1 agents failed"* ]]; then
    test_pass
else
    test_fail "output-less task failure disappeared: $summary"
fi

test_case "exact task selection excludes earlier same-provider seats"
tasks="$(jq -nc --arg file "$seat_three" '[{id:"probe-7-3",output_file:$file}]')"
summary="$(render_agent_summary "" "$tasks")"
files="$(agent_status_output_files "" "$tasks")"
if [[ "$(seat_statuses "$summary" claude-sonnet)" == ok && "$summary" != *codex* && "$files" == "$seat_three" ]]; then
    test_pass
else
    test_fail "unrelated session seats entered exact task selection: $summary / $files"
fi

test_case "probe summaries count genuinely usable timeout output"
partial="$WORKSPACE_DIR/results/codex-probe-partial-1.md"
printf '## Output\nuseful partial research\n## Status: TIMEOUT\n' > "$partial"
write_agent_status codex timeout 100 10 "Timed out" 1000 "$partial"
summary="$(render_agent_summary '-probe-partial-' null probe)"
if [[ "$summary" == *'use 1 available outputs'* ]]; then
    test_pass
else
    test_fail "probe synthesis can use partial output that the summary did not count: $summary"
fi

test_case "exact task scope does not inherit a legacy failure through a reused path"
write_agent_status codex failed 1 0 "old task" 0 "$seat_three" researcher
summary="$(render_agent_summary "" "$tasks")"
if [[ "$summary" != *codex* ]]; then test_pass; else test_fail "old seat entered current scope: $summary"; fi

test_case "exact task scope rejects an earlier output for a reused task ID"
foreign_tasks="$(jq -nc --arg file "$WORKSPACE_DIR/results/agy-probe-7-3.md" '[{id:"probe-7-3",output_file:$file}]')"
summary="$(render_agent_summary '' "$foreign_tasks")"
files="$(agent_status_output_files '' "$foreign_tasks")"
if [[ "$summary" != *claude-sonnet* && -z "$files" ]]; then test_pass
else test_fail "reused task inherited another provider's result: $summary / $files"; fi

test_case "an output-less scope cannot inherit an earlier output-bearing row"
empty_tasks='[{"id":"probe-7-3","output_file":""}]'
files="$(agent_status_output_files '' "$empty_tasks")"
if [[ -z "$files" ]]; then test_pass
else test_fail "output-less scope inherited a saved result: $files"; fi

test_case "seat-only filters retain the selected seat's usable output"
files="$(agent_status_output_files 'spawn-probe-7-3')"
if [[ "$files" == "$seat_three" ]]; then test_pass
else test_fail "summary and output selector disagree on seat filter: $files"; fi

test_case "exact output scopes retain genuinely output-less failures"
empty_tasks='[{"id":"summary-budget-subtask-1","output_file":"/missing-current-output.md"}]'
summary="$(render_agent_summary '' "$empty_tasks")"
if [[ "$summary" == *'1 of 1 agents failed'* ]]; then test_pass
else test_fail "output-less failure disappeared from current scope: $summary"; fi

test_case "cancelled seats count as failures and enforce require-all"
export OCTOPUS_RUN_ID=cancelled-summary
write_agent_status codex cancelled 1 0 'Worker exited' 1 '' researcher spawn-cancelled
cancelled_rc=0
summary="$(OCTOPUS_REQUIRE_ALL=true render_agent_summary)" || cancelled_rc=$?
if [[ "$cancelled_rc" == 78 && "$summary" == *'1 of 1 agents failed, timed out or were cancelled'* && "$summary" == *'⊘ cancelled'* ]]; then
    test_pass
else test_fail "cancelled seat escaped the summary failure guard: rc=$cancelled_rc $summary"; fi

test_case "budget helper and caller keep one rejected seat"
source "$PROJECT_ROOT/scripts/lib/dispatch.sh"
get_provider_context_limit() { echo 1; }
get_role_budget_proportion() { echo 100; }
log() { :; }
export OCTOPUS_RUN_ID=budget-identity OCTOPUS_OVERSIZE_STRATEGY=fail
budget_rc=0
enforce_context_budget 'too much context' '' codex probe spawn-budget-1 >/dev/null || budget_rc=$?
write_agent_status codex failed 4 0 "Prompt exceeded context budget" 0 '' '' spawn-budget-1
if [[ "$budget_rc" == 78 ]] && jq -e '.agents | length == 1' "$WORKSPACE_DIR/runs/$OCTOPUS_RUN_ID/agents.json" >/dev/null; then
    test_pass
else test_fail "one rejection became multiple seats"; fi

test_case "probe budget failure remains in its filtered summary"
source "$PROJECT_ROOT/scripts/lib/workflows.sh"
preflight_check() { :; }
match_routing_rule() { :; }
classify_task() { :; }
apply_persona() { printf '%s' 'too much context'; }
SUPPORTS_AGENT_TYPE_ROUTING=false OCTOPUS_PERSONA_PACKS=off
RESULTS_DIR="$WORKSPACE_DIR/results" LOGS_DIR="$WORKSPACE_DIR/logs"
probe_rc=0
probe_single_agent codex perspective probe-budget-2 original >/dev/null || probe_rc=$?
summary="$(render_agent_summary '-probe-budget-2')"
if [[ "$probe_rc" == 78 && "$summary" == *'1 of 1 agents failed'* ]]; then test_pass
else test_fail "probe rejection disappeared: $summary, rc=$probe_rc"; fi

test_case "probe status rows use the canonical spawn seat ID"
eval "$(sed -n '/^octo_spawn_contract_seat_id() {$/,/^}$/p' "$PROJECT_ROOT/scripts/lib/spawn.sh")"
export OCTOPUS_RUN_ID=probe-canonical-seat
probe_rc=0
probe_single_agent codex perspective 'probe-budget@3' original >/dev/null || probe_rc=$?
if [[ "$probe_rc" == 78 ]] && jq -e --arg seat "$(octo_spawn_contract_seat_id 'probe-budget@3')" \
    '.agents | length == 1 and .[0].seat_id == $seat and $seat == "spawn-probe-budget_3"' \
    "$WORKSPACE_DIR/runs/$OCTOPUS_RUN_ID/agents.json" >/dev/null; then
    test_pass
else
    test_fail "probe wrote a seat ID other than the contract seat, rc=$probe_rc"
fi

test_case "a probe environment failure records the canonical spawn seat ID"
export OCTOPUS_RUN_ID=probe-env-seat
probe_rc=0
(
    enforce_context_budget() { printf '%s' "$1"; }
    get_agent_model() { printf '%s' gpt-test; }
    get_agent_command() { printf '%s' 'codex exec'; }
    validate_agent_command() { :; }
    record_agent_call() { :; }
    update_metrics() { :; }
    bridge_register_task() { :; }
    update_agent_status() { :; }
    build_provider_env() { return 1; }
    probe_single_agent codex perspective 'probe-env@4' original >/dev/null 2>&1
) || probe_rc=$?
if [[ "$probe_rc" == 1 ]] && jq -e '.agents | length == 1 and .[0].seat_id == "spawn-probe-env_4" and
    .[0].reason == "Provider environment construction failed"' \
    "$WORKSPACE_DIR/runs/$OCTOPUS_RUN_ID/agents.json" >/dev/null; then
    test_pass
else
    test_fail "probe environment failure lost its seat ID, rc=$probe_rc"
fi

test_case "a rejected synchronous call records one failed seat"
source "$PROJECT_ROOT/scripts/lib/agent-sync.sh"
load_earned_skills() { :; }
build_provider_context() { :; }
run_contract_transition() { :; }
octo_with_engineering_methods() { printf '%s' "$2"; }
CODEX_SUBAGENT_PREAMBLE=''
export OCTOPUS_RUN_ID=sync-budget-identity
sync_rc=0
run_agent_sync codex 'too much context' 1 researcher probe >/dev/null || sync_rc=$?
summary="$(render_agent_summary)"
if [[ "$sync_rc" == 78 && "$summary" == *'1 of 1 agents failed'* ]] &&
   jq -e '.agents | length == 1 and all(.seat_id | startswith("sync-"))' \
       "$WORKSPACE_DIR/runs/$OCTOPUS_RUN_ID/agents.json" >/dev/null; then
    test_pass
else test_fail "synchronous budget rejection counted multiple seats: $summary, rc=$sync_rc"; fi

test_case "a truncated ledger does not abort a strict-shell summary caller"
export OCTOPUS_RUN_ID=truncated-ledger
mkdir -p "$WORKSPACE_DIR/runs/$OCTOPUS_RUN_ID"
printf '{"agent":' > "$WORKSPACE_DIR/runs/$OCTOPUS_RUN_ID/agents.jsonl"
if bash -euo pipefail -c 'source "$1/scripts/lib/error-tracking.sh"; render_agent_summary >/dev/null; echo continued' \
    _ "$PROJECT_ROOT" > "$TEST_TMP_DIR/truncated-summary.out" 2>/dev/null && \
    [[ "$(cat "$TEST_TMP_DIR/truncated-summary.out")" == continued ]]; then
    test_pass
else test_fail "summary aborted its caller on a truncated ledger"; fi

for damaged_ledger in truncated trailing; do
    test_case "require-all rejects a $damaged_ledger ledger"
    export OCTOPUS_RUN_ID="require-all-$damaged_ledger"
    ledger="$WORKSPACE_DIR/runs/$OCTOPUS_RUN_ID/agents.jsonl"
    mkdir -p "$(dirname "$ledger")"
    if [[ "$damaged_ledger" == trailing ]]; then
        write_agent_status codex failed 1 0 'Provider failed' 0 '' researcher spawn-damaged
    fi
    printf '{"agent":' >> "$ledger"
    summary_rc=0
    summary="$(OCTOPUS_REQUIRE_ALL=true render_agent_summary)" || summary_rc=$?
    if [[ "$summary_rc" == 78 && "$summary" == *'cannot read agent status ledger'* ]]; then
        test_pass
    else
        test_fail "damaged ledger bypassed require-all: rc=$summary_rc $summary"
    fi

    test_case "optional agents continue with a warning for a $damaged_ledger ledger"
    summary_rc=0
    summary="$(OCTOPUS_REQUIRE_ALL=false render_agent_summary)" || summary_rc=$?
    if [[ "$summary_rc" == 0 && "$summary" == *'cannot read agent status ledger'* ]]; then
        test_pass
    else
        test_fail "damaged ledger failed optional continuation or lacked a warning: rc=$summary_rc $summary"
    fi
done

# Exercise the CLI option contract of the installer's minimum jq version.
# The installed jq evaluates filters; this shim rejects the post-1.5 option.
test_case "scoped ledger readers work without jq's newer rawfile option"
if (
    jq() {
        local arg
        for arg in "$@"; do
            [[ "$arg" != --rawfile ]] || return 2
        done
        command jq "$@"
    }
    export OCTOPUS_RUN_ID=jq-minimum-options
    output="$WORKSPACE_DIR/results/minimum-jq.md"
    printf 'complete answer\n' > "$output"
    write_agent_status codex ok 1 1 '' 0 "$output" researcher spawn-minimum
    scope="$(command jq -nc --arg file "$output" '[{id:"minimum",output_file:$file}]')"
    [[ "$(agent_status_output_files '' "$scope")" == "$output" ]] &&
    [[ "$(render_agent_summary '' "$scope")" == *codex* ]]
); then test_pass
else test_fail "supported jq option set lost the scoped seat or its output"; fi

for invalid_scope in '[' 'null []'; do
    test_case "ledger readers reject an invalid or multi-value task scope: $invalid_scope"
    export OCTOPUS_RUN_ID=jq-minimum-options
    selector_rc=0 summary_rc=0
    agent_status_output_files '' "$invalid_scope" >/dev/null 2>&1 || selector_rc=$?
    OCTOPUS_REQUIRE_ALL=true render_agent_summary '' "$invalid_scope" >/dev/null 2>&1 || summary_rc=$?
    if [[ "$selector_rc" -gt 1 && "$summary_rc" == 78 ]]; then test_pass
    else test_fail "invalid scope accepted: selector=$selector_rc summary=$summary_rc"; fi
done

test_summary
