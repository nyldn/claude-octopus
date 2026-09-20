#!/usr/bin/env bash
# Provider subprocesses must not re-enter Octopus user-session routing hooks.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
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

test_case "provider-child user prompt hook emits no routing context"
hook_input='{"prompt":"implement this with octo:embrace"}'
hook_output=$(printf '%s' "$hook_input" | OCTOPUS_PROVIDER_CHILD=true bash "$PROJECT_ROOT/hooks/user-prompt-submit.sh")
if [[ -z "$hook_output" ]]; then
    test_pass
else
    test_fail "provider-child hook emitted routing context: $hook_output"
fi

test_summary
