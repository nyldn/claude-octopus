#!/bin/bash
# tests/unit/test-role-mapping-v929.sh
# Tests v9.29 role mapping refresh (Opus 4.7 for planning/security, GPT-5.4 for code-review/implementation).
# Ensures:
#   - New roles (code-reviewer, security-reviewer, implementer-heavy) resolve correctly
#   - Legacy alias (reviewer) still maps to code-reviewer equivalent
#   - OCTOPUS_LEGACY_ROLES=1 restores v9.28 mapping verbatim

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "v9.29 Role Mapping Refresh"

# agent-utils.sh references PLUGIN_DIR at source time — stub before loading.
export PLUGIN_DIR="${PLUGIN_DIR:-$PROJECT_ROOT}"
# Source the role mapping functions. agent-utils.sh references opus_default_model() from
# lib/model-resolver.sh and persona-loader functions — source both, tolerate missing helpers.
# shellcheck disable=SC1091
source "$PROJECT_ROOT/scripts/lib/model-resolver.sh" 2>/dev/null || true
# shellcheck disable=SC1091
source "$PROJECT_ROOT/scripts/lib/agent-utils.sh" 2>/dev/null || true

# Fallback opus_default_model stub if resolver didn't source (tests must run in isolation)
if ! declare -f opus_default_model >/dev/null 2>&1; then
    opus_default_model() { echo "claude-opus-4.7"; }
fi

# Force Opus 4.7 for deterministic assertions
export SUPPORTS_OPUS_4_7=true
unset OCTOPUS_OPUS_MODEL

# ═══════════════════════════════════════════════════════════════════════════════
# v9.29 DEFAULTS (OCTOPUS_LEGACY_ROLES unset)
# ═══════════════════════════════════════════════════════════════════════════════

test_architect_is_opus() {
    test_case "architect → claude-opus:claude-opus-4.7"
    unset OCTOPUS_LEGACY_ROLES
    local mapping
    mapping=$(get_role_mapping "architect")
    if [[ "$mapping" == "claude-opus:claude-opus-4.7" ]]; then
        test_pass
    else
        test_fail "expected claude-opus:claude-opus-4.7, got $mapping"
    fi
}

test_code_reviewer_is_gpt_54() {
    test_case "code-reviewer → codex-review:gpt-5.4"
    unset OCTOPUS_LEGACY_ROLES
    local mapping
    mapping=$(get_role_mapping "code-reviewer")
    if [[ "$mapping" == "codex-review:gpt-5.4" ]]; then
        test_pass
    else
        test_fail "expected codex-review:gpt-5.4, got $mapping"
    fi
}

test_reviewer_alias_for_code_reviewer() {
    test_case "reviewer (legacy alias) → same as code-reviewer"
    unset OCTOPUS_LEGACY_ROLES
    local old new
    old=$(get_role_mapping "reviewer")
    new=$(get_role_mapping "code-reviewer")
    if [[ "$old" == "$new" ]]; then
        test_pass
    else
        test_fail "reviewer=$old should equal code-reviewer=$new"
    fi
}

test_security_reviewer_is_opus() {
    test_case "security-reviewer → claude-opus:claude-opus-4.7"
    unset OCTOPUS_LEGACY_ROLES
    local mapping
    mapping=$(get_role_mapping "security-reviewer")
    if [[ "$mapping" == "claude-opus:claude-opus-4.7" ]]; then
        test_pass
    else
        test_fail "expected claude-opus:claude-opus-4.7, got $mapping"
    fi
}

test_implementer_stays_gpt_54() {
    test_case "implementer → codex:gpt-5.4 (unchanged from v9.28)"
    unset OCTOPUS_LEGACY_ROLES
    local mapping
    mapping=$(get_role_mapping "implementer")
    if [[ "$mapping" == "codex:gpt-5.4" ]]; then
        test_pass
    else
        test_fail "expected codex:gpt-5.4, got $mapping"
    fi
}

test_implementer_heavy_is_opus() {
    test_case "implementer-heavy → claude-opus:claude-opus-4.7 (opt-in)"
    unset OCTOPUS_LEGACY_ROLES
    local mapping
    mapping=$(get_role_mapping "implementer-heavy")
    if [[ "$mapping" == "claude-opus:claude-opus-4.7" ]]; then
        test_pass
    else
        test_fail "expected claude-opus:claude-opus-4.7, got $mapping"
    fi
}

test_strategist_is_opus_47() {
    test_case "strategist → claude-opus:claude-opus-4.7 (resolver picks 4.7)"
    unset OCTOPUS_LEGACY_ROLES
    local mapping
    mapping=$(get_role_mapping "strategist")
    if [[ "$mapping" == "claude-opus:claude-opus-4.7" ]]; then
        test_pass
    else
        test_fail "expected claude-opus:claude-opus-4.7, got $mapping"
    fi
}

test_synthesizer_is_sonnet() {
    test_case "synthesizer → claude:claude-sonnet-4.6 (unchanged)"
    unset OCTOPUS_LEGACY_ROLES
    local mapping
    mapping=$(get_role_mapping "synthesizer")
    if [[ "$mapping" == "claude:claude-sonnet-4.6" ]]; then
        test_pass
    else
        test_fail "expected claude:claude-sonnet-4.6, got $mapping"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# LEGACY OPT-OUT (OCTOPUS_LEGACY_ROLES=1 restores v9.28)
# ═══════════════════════════════════════════════════════════════════════════════

test_legacy_architect_is_gpt_54() {
    test_case "OCTOPUS_LEGACY_ROLES=1: architect → codex:gpt-5.4 (v9.28 behavior)"
    export OCTOPUS_LEGACY_ROLES=1
    local mapping
    mapping=$(get_role_mapping "architect")
    unset OCTOPUS_LEGACY_ROLES
    if [[ "$mapping" == "codex:gpt-5.4" ]]; then
        test_pass
    else
        test_fail "expected codex:gpt-5.4 under legacy, got $mapping"
    fi
}

test_legacy_security_reviewer_falls_back() {
    test_case "OCTOPUS_LEGACY_ROLES=1: security-reviewer → codex-review:gpt-5.4 (unified v9.28 reviewer)"
    export OCTOPUS_LEGACY_ROLES=1
    local mapping
    mapping=$(get_role_mapping "security-reviewer")
    unset OCTOPUS_LEGACY_ROLES
    if [[ "$mapping" == "codex-review:gpt-5.4" ]]; then
        test_pass
    else
        test_fail "expected codex-review:gpt-5.4 under legacy, got $mapping"
    fi
}

test_legacy_strategist_is_opus_46() {
    test_case "OCTOPUS_LEGACY_ROLES=1: strategist → claude-opus-4.6 (v9.28 literal)"
    export OCTOPUS_LEGACY_ROLES=1
    local mapping
    mapping=$(get_role_mapping "strategist")
    unset OCTOPUS_LEGACY_ROLES
    if [[ "$mapping" == "claude-opus:claude-opus-4.6" ]]; then
        test_pass
    else
        test_fail "expected claude-opus:claude-opus-4.6 under legacy, got $mapping"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# AGENT/MODEL SPLIT HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

test_get_role_agent_for_architect() {
    test_case "get_role_agent architect → claude-opus"
    unset OCTOPUS_LEGACY_ROLES
    local agent
    agent=$(get_role_agent "architect")
    if [[ "$agent" == "claude-opus" ]]; then
        test_pass
    else
        test_fail "expected claude-opus, got $agent"
    fi
}

test_get_role_model_for_code_reviewer() {
    test_case "get_role_model code-reviewer → gpt-5.4"
    unset OCTOPUS_LEGACY_ROLES
    local model
    model=$(get_role_model "code-reviewer")
    if [[ "$model" == "gpt-5.4" ]]; then
        test_pass
    else
        test_fail "expected gpt-5.4, got $model"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# RUN
# ═══════════════════════════════════════════════════════════════════════════════

test_architect_is_opus
test_code_reviewer_is_gpt_54
test_reviewer_alias_for_code_reviewer
test_security_reviewer_is_opus
test_implementer_stays_gpt_54
test_implementer_heavy_is_opus
test_strategist_is_opus_47
test_synthesizer_is_sonnet
test_legacy_architect_is_gpt_54
test_legacy_security_reviewer_falls_back
test_legacy_strategist_is_opus_46
test_get_role_agent_for_architect
test_get_role_model_for_code_reviewer

test_summary
