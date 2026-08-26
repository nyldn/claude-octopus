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

test_summary
