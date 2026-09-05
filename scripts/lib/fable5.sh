#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# fable5.sh — Claude Fable 5 (Mythos-class) mode detection and dispatch guards
# ═══════════════════════════════════════════════════════════════════════════════
# Fable 5.1 and the preserved Fable 5 ID are opt-in only ($10/$50 MTok — 2x
# Opus 5) via an env pin. When a pin
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
#   OCTOPUS_OPUS_MODEL=claude-fable-5-1        — opus seats run Fable 5.1
#   OCTOPUS_CLAUDE_SDK_MODEL=claude-fable-5-1  — claude-sdk seat runs Fable 5.1
#   OCTOPUS_CLAUDE_MODEL=claude-fable-5-1      — ordinary Claude seats run Fable 5.1
#   CLAUDE_MODEL=claude-fable-5-1              — host-level Claude pin runs Fable 5.1
#
# Master switch: OCTOPUS_FABLE5_MODE=auto (default) | off | on
#   off — all guards disabled even when a pin is present
#   on  — guards forced on regardless of pins
#
# Prompting guidance lives in skills/blocks/fable5-prompting.md.

FABLE5_MODEL_ID="claude-fable-5-1"
FABLE5_LEGACY_MODEL_ID="claude-fable-5"
# Resolver/dispatch reroute target. Dot form matches models.sh registry ids;
# dispatch translates to the dash form the claude CLI expects.
FABLE5_REROUTE_MODEL="claude-opus-5"

fable5_is_model() {
    case "${1:-}" in
        "$FABLE5_MODEL_ID"|"$FABLE5_LEGACY_MODEL_ID") return 0 ;;
    esac
    return 1
}

fable5_fallback_model() {
    local fallback_model="${OCTOPUS_FABLE5_FALLBACK_MODEL:-$FABLE5_REROUTE_MODEL}"
    # A fallback that still targets Fable defeats both the security reroute and
    # refusal recovery contracts. Fail safe to the built-in Opus target.
    if fable5_is_model "$fallback_model"; then
        fallback_model="$FABLE5_REROUTE_MODEL"
    fi
    printf '%s\n' "$fallback_model"
}

fable5_opus_pinned() {
    fable5_is_model "${OCTOPUS_OPUS_MODEL:-}"
}

fable5_sdk_pinned() {
    fable5_is_model "${OCTOPUS_CLAUDE_SDK_MODEL:-}"
}

fable5_mode_active() {
    case "${OCTOPUS_FABLE5_MODE:-auto}" in
        off) return 1 ;;
        on)  return 0 ;;
    esac
    fable5_opus_pinned || fable5_sdk_pinned ||
        fable5_is_model "${OCTOPUS_CLAUDE_MODEL:-}" ||
        fable5_is_model "${CLAUDE_MODEL:-}"
}

# fable5_prompt_within_budget <prompt-bytes>
#
# Fable has a model-specific pre-dispatch ceiling because its practical input
# behavior is narrower than the generic provider context limit. The inclusive
# default is 512 KiB. Invalid configuration is a usage/configuration error (2),
# not an oversized prompt (1), so callers can fail closed instead of silently
# routing under an unintended policy.
fable5_prompt_within_budget() {
    local prompt_bytes="${1:-0}"
    local ceiling="${OCTOPUS_FABLE5_MAX_INPUT_BYTES:-524288}"
    [[ "$prompt_bytes" =~ ^[0-9]+$ ]] || return 2
    [[ "$ceiling" =~ ^[0-9]+$ ]] || return 2
    [[ "$prompt_bytes" -le "$ceiling" ]]
}

# fable5_recovery_decision <requested-model> <failure-kind>
# Emits the recovery identity and reason used by refusal and quota handling.
fable5_recovery_decision() {
    local requested_model="${1:-}" failure_kind="${2:-}"
    local resolved_model="$requested_model" reason="no-fallback"
    if fable5_is_model "$requested_model"; then
        case "$failure_kind" in
            refusal) reason="refusal-fallback" ;;
            quota-exhausted) reason="quota-fallback" ;;
            *) return 2 ;;
        esac
        resolved_model="$(fable5_fallback_model)"
    fi
    jq -cn --arg requested_model "$requested_model" \
        --arg resolved_model "$resolved_model" --arg reason "$reason" \
        '{schema_version:"10.0", requested_model:$requested_model,
          resolved_model:$resolved_model, reason:$reason}'
}

# fable5_clamp_effort <effort> — echo the effort to actually use.
# Clamps xhigh/max to high when the opus seat is pinned to Fable 5 (the only
# seat whose dispatch consumes the effort mapping). Pass-through otherwise.
fable5_clamp_effort() {
    local effort="${1:-}"
    if fable5_mode_active && fable5_opus_pinned; then
        fable5_clamp_effort_for_model "$effort" "${OCTOPUS_OPUS_MODEL:-}"
        return $?
    fi
    echo "$effort"
}

# fable5_is_security_dispatch <role> <agent_type> <phase> — true when any of
# the dispatch identifiers indicate security work (security-auditor persona,
# squeeze red/blue workflow, red-team roles).
fable5_is_security_dispatch() {
    if declare -f octo_agent_spec_is_security_dispatch >/dev/null 2>&1; then
        if octo_agent_spec_is_security_dispatch "${1:-}" "${2:-}" "${3:-}"; then
            return 0
        fi
        return 1
    fi
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
    if fable5_is_model "$model" && [[ "${OCTOPUS_FABLE5_MODE:-auto}" != "off" ]] \
        && fable5_is_security_dispatch "${2:-}" "${3:-}" "${4:-}"; then
        local fallback_model
        fallback_model="$(fable5_fallback_model)"
        if declare -f log >/dev/null 2>&1; then
            log "WARN" "Fable 5 security reroute: ${model} → ${fallback_model} (safety classifiers can refuse adversarial security phrasing)"
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

FABLE5_ESCALATION_FEATURE_ID="fable5-routing"

# The user's Fable 5 routing policy, not a boolean. Values:
#   off              never (default)
#   escalate         judgment authoring: architect, strategist
#   escalate-reviews the above plus code review
#   on-demand        never automatic; reachable only by an explicit model pin
fable5_routing_policy() {
    if declare -f octo_features_choice >/dev/null 2>&1; then
        octo_features_choice "$FABLE5_ESCALATION_FEATURE_ID"
        return 0
    fi
    # features.sh unavailable: honour the env key directly, never defaulting on.
    printf '%s\n' "${OCTOPUS_FABLE5_ROUTING:-off}"
}

# Which roles the chosen policy escalates.
#
# `escalate-reviews` deliberately includes code-reviewer even though a Fable
# review of Opus-authored work is same-family agreement rather than an
# independent cross-vendor check. That tradeoff is stated in the choice
# description the user picked from, so it is theirs to make; it is simply not
# the default.
fable5_escalation_role_eligible() {
    local role="${1:-}" policy
    policy="$(fable5_routing_policy)"
    case "$policy" in
        escalate)
            case "$role" in architect|strategist) return 0 ;; esac
            ;;
        escalate-reviews)
            case "$role" in architect|strategist|code-reviewer|reviewer) return 0 ;; esac
            ;;
    esac
    return 1
}

# Kept as the coarse gate so the dispatch path reads plainly: any policy that
# escalates something at all.
fable5_escalation_consented() {
    case "$(fable5_routing_policy)" in
        escalate|escalate-reviews) return 0 ;;
    esac
    return 1
}

# Eligibility excludes the one-seat ownership claim so callers can evaluate the
# prompt-size gate before consuming the run's only Fable escalation.
fable5_escalation_candidate() {
    local model="${1:-}" role="${2:-}" agent_type="${3:-}" phase="${4:-}"
    [[ "$model" == "claude-opus-5" || "$model" == "claude-opus.5" ]] || return 1
    [[ -z "${OCTOPUS_OPUS_MODEL:-}" ]] || return 1
    fable5_escalation_consented || return 1
    fable5_escalation_role_eligible "$role" || return 1
    fable5_is_security_dispatch "$role" "$agent_type" "$phase" && return 1
    if declare -f octo_quota_is_dead >/dev/null 2>&1 && octo_quota_is_dead "$FABLE5_MODEL_ID"; then
        return 1
    fi
    return 0
}

# Atomically claim the single Fable escalation for a durable run. The contract
# directory makes this survive command substitutions and sibling subprocesses;
# isolated library tests without a run contract retain the process-local marker.
fable5_claim_escalation() {
    if declare -f octo_run_contract_dir >/dev/null 2>&1; then
        local marker claim_scope
        # A session ID can outlive several orchestrator invocations. Use the
        # explicit run ID when present; otherwise scope the one-seat claim to
        # this orchestrator process (stable across its subshells/backgrounds).
        claim_scope="${OCTOPUS_RUN_ID:-process-$$}"
        claim_scope="$(printf '%s' "$claim_scope" | sed 's/[^A-Za-z0-9_.:-]/_/g')"
        marker="$(octo_run_contract_dir)/.fable5-escalated-${claim_scope}"
        mkdir -p "$(dirname "$marker")" 2>/dev/null || return 1
        if mkdir "$marker" 2>/dev/null; then
            export _OCTO_FABLE5_ESCALATED=1
            return 0
        fi
        return 1
    fi
    [[ -z "${_OCTO_FABLE5_ESCALATED:-}" ]] || return 1
    export _OCTO_FABLE5_ESCALATED=1
    return 0
}

# fable5_maybe_escalate <model> <role> <agent_type> <phase>
# Echoes the model to dispatch: Fable 5 when every condition holds, the input
# model untouched otherwise. Always succeeds so callers can use it inline.
fable5_maybe_escalate() {
    local model="${1:-}" role="${2:-}" agent_type="${3:-}" phase="${4:-}"
    fable5_escalation_candidate "$model" "$role" "$agent_type" "$phase" \
        || { printf '%s\n' "$model"; return 0; }

    # One escalated dispatch per durable run. Councils, debates and review
    # fleets fan out over many seats; escalating each one is precisely the
    # spend the one-owner rule exists to prevent.
    if ! fable5_claim_escalation; then
        if declare -f log >/dev/null 2>&1; then
            log "INFO" "Fable 5 escalation already used this run; ${role} stays on ${model}"
        fi
        printf '%s\n' "$model"; return 0
    fi

    if declare -f log >/dev/null 2>&1; then
        log "WARN" "🐙 Fable 5 escalation: ${role} ${model} → ${FABLE5_MODEL_ID} (\$10/\$50 per MTok, 2x Opus 5; /octo:whats-new to disable)"
    fi
    printf '%s\n' "$FABLE5_MODEL_ID"
    return 0
}

# fable5_resolve_dispatch_model <model> <role> <agent-type> <phase> <bytes>
#
# Resolve escalation, security reroute, and the model-specific input ceiling as
# one auditable pre-dispatch decision. The requested identity is the model after
# opt-in escalation; the resolved identity is what may be serialized onto the
# provider command line. No provider command is executed here.
fable5_resolve_dispatch_model() {
    local original_model="${1:-}" role="${2:-}" agent_type="${3:-}"
    local phase="${4:-}" prompt_bytes="${5:-0}"
    local requested_model resolved_model reason="unchanged"

    # Reject an oversized eligible escalation before the atomic one-seat claim.
    # This leaves the single premium seat available for a later prompt that can
    # actually run on Fable.
    if fable5_escalation_candidate "$original_model" "$role" "$agent_type" "$phase"; then
        local preflight_rc=0
        fable5_prompt_within_budget "$prompt_bytes" || preflight_rc=$?
        [[ "$preflight_rc" -ne 2 ]] || return 2
        requested_model="$FABLE5_MODEL_ID"
        if [[ "$preflight_rc" -eq 1 ]]; then
            resolved_model="$(fable5_fallback_model)"
            reason="prompt-budget-fallback"
        elif [[ "${OCTOPUS_DISPATCH_PREVIEW:-false}" == "true" ]]; then
            resolved_model="$FABLE5_MODEL_ID"
            reason="fable-preview"
        elif fable5_claim_escalation; then
            resolved_model="$FABLE5_MODEL_ID"
            reason="fable-selected"
            if declare -f log >/dev/null 2>&1; then
                log "WARN" "🐙 Fable 5 escalation: ${role} ${original_model} → ${FABLE5_MODEL_ID} (single premium seat for this run)"
            fi
        else
            resolved_model="$original_model"
            reason="seat-cap-fallback"
        fi
        jq -cn --arg original_model "$original_model" \
            --arg requested_model "$requested_model" \
            --arg resolved_model "$resolved_model" --arg reason "$reason" \
            --arg prompt_bytes "$prompt_bytes" \
            '{schema_version:"10.0", original_model:$original_model,
              requested_model:$requested_model, resolved_model:$resolved_model,
              reason:$reason, prompt_bytes:($prompt_bytes | tonumber)}'
        return 0
    fi

    requested_model="$(fable5_maybe_escalate "$original_model" "$role" "$agent_type" "$phase")"
    resolved_model="$(fable5_maybe_reroute "$requested_model" "$role" "$agent_type" "$phase")"
    if [[ "$resolved_model" != "$requested_model" ]]; then
        reason="security-fallback"
    elif fable5_is_model "$requested_model"; then
        if fable5_prompt_within_budget "$prompt_bytes"; then
            reason="fable-selected"
        else
            local gate_rc=$?
            if [[ "$gate_rc" -eq 2 ]]; then
                return 2
            fi
            resolved_model="$(fable5_fallback_model)"
            reason="prompt-budget-fallback"
            if declare -f log >/dev/null 2>&1; then
                log "WARN" "Fable 5 input gate: ${prompt_bytes} bytes exceeds ${OCTOPUS_FABLE5_MAX_INPUT_BYTES:-524288}; using ${resolved_model} before dispatch"
            fi
        fi
    fi

    jq -cn --arg original_model "$original_model" \
        --arg requested_model "$requested_model" \
        --arg resolved_model "$resolved_model" --arg reason "$reason" \
        --arg prompt_bytes "$prompt_bytes" \
        '{schema_version:"10.0", original_model:$original_model,
          requested_model:$requested_model, resolved_model:$resolved_model,
          reason:$reason, prompt_bytes:($prompt_bytes | tonumber)}'
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
    if ! fable5_is_model "$model" || [[ "${OCTOPUS_FABLE5_MODE:-auto}" == "off" ]]; then
        printf '%s\n' "$effort"
        return 0
    fi

    local cap="${OCTOPUS_FABLE5_MAX_EFFORT:-high}" resolved="$effort"
    case "$cap" in
        high|xhigh|max) ;;
        *)
            if declare -f log >/dev/null 2>&1; then
                log "WARN" "Invalid OCTOPUS_FABLE5_MAX_EFFORT=${cap}; using high"
            fi
            cap="high"
            ;;
    esac
    case "$cap:$effort" in
        high:xhigh|high:max) resolved="high" ;;
        xhigh:max) resolved="xhigh" ;;
    esac
    if [[ "$resolved" != "$effort" ]] && declare -f log >/dev/null 2>&1; then
        log "WARN" "Fable 5 effort clamp: ${effort} → ${resolved} (raise OCTOPUS_FABLE5_MAX_EFFORT only for an explicit high-value run)"
    fi
    printf '%s\n' "$resolved"
    return 0
}
