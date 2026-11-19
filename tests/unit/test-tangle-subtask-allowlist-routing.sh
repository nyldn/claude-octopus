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

test_case "Step 2 routes both subtask kinds through tangle_route_subtask_agent"
step2_setup=$(sed -n '/local tangle_reasoning_agent="agy"/,/fleet_dispatch_begin/p' "$WORKFLOWS")
coding_routed=$(printf '%s\n' "$step2_setup" | grep -c 'tangle_route_subtask_agent coding' || true)
reasoning_routed=$(printf '%s\n' "$step2_setup" | grep -c 'tangle_route_subtask_agent reasoning' || true)
legacy_check=$(printf '%s\n' "$step2_setup" | grep -c 'command -v "\$tangle_reasoning_agent"' || true)
if [[ "$coding_routed" -eq 1 && "$reasoning_routed" -eq 1 && "$legacy_check" -eq 0 ]]; then
    test_pass
else
    test_fail "Step 2 setup not routed (coding=$coding_routed reasoning=$reasoning_routed legacy=$legacy_check)"
fi

test_summary
