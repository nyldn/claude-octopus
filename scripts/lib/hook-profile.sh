#!/usr/bin/env bash
# Intensity Profile System — unified profile for Claude Octopus (v9.8.0)
# Single knob: OCTO_PROFILE=budget|balanced|quality (default: balanced)
# Controls: hook gating, model selection hints, phase skipping, context verbosity
#
# Legacy compat: OCTO_HOOK_PROFILE still works (maps to OCTO_PROFILE)
# Per-hook override: OCTO_DISABLED_HOOKS=hook1,hook2 to skip specific hooks
# Kill switch: OCTO_PROFILE_GATING=off (disables hook gating, all hooks fire)
# ═══════════════════════════════════════════════════════════════════════════════

[[ -n "${_OCTOPUS_HOOK_PROFILE_LOADED:-}" ]] && return 0
_OCTOPUS_HOOK_PROFILE_LOADED=true

# Resolve profile: OCTO_PROFILE > OCTO_HOOK_PROFILE > balanced
# Map legacy names: minimal→budget, standard→balanced, strict→quality
_resolve_profile() {
    local raw="${OCTO_PROFILE:-${OCTO_HOOK_PROFILE:-balanced}}"
    case "$raw" in
        minimal) echo "budget" ;;
        standard) echo "balanced" ;;
        strict) echo "quality" ;;
        budget|balanced|quality) echo "$raw" ;;
        *) echo "balanced" ;;
    esac
}

# ── Hook Gating ──────────────────────────────────────────────────────────────

is_hook_enabled() {
    local hook_name="$1"
    local profile
    profile=$(_resolve_profile)

    # Kill switch
    [[ "${OCTO_PROFILE_GATING:-on}" == "off" ]] && return 0

    # Per-hook override
    if [[ -n "${OCTO_DISABLED_HOOKS:-}" ]]; then
        if echo ",$OCTO_DISABLED_HOOKS," | grep -q ",$hook_name,"; then
            return 1
        fi
    fi

    # Profile-based gating
    case "$profile" in
        budget)
            # Only essential hooks: session lifecycle, cost tracking, statusline
            case "$hook_name" in
                session-start-memory|session-end|octopus-statusline|octopus-hud|telemetry-webhook|cost-tracker|context-bridge|done-criteria|codex-exec-guard) return 0 ;;
                *) return 1 ;;
            esac
            ;;
        balanced)
            # Everything except expensive review/security gates
            case "$hook_name" in
                security-gate|code-quality-gate|architecture-gate|perf-gate|frontend-gate) return 1 ;;
                *) return 0 ;;
            esac
            ;;
        quality)
            # All hooks enabled
            return 0
            ;;
        *)
            return 0
            ;;
    esac
}

# ── Model Selection ──────────────────────────────────────────────────────────

# Get model recommendation for a given phase
# Args: phase (discover|define|develop|deliver|debate|synthesis)
# Returns: sonnet|opus|auto
get_profile_model_hint() {
    local phase="${1:-auto}"
    local profile
    profile=$(_resolve_profile)

    case "$profile" in
        budget)
            echo "sonnet"
            ;;
        balanced)
            case "$phase" in
                deliver|debate|synthesis) echo "opus" ;;
                *) echo "sonnet" ;;
            esac
            ;;
        quality)
            case "$phase" in
                discover|develop) echo "sonnet" ;;
                *) echo "opus" ;;
            esac
            ;;
        *)
            echo "auto"
            ;;
    esac
}

# ── Phase Skipping ───────────────────────────────────────────────────────────

# Check if a phase should be skipped
# Args: phase_name [context_hint]
# Returns: 0 if skip, 1 if run
should_skip_phase() {
    local phase="$1"
    local context="${2:-}"
    local profile
    profile=$(_resolve_profile)

    case "$profile" in
        budget)
            [[ "$phase" == "discover" && -n "$context" ]] && return 0
            ;;
        balanced)
            [[ "$phase" == "discover" && "$context" == "has_prior_results" ]] && return 0
            ;;
        quality)
            return 1
            ;;
    esac

    return 1
}

# ── Context Verbosity ────────────────────────────────────────────────────────

# Returns: compressed|standard|full
get_context_verbosity() {
    local profile
    profile=$(_resolve_profile)

    case "$profile" in
        budget)   echo "compressed" ;;
        balanced) echo "standard" ;;
        quality)  echo "full" ;;
        *)        echo "standard" ;;
    esac
}

# ── Display & Diagnostics ────────────────────────────────────────────────────

get_hook_profile() {
    _resolve_profile
}

get_profile_display() {
    local profile
    profile=$(_resolve_profile)
    local source="default"

    if [[ -n "${OCTO_PROFILE:-}" ]]; then
        source="env"
    elif [[ -n "${OCTO_HOOK_PROFILE:-}" ]]; then
        source="legacy env"
    elif [[ -n "${OCTO_PROFILE_AUTO:-}" ]]; then
        source="auto (${OCTO_PROFILE_AUTO})"
    fi

    echo "$profile ($source)"
}

# ── Intent Auto-Selection ────────────────────────────────────────────────────

# Suggest a profile from intent classification
# Args: intent_type
# Returns: budget|balanced|quality
suggest_profile_from_intent() {
    local intent="$1"
    local lower_intent
    lower_intent=$(printf '%s' "$intent" | tr '[:upper:]' '[:lower:]')

    case "$lower_intent" in
        *quick*|*question*|*lookup*|*check*|*simple*|*what*|*how*)
            echo "budget"
            ;;
        *deploy*|*release*|*production*|*ship*|*security*|*audit*|*review*)
            echo "quality"
            ;;
        *)
            echo "balanced"
            ;;
    esac
}
