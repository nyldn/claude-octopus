#!/usr/bin/env bash
# Model-, transport-, and encoding-aware context admission contracts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "context admission"

log() { :; }
source "$PROJECT_ROOT/scripts/lib/models.sh"
source "$PROJECT_ROOT/scripts/lib/dispatch.sh"

test_case "exact Claude SDK Haiku seat cannot exceed its catalog window"
OCTOPUS_CLAUDE_SDK_CONTEXT_BUDGET=1000000
OCTOPUS_CONTEXT_OUTPUT_RESERVE_TOKENS=0
OCTOPUS_CONTEXT_OVERHEAD_TOKENS=0
if [[ "$(get_provider_context_limit 'claude-sdk:claude-haiku-4.5')" == 200000 ]]; then
  test_pass
else
  test_fail "exact Haiku seat inherited the generic 1M SDK limit"
fi

test_case "output and system-tool reserves reduce available input"
OCTOPUS_CLAUDE_SDK_CONTEXT_BUDGET=10000
OCTOPUS_CONTEXT_OUTPUT_RESERVE_TOKENS=1000
OCTOPUS_CONTEXT_OVERHEAD_TOKENS=500
if [[ "$(get_provider_context_limit 'claude-sdk:claude-haiku-4.5')" == 8500 ]]; then
  test_pass
else
  test_fail "context reserves were not deducted from the smallest ceiling"
fi

test_case "excessive configured override clamps to the model limit"
OCTOPUS_CLAUDE_SDK_CONTEXT_BUDGET=999999999
if [[ "$(get_provider_context_limit 'claude-sdk:claude-haiku-4.5')" == 198500 ]]; then
  test_pass
else
  test_fail "oversized override escaped the model catalog ceiling"
fi

test_case "CLI-effective transport limit can be stricter than the model"
OCTOPUS_CLAUDE_SDK_EFFECTIVE_CONTEXT_LIMIT=100000
if [[ "$(get_provider_context_limit 'claude-sdk:claude-haiku-4.5')" == 98500 ]]; then
  test_pass
else
  test_fail "transport limit did not constrain available input"
fi
unset OCTOPUS_CLAUDE_SDK_EFFECTIVE_CONTEXT_LIMIT

test_case "reserves that consume the whole context fail closed"
OCTOPUS_CLAUDE_SDK_CONTEXT_BUDGET=1000
OCTOPUS_CONTEXT_OUTPUT_RESERVE_TOKENS=900
OCTOPUS_CONTEXT_OVERHEAD_TOKENS=100
if get_provider_context_limit 'claude-sdk:claude-haiku-4.5' >/dev/null 2>&1; then
  test_fail "zero available input was admitted"
else
  test_pass
fi

test_case "non-ASCII prompts use a byte-aware token estimate"
OCTOPUS_CONTEXT_BUDGET=12
OCTOPUS_CONTEXT_OUTPUT_RESERVE_TOKENS=1
OCTOPUS_CONTEXT_OVERHEAD_TOKENS=1
OCTOPUS_OVERSIZE_STRATEGY=fail
emoji_prompt='😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀'
set +e
enforce_context_budget "$emoji_prompt" "" codex review >/dev/null 2>&1
emoji_rc=$?
set -e
if [[ "$emoji_rc" -eq 78 ]]; then
  test_pass
else
  test_fail "byte-dense prompt bypassed token admission (rc=$emoji_rc)"
fi

test_summary
