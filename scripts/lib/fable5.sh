#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# fable5.sh — Claude Fable 5 (Mythos-class) mode detection and dispatch guards
# ═══════════════════════════════════════════════════════════════════════════════
# Fable 5 is opt-in only ($10/$50 MTok — 2x Opus 4.8) via an env pin. When a pin
# is detected, orchestration auto-enables three guards (auto-detect + banner,
# no user action needed):
#
#   1. Security reroute — security-audit dispatches never target Fable 5; its
#      safety classifiers can refuse offensive-security phrasing even in
#      authorized audits. Rerouted to Opus 4.8.
#   2. Effort clamp — xhigh/max clamp to high for Fable dispatches. Fable 5
#      effort applies per tool call; higher settings widen scope at 2x cost
#      without extending runs.
#   3. Refusal retry — the claude-sdk shim retries a failed/empty Fable 5
#      dispatch once on Opus 4.8 (see helpers/claude-sdk-exec.sh).
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

# fable5_is_security_dispatch <role> <agent_type> <phase> — true when any of
# the dispatch identifiers indicate security work (security-auditor persona,
# squeeze red/blue workflow, red-team roles).
fable5_is_security_dispatch() {
    local combined="${1:-} ${2:-} ${3:-}"
    case "$combined" in
        *security*|*squeeze*|*red-team*|*redteam*) return 0 ;;
        *) return 1 ;;
    esac
}

# fable5_maybe_reroute <model> <role> <agent_type> <phase> — echo the model to
# dispatch. Swaps Fable 5 for Opus 4.8 on security dispatches.
fable5_maybe_reroute() {
    local model="${1:-}"
    if [[ "$model" == "$FABLE5_MODEL_ID" ]] && fable5_mode_active \
        && fable5_is_security_dispatch "${2:-}" "${3:-}" "${4:-}"; then
        if declare -f log >/dev/null 2>&1; then
            log "WARN" "Fable 5 security reroute: ${FABLE5_MODEL_ID} → ${FABLE5_REROUTE_MODEL} (safety classifiers can refuse adversarial security phrasing)"
        fi
        echo "$FABLE5_REROUTE_MODEL"
        return 0
    fi
    echo "$model"
}

# fable5_banner — one-line stderr banner, once per process tree (guarded by an
# exported env marker so child shells stay quiet).
fable5_banner() {
    fable5_mode_active || return 0
    [[ -n "${_OCTO_FABLE5_BANNER_SHOWN:-}" ]] && return 0
    export _OCTO_FABLE5_BANNER_SHOWN=1
    echo "🐙 Fable 5 mode active — security passes reroute to Opus 4.8, effort clamps to high, refusal retry on (OCTOPUS_FABLE5_MODE=off to disable)" >&2
}
