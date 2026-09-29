#!/usr/bin/env bash
# Regression coverage for evidence-based review provider status (#891).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT/scripts/lib/review.sh"

test_suite "Review provider report"

status_file="$TEST_TMP_DIR/provider-status.txt"

test_case "review provider-status parsing delegates to the shared parser"
if (
    octo_parse_provider_status_record() {
        OCTO_PROVIDER_STATUS_PROVIDER=commandcode
        OCTO_PROVIDER_STATUS_MODEL=model-one.v1
        OCTO_PROVIDER_STATUS_VALUE=fallback
        OCTO_PROVIDER_STATUS_DETAIL='shared parser detail'
        return 0
    }
    review_parse_provider_status_record 'ignored|input|that|must|not be parsed locally' &&
    [[ "$REVIEW_STATUS_PROVIDER" == commandcode &&
       "$REVIEW_STATUS_MODEL" == model-one.v1 &&
       "$REVIEW_STATUS_VALUE" == fallback &&
       "$REVIEW_STATUS_DETAIL" == 'shared parser detail' ]] || exit 1
    octo_parse_provider_status_record() { return 73; }
    parse_rc=0
    review_parse_provider_status_record 'ignored|input' || parse_rc=$?
    [[ "$parse_rc" -eq 73 ]]
); then
    test_pass
else
    test_fail "review parser bypassed the shared provider-status parser"
fi

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

codex_usage_limit_error="ERROR: You've hit your usage limit. Upgrade to Pro (https://chatgpt.com/explore/pro), visit https://chatgpt.com/codex/settings/usage to purchase more credits or try again at 7:17 PM."

test_case "review failure detail reports the codex ERROR line past the echoed prompt"
codex_quota_file="$TEST_TMP_DIR/codex-usage-limit-failed.md"
cat > "$codex_quota_file" <<'EOF'
# Agent: codex-standard
# Executor alias: codex-standard
# Configured provider: codex
# Configured model: gpt-5.6-sol
# Task ID: review-r1-implementation-logic-reviewer-1790632512
# Role: implementation-logic-reviewer
# Phase: review
# Prompt-Format: octopus-length-v1
You are running as a non-interactive subagent dispatched by Claude Octopus via codex exec.

If required review is unavailable or denied, report incomplete coverage without
claiming completion.

## Assigned task
You are the implementation-logic-reviewer specialist. Focus on: correctness and logic bugs, edge cases, regressions.
# Started: Mon Sep 28 18:55:17 -03 2026

## Output
```
(no output captured — codex-standard produced no stdout; check provider auth/config with 'orchestrate.sh doctor')
```

## Status: FAILED (exit code: 1)

## Error Log
```
OpenAI Codex v0.146.0
--------
workdir: /tmp/review-worktree
model: gpt-5.6-sol
provider: openai
approval: never
--------
user
You are running as a non-interactive subagent dispatched by Claude Octopus via codex exec.

If required review is unavailable or denied, report incomplete coverage without
claiming completion.

## Assigned task
You are the implementation-logic-reviewer specialist. Focus on: correctness and logic bugs, edge cases, regressions.
ERROR: You've hit your usage limit. Upgrade to Pro (https://chatgpt.com/explore/pro), visit https://chatgpt.com/codex/settings/usage to purchase more credits or try again at 7:17 PM.
ERROR: You've hit your usage limit. Upgrade to Pro (https://chatgpt.com/explore/pro), visit https://chatgpt.com/codex/settings/usage to purchase more credits or try again at 7:17 PM.
```
# Completed: Mon Sep 28 18:55:27 -03 2026
EOF
detail="$(review_result_failure_detail "$codex_quota_file")"
if [[ "$detail" == "$codex_usage_limit_error" ]]; then
    test_pass
else
    test_fail "codex failure cause was replaced by echoed prompt text: ${detail:-<empty>}"
fi

test_case "review failure detail does not report echoed prompt text when codex prints no ERROR line"
codex_crash_file="$TEST_TMP_DIR/codex-crash-failed.md"
cat > "$codex_crash_file" <<'EOF'
# Agent: codex-standard
# Prompt-Format: octopus-length-v1
You are a code reviewer. Review the following diff.
If required review is unavailable or denied, report incomplete coverage without
claiming completion.

## Diff
-    throw new Error(
+    throw new ClientError(
# Started: Mon Sep 28 18:55:17 -03 2026

## Output
```
(no output captured — codex-standard produced no stdout; check provider auth/config with 'orchestrate.sh doctor')
```

## Status: FAILED (exit code: 101)

## Error Log
```
OpenAI Codex v0.146.0
--------
model: gpt-5.6-sol
--------
user
You are a code reviewer. Review the following diff.
If required review is unavailable or denied, report incomplete coverage without
claiming completion.

## Diff
-    throw new Error(
+    throw new ClientError(
thread 'main' panicked at codex-rs/exec/src/lib.rs:88:14
```
EOF
detail="$(review_result_failure_detail "$codex_crash_file")"
if [[ "$detail" == "OpenAI Codex v0.146.0" ]]; then
    test_pass
else
    test_fail "echoed prompt text was reported as the failure cause: ${detail:-<empty>}"
fi

test_case "review failure detail prefers a stderr ERROR line over partial stdout"
partial_stdout_file="$TEST_TMP_DIR/codex-partial-stdout-failed.md"
cat > "$partial_stdout_file" <<'EOF'
# Agent: codex-standard
# Started: Mon Sep 28 18:55:17 -03 2026

## Output
```
Reviewing the diff for correctness and logic bugs.
```

## Status: FAILED (exit code: 1)

## Error Log
```
OpenAI Codex v0.146.0
--------
model: gpt-5.6-sol
--------
ERROR: You've hit your usage limit. Upgrade to Pro (https://chatgpt.com/explore/pro), visit https://chatgpt.com/codex/settings/usage to purchase more credits or try again at 7:17 PM.
```
EOF
detail="$(review_result_failure_detail "$partial_stdout_file")"
if [[ "$detail" == "$codex_usage_limit_error" ]]; then
    test_pass
else
    test_fail "stderr ERROR line lost to partial stdout: ${detail:-<empty>}"
fi

test_case "review failure detail prefers the last ERROR line in a transcript Output"
transcript_output_file="$TEST_TMP_DIR/codex-transcript-output-failed.md"
cat > "$transcript_output_file" <<'EOF'
# Agent: codex-standard
# Started: Mon Sep 28 18:55:17 -03 2026

## Output
```
OpenAI Codex v0.146.0
--------
model: gpt-5.6-sol
--------
user
If required review is unavailable or denied, report incomplete coverage without
claiming completion.

## Assigned task
You are the implementation-logic-reviewer specialist.
ERROR: You've hit your usage limit. Upgrade to Pro (https://chatgpt.com/explore/pro), visit https://chatgpt.com/codex/settings/usage to purchase more credits or try again at 7:17 PM.
```

## Status: FAILED (exit code: 1)
EOF
detail="$(review_result_failure_detail "$transcript_output_file")"
if [[ "$detail" == "$codex_usage_limit_error" ]]; then
    test_pass
else
    test_fail "transcript Output reported its first line instead of the error: ${detail:-<empty>}"
fi

test_case "review failure detail reads the message from a codex JSON error"
codex_json_error_file="$TEST_TMP_DIR/codex-json-error-failed.md"
cat > "$codex_json_error_file" <<'EOF'
# Agent: codex
# Started: Tue Jul 21 18:54:30 -03 2026

## Output
```
(no output captured)
```

## Status: FAILED (exit code: 1)

## Error Log
```
OpenAI Codex v0.144.0
--------
model: gpt-5.4
--------
user
You are a code reviewer. Review the following diff.
diff --git a/src/client.ts b/src/client.ts
-    throw new Error(
+    throw new ClientError(

## What to look for
Correctness and logic bugs.
ERROR: {
  "type": "error",
  "error": {
    "type": "invalid_request_error",
    "code": "invalid_value",
    "message": "Invalid value: 'max'. Supported values are: 'none', 'minimal', 'low', 'medium', 'high', and 'xhigh'.",
    "param": "reasoning.effort"
  },
  "status": 400
}
```
EOF
detail="$(review_result_failure_detail "$codex_json_error_file")"
if [[ "$detail" == "ERROR: Invalid value: 'max'. Supported values are: 'none', 'minimal', 'low', 'medium', 'high', and 'xhigh'." ]]; then
    test_pass
else
    test_fail "codex JSON error message was not reported: ${detail:-<empty>}"
fi

test_case "review failure detail prefers an error line over the first Output line"
output_error_file="$TEST_TMP_DIR/output-error-after-progress.md"
cat > "$output_error_file" <<'EOF'
# Agent result

## Output
```
Connecting to the provider API...
Error: 429 Too Many Requests (rate limit exceeded)
```

## Status: FAILED (Provider exited 1)
EOF
detail="$(review_result_failure_detail "$output_error_file")"
if [[ "$detail" == "Error: 429 Too Many Requests (rate limit exceeded)" ]]; then
    test_pass
else
    test_fail "Output error line lost to the first Output line: ${detail:-<empty>}"
fi

test_case "review failure detail keeps the first Output line when nothing looks like an error"
login_failure_file="$TEST_TMP_DIR/output-no-error-line.md"
cat > "$login_failure_file" <<'EOF'
# Agent result

## Output
```
Not logged in · Please run /login
Run claude, then /login, to sign in again.
```

## Status: FAILED (exit code: 1)
EOF
detail="$(review_result_failure_detail "$login_failure_file")"
if [[ "$detail" == "Not logged in · Please run /login" ]]; then
    test_pass
else
    test_fail "first Output line fallback changed: ${detail:-<empty>}"
fi

test_case "single-provider override keeps every review phase on the requested provider"
override_fleet="$({
    review_single_provider_is_available() { [[ "$1" == openai-compatible-agent ]]; }
    OCTO_ALLOWED_PROVIDERS=openai-compatible-agent OCTOPUS_REVIEW_SINGLE_PROVIDER=openai-compatible-agent build_review_fleet
})"
override_phase="$({
    review_single_provider_is_available() { [[ "$1" == openai-compatible-agent ]]; }
    OCTO_ALLOWED_PROVIDERS=openai-compatible-agent OCTOPUS_REVIEW_SINGLE_PROVIDER=openai-compatible-agent review_phase_provider claude-sonnet
})"
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

test_case "single-provider override fails closed without caller availability authority"
override_rc=0
override_output="$(unset AVAILABLE_AGENTS; OCTO_ALLOWED_PROVIDERS=openai-compatible-agent OCTOPUS_REVIEW_SINGLE_PROVIDER=openai-compatible-agent review_single_provider_override 2>/dev/null)" || override_rc=$?
if [[ "$override_rc" -ne 0 && -z "$override_output" ]]; then
    test_pass
else
    test_fail "override was accepted without an availability authority: rc=$override_rc output=[$override_output]"
fi

test_case "static provider inventory is not live availability authority"
override_rc=0
override_output="$({
    is_agent_available_v2() { return 1; }
    AVAILABLE_AGENTS=perplexity \
        OCTO_ALLOWED_PROVIDERS=perplexity \
        OCTOPUS_REVIEW_SINGLE_PROVIDER=perplexity \
        review_single_provider_override 2>/dev/null
})" || override_rc=$?
if [[ "$override_rc" -ne 0 && -z "$override_output" ]]; then
    test_pass
else
    test_fail "static inventory admitted an unavailable provider: rc=$override_rc output=[$override_output]"
fi

test_case "shared live resolver may admit a non-host single provider"
override_output="$({
    is_agent_available_v2() { [[ "$1" == perplexity ]]; }
    OCTO_ALLOWED_PROVIDERS=perplexity \
        OCTOPUS_REVIEW_SINGLE_PROVIDER=perplexity \
        review_single_provider_override 2>/dev/null
})"
if [[ "$override_output" == perplexity ]]; then
    test_pass
else
    test_fail "live resolver did not admit the available provider: output=[$override_output]"
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

test_case "provider report renders admitted contextual providers with canonical keys"
printf '%s\n' \
  'vibe|ok|completed' \
  'atlas-cloud|fallback|Atlas request failed' \
  'anthropic|ok|completed' > "$status_file"
report="$(env "HOME=${TEST_TMP_DIR}" bash -c '
    source "$1/scripts/lib/provider-registry.sh"
    source "$1/scripts/lib/review.sh"
    print_provider_report "$2"
' _ "$PROJECT_ROOT" "$status_file")"
if grep -Eq 'Vibe:[[:space:]]+.*OK' <<< "$report" && \
   grep -Eq 'Atlascloud:[[:space:]]+.*FALLBACK' <<< "$report" && \
   grep -Eq 'Claude:[[:space:]]+.*OK' <<< "$report" && \
   [[ "$report" == *'Atlas request failed'* ]]; then
    test_pass
else
    test_fail "provider report omitted or mis-keyed a contextual provider: $report"
fi

test_case "provider report keeps distinct models from the same provider"
: > "$status_file"
review_append_provider_status "$status_file" 'commandcode:model-one.v1' implementation-logic-reviewer ok completed
review_append_provider_status "$status_file" 'commandcode:model-two.v2' implementation-security-reviewer fallback 'second model failed'
status_records="$(cat "$status_file")"
report="$(env "HOME=${TEST_TMP_DIR}" bash -c '
    source "$1/scripts/lib/provider-registry.sh"
    source "$1/scripts/lib/review.sh"
    print_provider_report "$2"
' _ "$PROJECT_ROOT" "$status_file")"
if [[ "$status_records" == *'v2|commandcode|model-one.v1|ok|completed'* ]] && \
   [[ "$status_records" == *'v2|commandcode|model-two.v2|fallback|second model failed'* ]] && \
   grep -Eq 'Commandcode/model-one\.v1:.*OK' <<< "$report" && \
   grep -Eq 'Commandcode/model-two\.v2:.*FALLBACK' <<< "$report" && \
   [[ "$(grep -cE 'Commandcode/model-(one\.v1|two\.v2):' <<< "$report")" -eq 2 ]]; then
    test_pass
else
    test_fail "same-provider model identities collapsed in report: $report"
fi

test_case "v2 provider status keeps exact OpenAI-compatible registry identities"
: > "$status_file"
for exact_provider in openai-compatible openai-tools openai-compatible-agent; do
    review_append_provider_status "$status_file" "${exact_provider}:shared-model" implementation-logic-reviewer ok completed
done
status_records="$(cat "$status_file")"
report="$(env "HOME=${TEST_TMP_DIR}" bash -c '
    source "$1/scripts/lib/provider-registry.sh"
    source "$1/scripts/lib/review.sh"
    print_provider_report "$2"
' _ "$PROJECT_ROOT" "$status_file")"
if [[ "$status_records" == *'v2|openai-compatible|shared-model|ok|completed'* ]] && \
   [[ "$status_records" == *'v2|openai-tools|shared-model|ok|completed'* ]] && \
   [[ "$status_records" == *'v2|openai-compatible-agent|shared-model|ok|completed'* ]] && \
   [[ "$(grep -cE 'Openai-(compatible|tools|compatible-agent)/shared-model:.*OK' <<< "$report")" -eq 3 ]]; then
    test_pass
else
    test_fail "exact v2 provider identities collided: records=[$status_records] report=[$report]"
fi

test_case "legacy OpenAI-compatible status still aggregates by provider family"
printf '%s\n' \
  'openai-compatible|ok|completed' \
  'openai-tools|fallback|tool loop failed' \
  'openai-compatible-agent|ok|completed' > "$status_file"
report="$(env "HOME=${TEST_TMP_DIR}" bash -c '
    source "$1/scripts/lib/provider-registry.sh"
    source "$1/scripts/lib/review.sh"
    print_provider_report "$2"
' _ "$PROJECT_ROOT" "$status_file")"
if [[ "$(grep -cE 'Compatible:[[:space:]]+' <<< "$report")" -eq 1 ]] && \
   ! grep -Eq 'Openai-(tools|compatible-agent):' <<< "$report"; then
    test_pass
else
    test_fail "legacy provider family status stopped aggregating: $report"
fi

test_case "synthesis lifecycle event uses the canonical provider key"
synthesis_event="$(sed -n '/# #498: emit a synthesis lifecycle event/,/if \[\[ -n "$proof_dir" \]\]/p' "$PROJECT_ROOT/scripts/lib/review.sh")"
if grep -Fq 'provider="$synthesis_provider_key"' <<< "$synthesis_event" && \
   ! grep -Fq 'provider="$synthesis_provider"' <<< "$synthesis_event"; then
    test_pass
else
    test_fail "synthesis event does not use the canonical provider key"
fi

test_summary
