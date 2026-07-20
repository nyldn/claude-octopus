#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# fable5.sh — Claude Fable 5 (Mythos-class) mode detection and dispatch guards
# ═══════════════════════════════════════════════════════════════════════════════
# Fable 5 is opt-in only ($10/$50 MTok — 2x Opus 4.8) via an env pin. When a pin
# is detected, orchestration auto-enables three guards (auto-detect + banner,
# no user action needed):
#
#   1. Availability fallback — a Fable 5 dispatch falls back to Opus 4.8 only
#      when the provider explicitly rejects the model or reports it unavailable.
#   2. Effort clamp — xhigh/max clamp to high for Fable dispatches. Fable 5
#      effort applies per tool call; higher settings widen scope at 2x cost
#      without extending runs.
#   3. Refusal handling remains provider-owned; an ordinary content refusal is
#      not treated as model unavailability and does not silently upgrade cost.
#
# Detection is env-pin based only (deterministic; host session model ignored):
#   OCTOPUS_OPUS_MODEL=claude-fable-5        — opus seats run Fable 5
#   OCTOPUS_CLAUDE_SDK_MODEL=claude-fable-5  — claude-sdk seat runs Fable 5
#
# Master switch: OCTOPUS_FABLE5_MODE=auto (default) | off | on
#   off — all guards disabled even when a pin is present
#   on  — guards forced on regardless of pins
#
# Prompting guidance lives in skills/blocks/fable5-prompting.md.

FABLE5_MODEL_ID="claude-fable-5"
# Resolver/dispatch reroute target. Dot form matches models.sh registry ids;
# dispatch translates to the dash form the claude CLI expects.
FABLE5_REROUTE_MODEL="claude-opus-4.8"

fable5_opus_pinned() {
    [[ "${OCTOPUS_OPUS_MODEL:-}" == "$FABLE5_MODEL_ID" ]]
}

fable5_sdk_pinned() {
    [[ "${OCTOPUS_CLAUDE_SDK_MODEL:-}" == "$FABLE5_MODEL_ID" ]]
}

fable5_mode_active() {
    case "${OCTOPUS_FABLE5_MODE:-auto}" in
        off) return 1 ;;
        on)  return 0 ;;
    esac
    fable5_opus_pinned || fable5_sdk_pinned
}

# fable5_clamp_effort <effort> — echo the effort to actually use.
# Clamps xhigh/max to high when the opus seat is pinned to Fable 5 (the only
# seat whose dispatch consumes the effort mapping). Pass-through otherwise.
fable5_clamp_effort() {
    local effort="${1:-}"
    if fable5_mode_active && fable5_opus_pinned; then
        case "$effort" in
            xhigh|max)
                if declare -f log >/dev/null 2>&1; then
                    log "WARN" "Fable 5 effort clamp: ${effort} → high (per-call effort widens scope at 2x cost; OCTOPUS_FABLE5_MODE=off to disable)"
                fi
                echo "high"
                return 0
                ;;
        esac
    fi
    echo "$effort"
}

# Compatibility hook for model resolution. Fable remains primary for every
# role; spawn.sh performs the availability-only retry after provider failure.
fable5_maybe_reroute() {
    local model="${1:-}"
    echo "$model"
}

# True only for errors proving that Fable itself cannot currently be served.
# Generic failures and content refusals deliberately do not match.
fable5_model_unavailable() {
    local stderr_file="${1:-}"
    local stdout_file="${2:-}"
    local error_text=""
    [[ -n "$stderr_file" && -f "$stderr_file" ]] && error_text+=$(<"$stderr_file")
    [[ -n "$stdout_file" && -f "$stdout_file" ]] && error_text+=$'\n'$(<"$stdout_file")
    error_text="${error_text,,}"
    [[ "$error_text" == *"model not found"* || \
       "$error_text" == *"unknown model"* || \
       "$error_text" == *"model does not exist"* || \
       "$error_text" == *"model unavailable"* || \
       "$error_text" == *"model is unavailable"* || \
       "$error_text" == *"not available"* || \
       "$error_text" == *"capacity"* || \
       "$error_text" == *"overloaded"* || \
       "$error_text" == *"rate limit"* || \
       "$error_text" == *"429"* ]]
}

# fable5_banner — one-line stderr banner, once per process tree (guarded by an
# exported env marker so child shells stay quiet).
fable5_banner() {
    fable5_mode_active || return 0
    [[ -n "${_OCTO_FABLE5_BANNER_SHOWN:-}" ]] && return 0
    export _OCTO_FABLE5_BANNER_SHOWN=1
    echo "🐙 Fable 5 mode active — Opus 4.8 fallback only when Fable is unavailable, effort high (OCTOPUS_FABLE5_MODE=off to disable)" >&2
}
