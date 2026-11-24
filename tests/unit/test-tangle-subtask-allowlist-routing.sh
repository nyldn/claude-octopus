#!/usr/bin/env bash
# WHY: Tangle's Step 2 routed every [REASONING] subtask to agy whenever the agy
# binary was on PATH, ignoring OCTO_ALLOWED_PROVIDERS. spawn_agent then refused
# the seat ("produced no provider PID"), and that single refusal aborted the
# whole Tangle run after ~15 minutes of design review and decomposition, with
# the CODING subtasks already spawned. A provider outside the allowlist must be
# treated exactly like a missing binary, for [CODING] and [REASONING] alike.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT/scripts/lib/model-resolver.sh"
source "$PROJECT_ROOT/scripts/lib/provider-allowlist.sh"
source "$PROJECT_ROOT/scripts/lib/workflows.sh"

test_suite "tangle subtask routing honours the provider allowlist"

WORKFLOWS="$PROJECT_ROOT/scripts/lib/workflows.sh"
unset OCTO_ALLOWED_PROVIDERS
mkdir -p "$TEST_TMP_DIR/provider-allowlist"
export OCTOPUS_CONFIG_DIR="$TEST_TMP_DIR/provider-allowlist"

STUB_ALL="$TEST_TMP_DIR/bin-all"
STUB_CODEX="$TEST_TMP_DIR/bin-codex"
STUB_NONE="$TEST_TMP_DIR/bin-none"
mkdir -p "$STUB_ALL" "$STUB_CODEX" "$STUB_NONE"
for stub in "$STUB_ALL/agy" "$STUB_ALL/codex" "$STUB_CODEX/codex"; do
    printf '#!/bin/sh\nexit 0\n' > "$stub"
    chmod +x "$stub"
done

route() {
    local stub_dir="$1" allowlist="$2" kind="$3" agent="$4"
    (
        if [[ -n "$allowlist" ]]; then
            export OCTO_ALLOWED_PROVIDERS="$allowlist"
        else
            unset OCTO_ALLOWED_PROVIDERS
        fi
        PATH="$stub_dir:/usr/bin:/bin"
        tangle_route_subtask_agent "$kind" "$agent"
    )
}

expect_route() {
    local name="$1" expected="$2"
    shift 2
    test_case "$name"
    local got
    got=$(route "$@")
    if [[ "$got" == "$expected" ]]; then
        test_pass
    else
        test_fail "expected $expected, got $got"
    fi
}

expect_route "allowlist 'codex claude' sends [REASONING] away from an installed agy to codex" \
    codex "$STUB_ALL" "codex claude" reasoning agy
expect_route "allowlist 'claude' sends [REASONING] to claude-sonnet when agy and codex are both installed" \
    claude-sonnet "$STUB_ALL" "claude" reasoning agy
expect_route "allowlist 'claude' sends [CODING] away from codex to claude-sonnet" \
    claude-sonnet "$STUB_ALL" "claude" coding codex
expect_route "allowlist 'codex claude' keeps [CODING] on codex" \
    codex "$STUB_ALL" "codex claude" coding codex
expect_route "allowlist 'codex claude' moves a disallowed [CODING] override to codex" \
    codex "$STUB_ALL" "codex claude" coding agy
expect_route "no allowlist keeps an installed agy for [REASONING]" \
    agy "$STUB_ALL" "" reasoning agy
expect_route "no allowlist falls back from a missing agy to codex" \
    codex "$STUB_CODEX" "" reasoning agy
expect_route "no allowlist falls back to claude-sonnet when neither agy nor codex is installed" \
    claude-sonnet "$STUB_NONE" "" reasoning agy
expect_route "no allowlist leaves [CODING] alone even when its binary is missing" \
    codex "$STUB_NONE" "" coding codex

# Use the actual Step 2 setup, with a marker in place of fleet dispatch.
step2_setup=$(sed -n '/# Step 2: Parallel execution/,/^[[:space:]]*fleet_dispatch_begin$/p' "$WORKFLOWS")
run_step2_setup() (
    local subtasks="$1" parseable_subtask_count="$2"
    local task_group=fixture TMUX_MODE=false
    local RESULTS_DIR="$TEST_TMP_DIR"
    export OCTO_ALLOWED_PROVIDERS="$3"
    PATH="$STUB_NONE:/usr/bin:/bin"
    log() { printf '%s\n' "$2"; }
    fleet_dispatch_begin() { printf 'dispatch coding=%s\n' "$tangle_coding_agent"; }
    eval "$step2_setup"
)

test_case "Step 2 stops before dispatch when neither coding fallback is allowed"
if output=$(run_step2_setup '1. [CODING] Implement' 1 agy); then
    test_fail "unexpected dispatch: $output"
elif [[ "$output" == *"No permitted provider available for Tangle coding subtasks"* &&
        "$output" != *"dispatch coding="* ]]; then
    test_pass
else
    test_fail "missing coding routing error or unexpected dispatch: $output"
fi

test_case "Step 2 validates the reasoning route before dispatching the first coding subtask"
if output=$(run_step2_setup $'1. [CODING] Implement\n2. [REASONING] Analyze' 2 codex); then
    test_fail "unexpected dispatch: $output"
elif [[ "$output" == *"No permitted provider available for Tangle reasoning subtasks"* &&
        "$output" != *"dispatch coding="* ]]; then
    test_pass
else
    test_fail "missing reasoning routing error or unexpected dispatch: $output"
fi

test_case "Step 2 dispatches a coding-only plan when only the configured coding provider is eligible"
if output=$(run_step2_setup '1. [CODING] Implement' 1 codex) &&
    [[ "$output" == *"dispatch coding=codex"* ]]; then
    test_pass
else
    test_fail "coding-only dispatch failed: $output"
fi

test_summary
