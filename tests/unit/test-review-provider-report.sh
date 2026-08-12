#!/usr/bin/env bash
# Regression coverage for evidence-based review provider status (#891).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT/scripts/lib/review.sh"

test_suite "Review provider report"

status_file="$TEST_TMP_DIR/provider-status.txt"

test_case "Claude is not reported healthy without a successful execution"
printf '%s\n' 'codex|fallback|Round 1 agent did not complete successfully' > "$status_file"
report="$(env "HOME=${TEST_TMP_DIR}" bash -c '
    source "$1"
    print_provider_report "$2"
' _ "$PROJECT_ROOT/scripts/lib/review.sh" "$status_file")"
if grep -Eq 'Claude:[[:space:]]+not used' <<< "$report"; then
    test_pass
else
    test_fail "Claude received an optimistic status without execution evidence: $report"
fi

test_case "Claude failures are rendered as failures"
printf '%s\n' 'claude|fallback|Round 1 agent did not complete successfully' > "$status_file"
report="$(env "HOME=${TEST_TMP_DIR}" bash -c '
    source "$1"
    print_provider_report "$2"
' _ "$PROJECT_ROOT/scripts/lib/review.sh" "$status_file")"
if grep -Eq 'Claude:[[:space:]]+.*FALLBACK' <<< "$report" &&
   [[ "$report" == *"Round 1 agent did not complete successfully"* ]]; then
    test_pass
else
    test_fail "Claude failure was hidden by the provider report: $report"
fi

test_case "review failure detail preserves the actionable provider error"
failure_file="$TEST_TMP_DIR/openai-compatible-failed.md"
cat > "$failure_file" <<'EOF'
# Agent result

## Output
```
You've hit your weekly limit · resets Aug 15, 7am (UTC)
```

## Status: FAILED (Provider exited 1)
EOF
detail="$(review_result_failure_detail "$failure_file")"
if [[ "$detail" == "You've hit your weekly limit · resets Aug 15, 7am (UTC)" ]]; then
    test_pass
else
    test_fail "provider error was replaced by a generic failure: ${detail:-<empty>}"
fi

test_case "review failure detail falls back to the actionable stderr error"
stderr_failure_file="$TEST_TMP_DIR/provider-stderr-failed.md"
cat > "$stderr_failure_file" <<'EOF'
# Agent result

## Output
```
(no output captured — provider produced no stdout)
```

## Status: FAILED (Provider exited 1)

## Error Log
```
provider=generic
urllib.error.HTTPError: HTTP Error 410: Gone
RuntimeError: HTTP 410: GitHub Models is retired; use GitHub Copilot
```
EOF
detail="$(review_result_failure_detail "$stderr_failure_file")"
if [[ "$detail" == "RuntimeError: HTTP 410: GitHub Models is retired; use GitHub Copilot" ]]; then
    test_pass
else
    test_fail "provider stderr error was hidden: ${detail:-<empty>}"
fi

test_case "single-provider override keeps every review phase on the requested provider"
override_fleet="$(OCTOPUS_REVIEW_SINGLE_PROVIDER=openai-compatible-agent build_review_fleet)"
override_phase="$(OCTOPUS_REVIEW_SINGLE_PROVIDER=openai-compatible-agent review_phase_provider claude-sonnet)"
debate_block="$(sed -n '/# ── Debate gate/,/# ── ROUND 3/p' "$PROJECT_ROOT/scripts/lib/review.sh")"
if [[ "$(wc -l <<< "$override_fleet" | tr -d ' ')" -eq 1 ]] &&
   [[ "$override_fleet" == openai-compatible-agent:general-reviewer:* ]] &&
   [[ "$override_phase" == "openai-compatible-agent" ]] &&
   [[ "$override_fleet" != *"claude"* ]] &&
   grep -q 'review_phase_provider' <<< "$debate_block" &&
   ! grep -q 'review_run_agent_sync_progress "codex"' <<< "$debate_block"; then
    test_pass
else
    test_fail "single-provider review escaped to another provider: fleet=$override_fleet phase=$override_phase"
fi

test_case "review provider mapping keeps claude-sdk before the broad Claude glob"
sdk_line="$(grep -n 'claude-sdk\*)' "$PROJECT_ROOT/scripts/lib/review.sh" | head -1 | cut -d: -f1)"
claude_line="$(grep -n '^[[:space:]]*claude\*)' "$PROJECT_ROOT/scripts/lib/review.sh" | head -1 | cut -d: -f1)"
if [[ -n "$sdk_line" && -n "$claude_line" && "$sdk_line" -lt "$claude_line" ]]; then
    test_pass
else
    test_fail "claude-sdk must precede claude* in review provider mapping"
fi

test_case "OpenAI-compatible failures are visible with their full detail"
printf '%s\n' "openai-compatible|fallback|You've hit your weekly limit · resets Aug 15, 7am (UTC)" > "$status_file"
report="$(env "HOME=${TEST_TMP_DIR}" bash -c '
    source "$1"
    print_provider_report "$2"
' _ "$PROJECT_ROOT/scripts/lib/review.sh" "$status_file")"
if grep -Eq 'Compatible:[[:space:]]+.*FALLBACK' <<< "$report" &&
   [[ "$report" == *"You've hit your weekly limit · resets Aug 15, 7am (UTC)"* ]]; then
    test_pass
else
    test_fail "OpenAI-compatible provider failure was hidden or truncated: $report"
fi

test_case "Copilot fallback failures are visible with their full detail"
printf '%s\n' "copilot|fallback|Copilot request denied by repository policy" > "$status_file"
report="$(env "HOME=${TEST_TMP_DIR}" bash -c '
    source "$1"
    print_provider_report "$2"
' _ "$PROJECT_ROOT/scripts/lib/review.sh" "$status_file")"
if grep -Eq 'Copilot:[[:space:]]+.*FALLBACK' <<< "$report" &&
   [[ "$report" == *"Copilot request denied by repository policy"* ]]; then
    test_pass
else
    test_fail "Copilot provider failure was hidden or truncated: $report"
fi

test_summary
