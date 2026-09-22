#!/usr/bin/env bash
# Provider subprocesses must not re-enter Octopus user-session routing hooks.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "provider child boundary"

for hook in "$PROJECT_ROOT/hooks/auto-router-inject.sh" "$PROJECT_ROOT/hooks/user-prompt-submit.sh" "$PROJECT_ROOT/hooks/done-criteria.sh" "$PROJECT_ROOT/hooks/github-work-queue-watch.sh"; do
    test_case "$(basename "$hook") has a provider-child fast path"
    if bash -n "$hook" 2>/dev/null && grep -q 'OCTOPUS_PROVIDER_CHILD' "$hook"; then
        test_pass
    else
        test_fail "hook is missing the provider-child guard: $hook"
    fi
done

test_case "Claude provider environment marks nested dispatches"
source "$PROJECT_ROOT/scripts/lib/provider-routing.sh"
OCTOPUS_SECURITY_V870=true
build_provider_env claude
if printf '%s\n' "${PROVIDER_ENV_ARRAY[@]}" | grep -cx 'OCTOPUS_PROVIDER_CHILD=true' >/dev/null; then
    test_pass
else
    test_fail "Claude provider environment did not set OCTOPUS_PROVIDER_CHILD"
fi

test_case "Codex provider environment marks nested dispatches"
build_provider_env codex
if printf '%s\n' "${PROVIDER_ENV_ARRAY[@]}" | grep -cx 'OCTOPUS_PROVIDER_CHILD=true' >/dev/null; then
    test_pass
else
    test_fail "Codex provider environment did not set OCTOPUS_PROVIDER_CHILD"
fi

test_case "council re-entrancy guard is forwarded across env -i (codex/agy) when set (#2718)"
# A seat dispatched under a non-Claude host must inherit OCTOPUS_COUNCIL_ACTIVE so a
# nested `orchestrate.sh council` (driven by the worktree's governed CLAUDE-OCTO.md)
# is refused instead of recursing. codex/agy run under `env -i`, which would strip it.
council_guard_ok=y
for prov in codex agy; do
    ( export OCTOPUS_COUNCIL_ACTIVE=1
      build_provider_env "$prov"
      printf '%s\n' "${PROVIDER_ENV_ARRAY[@]}" | grep -cx 'OCTOPUS_COUNCIL_ACTIVE=1' >/dev/null ) || council_guard_ok=n
done
# And it must NOT be injected when the caller has not set it.
( unset OCTOPUS_COUNCIL_ACTIVE
  build_provider_env codex
  printf '%s\n' "${PROVIDER_ENV_ARRAY[@]}" | grep -qE '^OCTOPUS_COUNCIL_ACTIVE=' ) && council_guard_ok=n
if [[ "$council_guard_ok" == y ]]; then
    test_pass
else
    test_fail "council re-entrancy guard not forwarded across env -i (or injected when unset)"
fi

test_case "nested council is refused before persistent initialization"
guard_home="$TEST_TMP_DIR/council-guard-home"
guard_workspace="$TEST_TMP_DIR/council-guard-workspace"
guard_project="$TEST_TMP_DIR/council-guard-project"
guard_output="$TEST_TMP_DIR/council-guard.out"
mkdir -p "$guard_home" "$guard_project"
guard_status=0
HOME="$guard_home" \
CLAUDE_PLUGIN_DATA="$guard_workspace" \
OCTOPUS_PROJECT_DIR="$guard_project" \
OCTOPUS_COUNCIL_ACTIVE=1 \
    bash "$PROJECT_ROOT/scripts/orchestrate.sh" council "Nested review" \
    >"$guard_output" 2>&1 || guard_status=$?

if [[ "$guard_status" -eq 2 ]] &&
   grep -q "Refusing to start a nested council" "$guard_output" &&
   [[ ! -e "$guard_home/.claude-octopus" ]] &&
   [[ ! -e "$guard_workspace" ]]; then
    test_pass
else
    test_fail "nested council reached persistent initialization (status=$guard_status)"
fi

test_case "nested council guard recognizes research options before command"
guard_option_home="$TEST_TMP_DIR/council-guard-option-home"
guard_option_workspace="$TEST_TMP_DIR/council-guard-option-workspace"
guard_option_project="$TEST_TMP_DIR/council-guard-option-project"
guard_option_output="$TEST_TMP_DIR/council-guard-option.out"
mkdir -p "$guard_option_home" "$guard_option_project"
guard_option_status=0
HOME="$guard_option_home" \
CLAUDE_PLUGIN_DATA="$guard_option_workspace" \
OCTOPUS_PROJECT_DIR="$guard_option_project" \
OCTOPUS_COUNCIL_ACTIVE=1 \
    bash "$PROJECT_ROOT/scripts/orchestrate.sh" --intensity deep council "Nested review" \
    >"$guard_option_output" 2>&1 || guard_option_status=$?

if [[ "$guard_option_status" -eq 2 ]] &&
   grep -q "Refusing to start a nested council" "$guard_option_output" &&
   [[ ! -e "$guard_option_home/.claude-octopus" ]] &&
   [[ ! -e "$guard_option_workspace" ]]; then
    test_pass
else
    test_fail "nested council option parsing reached persistent initialization (status=$guard_option_status)"
fi

test_case "provider-child user prompt hook emits no routing context"
hook_input='{"prompt":"implement this with octo:embrace"}'
hook_output=$(printf '%s' "$hook_input" | OCTOPUS_PROVIDER_CHILD=true bash "$PROJECT_ROOT/hooks/user-prompt-submit.sh")
if [[ -z "$hook_output" ]]; then
    test_pass
else
    test_fail "provider-child hook emitted routing context: $hook_output"
fi

test_summary
