#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# fable5.sh — Claude Fable 5 (Mythos-class) mode detection and dispatch guards
# ═══════════════════════════════════════════════════════════════════════════════
# Fable 5 is opt-in only ($10/$50 MTok — 2x Opus 5) via an env pin. When a pin
# is detected, orchestration auto-enables three guards (auto-detect + banner,
# no user action needed):
#
#   1. Security reroute — security-audit dispatches never target Fable 5; its
#      safety classifiers can refuse offensive-security phrasing even in
#      authorized audits. Rerouted to Opus 5 by default.
#   2. Effort clamp — xhigh/max clamp to high for Fable dispatches. Fable 5
#      effort applies per tool call; higher settings widen scope at 2x cost
#      without extending runs.
#   3. Refusal retry — the claude-sdk shim retries a failed/empty Fable 5
#      dispatch once on Opus 5 (see helpers/claude-sdk-exec.sh).
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
FABLE5_REROUTE_MODEL="claude-opus-5"

fable5_fallback_model() {
    printf '%s\n' "${OCTOPUS_FABLE5_FALLBACK_MODEL:-$FABLE5_REROUTE_MODEL}"
}

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
# dispatch. Swaps Fable 5 for the configured current-Opus fallback.
fable5_maybe_reroute() {
    local model="${1:-}"
    if [[ "$model" == "$FABLE5_MODEL_ID" ]] && fable5_mode_active \
        && fable5_is_security_dispatch "${2:-}" "${3:-}" "${4:-}"; then
        local fallback_model
        fallback_model="$(fable5_fallback_model)"
        if declare -f log >/dev/null 2>&1; then
            log "WARN" "Fable 5 security reroute: ${FABLE5_MODEL_ID} → ${fallback_model} (safety classifiers can refuse adversarial security phrasing)"
        fi
        echo "$fallback_model"
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
    log "INFO" "🐙 Fable 5 mode active — security passes reroute to $(fable5_fallback_model), effort clamps to high, refusal retry on $(fable5_fallback_model) (OCTOPUS_FABLE5_MODE=off to disable)"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Selective escalation (opt-in via progressive feature disclosure)
# ═══════════════════════════════════════════════════════════════════════════════
# The env pin above is all-or-nothing for a whole session. Escalation is the
# selective form: Opus 5 stays the lead, and only judgment-class dispatches move
# up to Fable 5.
#
# Escalation lives at the DISPATCH layer, next to fable5_maybe_reroute, and
# deliberately not in the model resolver. The resolver caches on
# provider/agent/phase/role/config-cksum with no liveness component, so a
# resolver-level escalation would keep serving a cached claude-fable-5 after the
# seat was marked quota-dead mid-session. Dispatch runs after the cache on every
# call, so that failure mode cannot occur here.
#
# Which roles escalate: `architect` and `strategist` only. Those are the actual
# opus-seat judgment roles in agent-utils.sh, and they are what /octo:prd,
# flow-define and skill-council dispatch. Deliberately excluded:
#   - security-reviewer — Fable's classifiers refuse authorized audit phrasing
#     (this is what fable5_maybe_reroute exists for).
#   - implementer-heavy — implementation, not judgment.
#   - code-reviewer     — adversarial review of Opus-authored work belongs on a
#     different vendor. Anthropic-family agreement is not an independent check
#     (skills/blocks/frontier-model-routing.md), so escalating review here would
#     buy an echo at 2x price. Fable authors and arbitrates; Codex opposes.

FABLE5_ESCALATION_FEATURE_ID="fable5-escalation"

# True when the user has consented to escalation. Consent is read through the
# feature ledger, which also honours OCTOPUS_FABLE5_ESCALATE as a session
# override in both directions.
fable5_escalation_consented() {
    if declare -f octo_features_enabled >/dev/null 2>&1; then
        octo_features_enabled "$FABLE5_ESCALATION_FEATURE_ID"
        return $?
    fi
    # features.sh unavailable: fall back to the bare env var so escalation is
    # still reachable, but never default it on.
    case "${OCTOPUS_FABLE5_ESCALATE:-}" in
        1|on|true|yes) return 0 ;;
    esac
    return 1
}

fable5_escalation_role_eligible() {
    case "${1:-}" in
        architect|strategist) return 0 ;;
        *) return 1 ;;
    esac
}

# fable5_maybe_escalate <model> <role> <agent_type> <phase>
# Echoes the model to dispatch: Fable 5 when every condition holds, the input
# model untouched otherwise. Always succeeds so callers can use it inline.
fable5_maybe_escalate() {
    local model="${1:-}" role="${2:-}" agent_type="${3:-}" phase="${4:-}"

    # Escalation only ever upgrades the default Opus seat. Anything else (an
    # explicit pin to another model, a Sonnet seat, an already-Fable model) is
    # left exactly as resolved.
    if [[ "$model" != "claude-opus-5" && "$model" != "claude-opus.5" ]]; then
        printf '%s\n' "$model"; return 0
    fi

    # An explicit user/session pin is Tier 1 and outranks a release default;
    # upgrading past it would violate "user config beats defaults".
    if [[ -n "${OCTOPUS_OPUS_MODEL:-}" ]]; then
        printf '%s\n' "$model"; return 0
    fi

    fable5_escalation_consented        || { printf '%s\n' "$model"; return 0; }
    fable5_escalation_role_eligible "$role" || { printf '%s\n' "$model"; return 0; }

    # Security work never escalates. maybe_reroute would catch it downstream,
    # but refusing here keeps the reason in one place and avoids a pointless
    # upgrade-then-downgrade in the logs.
    if fable5_is_security_dispatch "$role" "$agent_type" "$phase"; then
        printf '%s\n' "$model"; return 0
    fi

    # Headroom is reactive: there is no endpoint that reports remaining Fable 5
    # usage on a Claude seat, so a rate-limited dispatch marks the model dead
    # (quota-watcher) and escalation stands down for the rest of the TTL.
    if declare -f octo_quota_is_dead >/dev/null 2>&1 \
       && octo_quota_is_dead "$FABLE5_MODEL_ID"; then
        if declare -f log >/dev/null 2>&1; then
            log "WARN" "Fable 5 headroom exhausted; continuing on ${model} for this session"
        fi
        printf '%s\n' "$model"; return 0
    fi

    # One escalated dispatch per process tree. Councils, debates and review
    # fleets fan out over many seats; escalating each one is precisely the
    # spend the one-owner rule exists to prevent.
    if [[ -n "${_OCTO_FABLE5_ESCALATED:-}" ]]; then
        if declare -f log >/dev/null 2>&1; then
            log "INFO" "Fable 5 escalation already used this run; ${role} stays on ${model}"
        fi
        printf '%s\n' "$model"; return 0
    fi
    export _OCTO_FABLE5_ESCALATED=1

    if declare -f log >/dev/null 2>&1; then
        log "WARN" "🐙 Fable 5 escalation: ${role} ${model} → ${FABLE5_MODEL_ID} (\$10/\$50 per MTok, 2x Opus 5; /octo:whats-new to disable)"
    fi
    printf '%s\n' "$FABLE5_MODEL_ID"
    return 0
}

# fable5_clamp_effort_for_model <effort> <model> — clamp xhigh/max to high when
# the model actually being dispatched is Fable 5.
#
# fable5_clamp_effort above keys off the env pin, which is correct for the pinned
# session but misses an escalated dispatch (no pin present). Clamping on the
# consent flag instead would over-reach in the other direction: it would also
# clamp non-escalated Opus 5 dispatches in the same run, silently downgrading an
# explicit OCTOPUS_EFFORT_OVERRIDE=xhigh on work that never went near Fable.
# Keying off the resolved model is the only form that hits exactly the dispatches
# that need it.
#
# The reason for clamping at all: Fable 5 effort applies per tool call, so xhigh
# does not lengthen a run, it widens the scope of each step at twice the price.
fable5_clamp_effort_for_model() {
    local effort="${1:-}" model="${2:-}"
    if [[ "$model" == "$FABLE5_MODEL_ID" ]]; then
        case "$effort" in
            xhigh|max)
                if declare -f log >/dev/null 2>&1; then
                    log "WARN" "Fable 5 effort clamp: ${effort} → high (per-call effort widens scope at 2x cost)"
                fi
                printf '%s\n' "high"
                return 0
                ;;
        esac
    fi
    printf '%s\n' "$effort"
    return 0
}
