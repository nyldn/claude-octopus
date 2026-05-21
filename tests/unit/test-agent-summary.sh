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
printf 'gemini output\n' > "$WORKSPACE_DIR/results/gemini.md"

test_case "write_agent_status creates jsonl and snapshot"
write_agent_status "codex" "ok" 100 50 "" 1200 "$WORKSPACE_DIR/results/codex.md" "researcher"
write_agent_status "gemini" "failed" 100 0 "Prompt rejected by provider (oversize)" 900 "$WORKSPACE_DIR/results/gemini.md" "researcher"

if [[ -s "$WORKSPACE_DIR/runs/test-run/agents.jsonl" && -s "$WORKSPACE_DIR/runs/test-run/agents.json" ]]; then
    test_pass
else
    test_fail "expected agents.jsonl and agents.json snapshot"
fi

test_case "agent_status_output_files excludes failed providers"
files="$(agent_status_output_files)"
if [[ "$files" == *"codex.md"* && "$files" != *"gemini.md"* ]]; then
    test_pass
else
    test_fail "expected only usable output files, got: ${files:-<empty>}"
fi

test_case "render_agent_summary shows provider table"
summary="$(render_agent_summary)"
if [[ "$summary" == *"codex"* && "$summary" == *"gemini"* && "$summary" == *"failed"* ]]; then
    test_pass
else
    test_fail "expected provider status table, got: ${summary:-<empty>}"
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
classification="$(classify_agent_output "$codex_empty_output" 0 "gemini" "$codex_stderr_transcript")"
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
