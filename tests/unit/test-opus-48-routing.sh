#!/bin/bash
set -euo pipefail

# tests/unit/test-opus-48-routing.sh
# Behavioral coverage for current-Opus routing (Opus 5 primary, legacy fallback).
#
# The companion test-cc-version-detection.sh only checks that the detection
# blocks and feature flags exist. This file exercises the actual resolution
# decisions the feature is about:
#   - opus_default_model() returns the right version for each flag combination
#   - get_agent_command "claude-opus-fast" preserves the model while using the
#     supported standard subprocess shape
#   - get_agent_command "claude-opus" maps phase+complexity to the right effort
#
# A regression that, say, made the resolver return 4.7 when 4.8 is supported
# would pass the detection test but must fail here.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Current Opus Routing (Opus 5)"

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
    unset OCTOPUS_OPUS_MODEL OCTOPUS_EFFORT_OVERRIDE OCTOPUS_OPUS_MODE OCTOPUS_OPUS5_AUTO_XHIGH
    unset OCTOPUS_CLAUDE_ALLOWED_MODELS
    unset SUPPORTS_OPUS_5 SUPPORTS_OPUS_4_8 SUPPORTS_OPUS_4_7
    # orchestrate.sh initializes these to false before detection; mirror that so
    # agents.sh never trips over an unset var (it reads SUPPORTS_SDK_MODEL_CAPS bare).
    export SUPPORTS_EFFORT_COMMAND=false SUPPORTS_EFFORT_CLI_FLAG=false
    export SUPPORTS_XHIGH_EFFORT=false SUPPORTS_SDK_MODEL_CAPS=false
}

# ═══════════════════════════════════════════════════════════════════════════════
# opus_default_model() — version preference + override
# ═══════════════════════════════════════════════════════════════════════════════

test_default_prefers_5() {
    test_case "opus_default_model → Opus 5 when SUPPORTS_OPUS_5=true"
    reset_env
    export SUPPORTS_OPUS_5=true SUPPORTS_OPUS_4_8=true SUPPORTS_OPUS_4_7=true
    local got; got="$(opus_default_model)"
    [[ "$got" == "claude-opus-5" ]] && test_pass || test_fail "expected claude-opus-5, got $got"
}

test_default_falls_back_to_48() {
    test_case "opus_default_model → 4.8 when Opus 5 is unsupported"
    reset_env
    export SUPPORTS_OPUS_5=false SUPPORTS_OPUS_4_8=true SUPPORTS_OPUS_4_7=true
    local got; got="$(opus_default_model)"
    [[ "$got" == "claude-opus-4.8" ]] && test_pass || test_fail "expected claude-opus-4.8, got $got"
}

test_default_falls_back_to_47() {
    test_case "opus_default_model → 4.7 when only 4.7 supported"
    reset_env
    export SUPPORTS_OPUS_5=false SUPPORTS_OPUS_4_8=false SUPPORTS_OPUS_4_7=true
    local got; got="$(opus_default_model)"
    [[ "$got" == "claude-opus-4.7" ]] && test_pass || test_fail "expected claude-opus-4.7, got $got"
}

test_default_falls_back_to_46() {
    test_case "opus_default_model → 4.6 when neither 4.8 nor 4.7 supported"
    reset_env
    export SUPPORTS_OPUS_5=false SUPPORTS_OPUS_4_8=false SUPPORTS_OPUS_4_7=false
    local got; got="$(opus_default_model)"
    [[ "$got" == "claude-opus-4.6" ]] && test_pass || test_fail "expected claude-opus-4.6, got $got"
}

test_default_respects_override() {
    test_case "opus_default_model → OCTOPUS_OPUS_MODEL override wins over Opus 5"
    reset_env
    export SUPPORTS_OPUS_5=true SUPPORTS_OPUS_4_8=true OCTOPUS_OPUS_MODEL="claude-opus-4.6"
    local got; got="$(opus_default_model)"
    [[ "$got" == "claude-opus-4.6" ]] && test_pass || test_fail "expected claude-opus-4.6, got $got"
}

# ═══════════════════════════════════════════════════════════════════════════════
# claude-opus-fast — wire model flag (dot→dash on the CLI)
# ═══════════════════════════════════════════════════════════════════════════════

test_fast_uses_5_when_supported() {
    test_case "claude-opus-fast compatibility → standard claude-opus-5 dispatch"
    reset_env
    export SUPPORTS_OPUS_5=true SUPPORTS_OPUS_4_8=true
    local got; got="$(get_agent_command claude-opus-fast)"
    [[ "$got" == *"--model claude-opus-5"* && "$got" != *"--fast"* ]] && test_pass || test_fail "expected standard Opus 5 compatibility dispatch, got: $got"
}

test_fast_falls_back_to_48() {
    test_case "claude-opus-fast compatibility → standard 4.8 when Opus 5 unsupported"
    reset_env
    export SUPPORTS_OPUS_5=false SUPPORTS_OPUS_4_8=true
    local got; got="$(get_agent_command claude-opus-fast)"
    [[ "$got" == *"--model claude-opus-4-8"* && "$got" != *"--fast"* ]] && test_pass || test_fail "expected standard 4.8 compatibility dispatch, got: $got"
}

test_fast_legacy_pin_wins() {
    test_case "claude-opus-fast compatibility preserves explicit 4.6 pin"
    reset_env
    export SUPPORTS_OPUS_5=true SUPPORTS_OPUS_4_8=true OCTOPUS_OPUS_MODEL="claude-opus-4.6"
    local got; got="$(get_agent_command claude-opus-fast)"
    [[ "$got" == *"--model claude-opus-4-6"* && "$got" != *"--fast"* ]] && test_pass || test_fail "expected standard pinned 4.6 dispatch, got: $got"
}

test_fast_model_override_rejects_word_split_injection() {
    test_case "claude-opus-fast rejects a model override that would add CLI arguments"
    reset_env
    export SUPPORTS_OPUS_5=true
    export OCTOPUS_OPUS_MODEL="claude-opus-5 --dangerously-skip-permissions"
    local got=""
    if got="$(get_agent_command claude-opus-fast 2>/dev/null)"; then
        test_fail "unsafe fast-model override was serialized: $got"
    else
        test_pass
    fi
}

test_fast_honors_claude_model_allowlist() {
    test_case "claude-opus-fast honors OCTOPUS_CLAUDE_ALLOWED_MODELS"
    reset_env
    export SUPPORTS_OPUS_5=true OCTOPUS_CLAUDE_ALLOWED_MODELS="claude-opus-4.6"
    local got; got="$(get_agent_command claude-opus-fast)"
    [[ "$got" == *"--model claude-opus-4-6"* && "$got" != *"--fast"* ]] &&
        test_pass || test_fail "expected allowlisted standard 4.6 fallback, got: $got"
}

# ═══════════════════════════════════════════════════════════════════════════════
# claude-opus — phase→effort policy (high default, xhigh for deep work)
# ═══════════════════════════════════════════════════════════════════════════════

# Effort mapping needs the SDK model-caps path live.
enable_effort() {
    export SUPPORTS_SDK_MODEL_CAPS=true SUPPORTS_XHIGH_EFFORT=true
    export SUPPORTS_EFFORT_COMMAND=true SUPPORTS_EFFORT_CLI_FLAG=true
}

test_effort_discover_is_high() {
    test_case "claude-opus discover → effort high"
    reset_env; enable_effort
    local got; got="$(get_agent_command claude-opus discover)"
    [[ "$got" == *"--effort high"* ]] && test_pass || test_fail "expected high, got: $got"
}

test_effort_develop_is_high_on_opus5() {
    test_case "claude-opus develop → effort high by default on Opus 5"
    reset_env; enable_effort; export SUPPORTS_OPUS_5=true
    local got; got="$(get_agent_command claude-opus develop)"
    [[ "$got" == *"--effort high"* ]] && test_pass || test_fail "expected high, got: $got"
}

test_effort_deliver_is_high_on_opus5() {
    test_case "claude-opus deliver → effort high by default on Opus 5"
    reset_env; enable_effort; export SUPPORTS_OPUS_5=true
    local got; got="$(get_agent_command claude-opus deliver)"
    [[ "$got" == *"--effort high"* ]] && test_pass || test_fail "expected high, got: $got"
}

test_effort_opus5_xhigh_opt_in() {
    test_case "claude-opus develop → xhigh when OCTOPUS_OPUS5_AUTO_XHIGH=1"
    reset_env; enable_effort
    export SUPPORTS_OPUS_5=true OCTOPUS_OPUS5_AUTO_XHIGH=1
    local got; got="$(get_agent_command claude-opus develop)"
    [[ "$got" == *"--effort xhigh"* ]] && test_pass || test_fail "expected xhigh opt-in, got: $got"
    unset OCTOPUS_OPUS5_AUTO_XHIGH
}

test_effort_define_is_high() {
    test_case "claude-opus define → effort high (ordinary scoping)"
    reset_env; enable_effort
    local got; got="$(get_agent_command claude-opus define)"
    [[ "$got" == *"--effort high"* ]] && test_pass || test_fail "expected high, got: $got"
}

test_effort_override_respected() {
    test_case "claude-opus develop + OCTOPUS_EFFORT_OVERRIDE=low → low"
    reset_env; enable_effort
    export OCTOPUS_EFFORT_OVERRIDE=low
    local got; got="$(get_agent_command claude-opus develop)"
    [[ "$got" == *"--effort low"* ]] && test_pass || test_fail "expected low, got: $got"
}

test_effort_omitted_when_unsupported() {
    test_case "claude-opus → no effort flag when host lacks effort support"
    reset_env
    export SUPPORTS_OPUS_5=true
    export SUPPORTS_EFFORT_COMMAND=false SUPPORTS_EFFORT_CLI_FLAG=false SUPPORTS_XHIGH_EFFORT=false
    local got; got="$(get_agent_command claude-opus develop)"
    if [[ "$got" != *"--effort"* && "$got" == *"--model claude-opus-5"* ]]; then
        test_pass
    else
        test_fail "expected plain '--model opus' with no effort prefix, got: $got"
    fi
}

test_model_override_rejects_word_split_injection() {
    test_case "claude-opus rejects a model override that would add CLI arguments"
    reset_env
    export SUPPORTS_OPUS_5=true
    export OCTOPUS_OPUS_MODEL="claude-opus-5 --dangerously-skip-permissions"
    local got=""
    if got="$(get_agent_command claude-opus develop 2>/dev/null)"; then
        test_fail "unsafe model override was serialized: $got"
    else
        test_pass
    fi
}

test_opus_honors_claude_model_allowlist() {
    test_case "claude-opus honors OCTOPUS_CLAUDE_ALLOWED_MODELS"
    reset_env
    export SUPPORTS_OPUS_5=true OCTOPUS_CLAUDE_ALLOWED_MODELS="claude-opus-4.6"
    local got; got="$(get_agent_command claude-opus develop)"
    [[ "$got" == *"--model claude-opus-4-6"* && "$got" != *"--model claude-opus-5"* ]] &&
        test_pass || test_fail "expected allowlisted 4.6 fallback, got: $got"
}

test_opus_rejects_unsafe_allowlist_fallback() {
    test_case "claude-opus rejects an unsafe allowlist fallback"
    reset_env
    export SUPPORTS_OPUS_5=true
    export OCTOPUS_CLAUDE_ALLOWED_MODELS="claude-opus-4.6 --dangerously-skip-permissions"
    local got=""
    if got="$(get_agent_command claude-opus develop 2>/dev/null)"; then
        test_fail "unsafe allowlist fallback was serialized: $got"
    else
        test_pass
    fi
}

test_effort_override_rejects_word_split_injection() {
    test_case "claude-opus rejects an unsafe effort token before command serialization"
    reset_env
    export SUPPORTS_OPUS_5=true SUPPORTS_EFFORT_COMMAND=true SUPPORTS_EFFORT_CLI_FLAG=true
    export OCTOPUS_EFFORT_OVERRIDE="high EXTRA_ARG"
    # Exercise dispatch.sh's defensive path directly; agents.sh normally rejects
    # this override earlier, but command construction must remain safe on its own.
    unset -f get_effort_level
    local got=""
    if got="$(get_agent_command claude-opus develop 2>/dev/null)"; then
        test_fail "unsafe effort override was serialized: $got"
    else
        test_pass
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# RUN
# ═══════════════════════════════════════════════════════════════════════════════

test_default_prefers_5
test_default_falls_back_to_48
test_default_falls_back_to_47
test_default_falls_back_to_46
test_default_respects_override

test_fast_uses_5_when_supported
test_fast_falls_back_to_48
test_fast_legacy_pin_wins
test_fast_model_override_rejects_word_split_injection
test_fast_honors_claude_model_allowlist

test_effort_discover_is_high
test_effort_develop_is_high_on_opus5
test_effort_deliver_is_high_on_opus5
test_effort_opus5_xhigh_opt_in
test_effort_define_is_high
test_effort_override_respected
test_effort_omitted_when_unsupported
test_model_override_rejects_word_split_injection
test_opus_honors_claude_model_allowlist
test_opus_rejects_unsafe_allowlist_fallback
# Keep last: this test deliberately removes get_effort_level to cover dispatch's
# standalone fallback path.
test_effort_override_rejects_word_split_injection

test_summary
