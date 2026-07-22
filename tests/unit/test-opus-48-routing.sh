#!/bin/bash
set -euo pipefail

# tests/unit/test-opus-48-routing.sh
# Behavioral coverage for the Opus 4.8 routing change (v9.42).
#
# The companion test-cc-version-detection.sh only checks that the detection
# blocks and feature flags exist. This file exercises the actual resolution
# decisions the feature is about:
#   - opus_default_model() returns the right version for each flag combination
#   - get_agent_command "claude-opus-fast" emits the right --model on the wire
#   - get_agent_command "claude-opus" maps phase+complexity to the right effort
#
# A regression that, say, made the resolver return 4.7 when 4.8 is supported
# would pass the detection test but must fail here.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Opus 4.8 Routing (v9.42)"
export HOME="$TEST_TMP_DIR/opus-home"
mkdir -p "$HOME"

# dispatch.sh calls log() on its sandbox-validation error path; stub it so the
# functions can run outside orchestrate.sh. _BARE_OPT is empty in normal runs.
log() { :; }
export _BARE_OPT=""
export OCTOPUS_PLATFORM="${OCTOPUS_PLATFORM:-Linux}"
export PLUGIN_DIR="${PLUGIN_DIR:-$PROJECT_ROOT}"

# shellcheck disable=SC1091
source "$PROJECT_ROOT/scripts/lib/model-resolver.sh" 2>/dev/null || true
# shellcheck disable=SC1091
source "$PROJECT_ROOT/scripts/lib/agents.sh" 2>/dev/null || true
# shellcheck disable=SC1091
source "$PROJECT_ROOT/scripts/lib/dispatch.sh" 2>/dev/null || true

# Hard fail if the functions under test never loaded — a silent stub would make
# every assertion meaningless.
if ! declare -f opus_default_model >/dev/null 2>&1; then
    test_case "opus_default_model() is defined"
    test_fail "opus_default_model not sourced from model-resolver.sh"
    test_summary
    exit 1
fi
if ! declare -f get_agent_command >/dev/null 2>&1; then
    test_case "get_agent_command() is defined"
    test_fail "get_agent_command not sourced from dispatch.sh"
    test_summary
    exit 1
fi

reset_env() {
    unset OCTOPUS_OPUS_MODEL OCTOPUS_EFFORT_OVERRIDE OCTOPUS_OPUS_MODE
    unset SUPPORTS_OPUS_4_8 SUPPORTS_OPUS_4_7
    # orchestrate.sh initializes these to false before detection; mirror that so
    # agents.sh never trips over an unset var (it reads SUPPORTS_SDK_MODEL_CAPS bare).
    export SUPPORTS_EFFORT_COMMAND=false SUPPORTS_XHIGH_EFFORT=false SUPPORTS_SDK_MODEL_CAPS=false
}

# ═══════════════════════════════════════════════════════════════════════════════
# opus_default_model() — version preference + override
# ═══════════════════════════════════════════════════════════════════════════════

test_default_prefers_48() {
    test_case "opus_default_model → 4.8 when SUPPORTS_OPUS_4_8=true"
    reset_env
    export SUPPORTS_OPUS_4_8=true SUPPORTS_OPUS_4_7=true
    local got; got="$(opus_default_model)"
    [[ "$got" == "claude-opus-4.8" ]] && test_pass || test_fail "expected claude-opus-4.8, got $got"
}

test_default_falls_back_to_47() {
    test_case "opus_default_model → 4.7 when only 4.7 supported"
    reset_env
    export SUPPORTS_OPUS_4_8=false SUPPORTS_OPUS_4_7=true
    local got; got="$(opus_default_model)"
    [[ "$got" == "claude-opus-4.7" ]] && test_pass || test_fail "expected claude-opus-4.7, got $got"
}

test_default_falls_back_to_46() {
    test_case "opus_default_model → 4.6 when neither 4.8 nor 4.7 supported"
    reset_env
    export SUPPORTS_OPUS_4_8=false SUPPORTS_OPUS_4_7=false
    local got; got="$(opus_default_model)"
    [[ "$got" == "claude-opus-4.6" ]] && test_pass || test_fail "expected claude-opus-4.6, got $got"
}

test_default_respects_override() {
    test_case "opus_default_model → OCTOPUS_OPUS_MODEL override wins over 4.8"
    reset_env
    export SUPPORTS_OPUS_4_8=true OCTOPUS_OPUS_MODEL="claude-opus-4.6"
    local got; got="$(opus_default_model)"
    [[ "$got" == "claude-opus-4.6" ]] && test_pass || test_fail "expected claude-opus-4.6, got $got"
}

# ═══════════════════════════════════════════════════════════════════════════════
# claude-opus-fast — wire model flag (dot→dash on the CLI)
# ═══════════════════════════════════════════════════════════════════════════════

test_fast_uses_48_when_supported() {
    test_case "claude-opus-fast → claude-opus-4-8 --fast on 4.8 host"
    reset_env
    export SUPPORTS_OPUS_4_8=true
    local got; got="$(get_agent_command claude-opus-fast)"
    [[ "$got" == *"--model claude-opus-4-8 --fast"* ]] && test_pass || test_fail "expected 4-8 fast, got: $got"
}

test_fast_uses_46_without_48() {
    test_case "claude-opus-fast → claude-opus-4-6 --fast when 4.8 unsupported"
    reset_env
    export SUPPORTS_OPUS_4_8=false
    local got; got="$(get_agent_command claude-opus-fast)"
    [[ "$got" == *"--model claude-opus-4-6 --fast"* ]] && test_pass || test_fail "expected 4-6 fast, got: $got"
}

test_fast_legacy_pin_wins() {
    test_case "claude-opus-fast → 4-6 fast when OCTOPUS_OPUS_MODEL pins 4.6 even on 4.8 host"
    reset_env
    export SUPPORTS_OPUS_4_8=true OCTOPUS_OPUS_MODEL="claude-opus-4.6"
    local got; got="$(get_agent_command claude-opus-fast)"
    [[ "$got" == *"--model claude-opus-4-6 --fast"* ]] && test_pass || test_fail "expected legacy 4-6 fast, got: $got"
}

# ═══════════════════════════════════════════════════════════════════════════════
# claude-opus — phase→effort policy (high default, xhigh for deep work)
# ═══════════════════════════════════════════════════════════════════════════════

# Effort mapping needs the SDK model-caps path live.
enable_effort() {
    export SUPPORTS_SDK_MODEL_CAPS=true SUPPORTS_XHIGH_EFFORT=true SUPPORTS_EFFORT_COMMAND=true
}

test_effort_discover_is_high() {
    test_case "claude-opus discover → effort high"
    reset_env; enable_effort
    local got; got="$(get_agent_command claude-opus discover)"
    [[ "$got" == *"CLAUDE_CODE_EFFORT_LEVEL=high "* ]] && test_pass || test_fail "expected high, got: $got"
}

test_effort_develop_is_xhigh() {
    test_case "claude-opus develop → effort xhigh (complexity 3)"
    reset_env; enable_effort
    local got; got="$(get_agent_command claude-opus develop)"
    [[ "$got" == *"CLAUDE_CODE_EFFORT_LEVEL=xhigh "* ]] && test_pass || test_fail "expected xhigh, got: $got"
}

test_effort_deliver_is_xhigh() {
    test_case "claude-opus deliver → effort xhigh (deep review)"
    reset_env; enable_effort
    local got; got="$(get_agent_command claude-opus deliver)"
    [[ "$got" == *"CLAUDE_CODE_EFFORT_LEVEL=xhigh "* ]] && test_pass || test_fail "expected xhigh, got: $got"
}

test_effort_define_is_high() {
    test_case "claude-opus define → effort high (ordinary scoping)"
    reset_env; enable_effort
    local got; got="$(get_agent_command claude-opus define)"
    [[ "$got" == *"CLAUDE_CODE_EFFORT_LEVEL=high "* ]] && test_pass || test_fail "expected high, got: $got"
}

test_effort_override_respected() {
    test_case "claude-opus develop + OCTOPUS_EFFORT_OVERRIDE=low → low"
    reset_env; enable_effort
    export OCTOPUS_EFFORT_OVERRIDE=low
    local got; got="$(get_agent_command claude-opus develop)"
    [[ "$got" == *"CLAUDE_CODE_EFFORT_LEVEL=low "* ]] && test_pass || test_fail "expected low, got: $got"
}

test_effort_omitted_when_unsupported() {
    test_case "claude-opus → no effort env prefix when host lacks effort support"
    reset_env
    export SUPPORTS_EFFORT_COMMAND=false SUPPORTS_XHIGH_EFFORT=false
    local got; got="$(get_agent_command claude-opus develop)"
    if [[ "$got" != *"CLAUDE_CODE_EFFORT_LEVEL="* && "$got" == *"--model claude-opus-4-6"* ]]; then
        test_pass
    else
        test_fail "expected resolved 4.6 model with no effort prefix, got: $got"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# RUN
# ═══════════════════════════════════════════════════════════════════════════════

test_default_prefers_48
test_default_falls_back_to_47
test_default_falls_back_to_46
test_default_respects_override

test_fast_uses_48_when_supported
test_fast_uses_46_without_48
test_fast_legacy_pin_wins

test_effort_discover_is_high
test_effort_develop_is_xhigh
test_effort_deliver_is_xhigh
test_effort_define_is_high
test_effort_override_respected
test_effort_omitted_when_unsupported

test_summary
