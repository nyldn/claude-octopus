#!/usr/bin/env bash
# Claude Octopus — Dynamic Fleet Builder
# ═══════════════════════════════════════════════════════════════════════════════
# Single source of truth for building agent fleets from available providers.
# Replaces hardcoded fleet tables in skill files.
#
# Usage: build-fleet.sh <workflow> <intensity> [prompt]
#   workflow:  research | review | security | architecture | debate
#   intensity: quick | standard | deep
#   prompt:    (optional) the user's prompt, used for context-aware assignment
#
# Output: one line per agent in format:
#   agent_type|label|perspective_prompt
#
# Model family diversity is enforced: at least 2 distinct families when possible.
# Compatible with bash 3.2 (macOS) — no associative arrays, no ${var,,}.
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROVIDER_ALLOWLIST_LIB="${SCRIPT_DIR}/../lib/provider-allowlist.sh"
if [[ ! -r "$PROVIDER_ALLOWLIST_LIB" ]]; then
    printf 'ERROR: required provider allowlist library is not readable: %s\n' "$PROVIDER_ALLOWLIST_LIB" >&2
    exit 1
fi
if ! source "$PROVIDER_ALLOWLIST_LIB"; then
    printf 'ERROR: failed to load required provider allowlist library: %s\n' "$PROVIDER_ALLOWLIST_LIB" >&2
    exit 1
fi
source "${SCRIPT_DIR}/../lib/provider-registry.sh"
source "${SCRIPT_DIR}/../lib/provider-policy.sh"
source "${SCRIPT_DIR}/../lib/agent-spec.sh"
source "${SCRIPT_DIR}/../lib/model-resolver.sh"
source "${SCRIPT_DIR}/../lib/review.sh"

WORKFLOW="${1:-research}"
INTENSITY="${2:-standard}"
PROMPT="${3:-}"

log() {
    local level="$1"
    shift
    printf '[%s] %s\n' "$level" "$*" >&2
}

# ── Provider → Model Family Mapping ──────────────────────────────────────────
get_family() {
    octo_agent_spec_model_family "$1"
}
# ── Provider Detection ────────────────────────────────────────────────────────
# check-providers.sh is the single admission gate for both the activation banner
# and fleet construction. Do not duplicate binary/auth probes here: that was the
# source of #799's green-banner/failed-dispatch split.
AVAILABLE_CLI=()
PROVIDER_CHECKER="${OCTOPUS_PROVIDER_CHECKER:-${SCRIPT_DIR}/check-providers.sh}"
if PROVIDER_STATUS_OUTPUT="$(bash "$PROVIDER_CHECKER" 2>/dev/null)"; then
    :
else
    provider_checker_status=$?
    log ERROR "provider admission check failed: $PROVIDER_CHECKER"
    exit "$provider_checker_status"
fi

provider_status_is_available() {
    local provider="$1"
    case $'\n'"$PROVIDER_STATUS_OUTPUT"$'\n' in
        *$'\n'"${provider}:available"$'\n'*) return 0 ;;
        *) return 1 ;;
    esac
}

# Preference order for primary slot assignment. Every entry is still admitted
# only when the shared status source reports exactly `available`.
for _provider in codex commandcode grok agy copilot qwen cursor-agent opencode \
    ollama vibe kimi claude-sdk openrouter openai-compatible perplexity; do
    # Fleet seats are consultative/read-only. Kimi's non-interactive mode
    # auto-approves tools and cannot enforce that boundary, so it remains an
    # implementation provider but is not eligible for these fleets.
    [[ "$_provider" == "kimi" ]] && continue
    provider_status_is_available "$_provider" && \
        octo_provider_allowed "$_provider" && \
        AVAILABLE_CLI+=("$_provider")
done
# Atlas Cloud's canonical provider status is `atlascloud`, while its executable
# agent type is `atlascloud-agent` (the Python tool-loop dispatch shim).
provider_status_is_available atlascloud && \
    octo_provider_allowed atlascloud-agent && \
    AVAILABLE_CLI+=("atlascloud-agent")

CLI_COUNT=0
if [[ -n "${AVAILABLE_CLI[*]:-}" ]]; then
    CLI_COUNT=${#AVAILABLE_CLI[@]}
fi

# ── Helpers ───────────────────────────────────────────────────────────────────

# Check if a value is in a space-delimited string (bash 3.2 safe set membership)
_contains() { [[ " $1 " == *" $2 "* ]]; }

# Check if provider is available
is_available() {
    local p="$1"
    p="${p%%:*}"
    _contains "${AVAILABLE_CLI[*]:-}" "$p"
}

# review.sh validates identity, capability, and policy. This caller supplies
# the authoritative live admission decision produced by check-providers.sh.
review_single_provider_is_available() {
    local canonical="$1" executor="$2" status_provider="$1" available_executor="$2"
    case "$canonical" in
        claude)
            # Claude is the host runtime and is intentionally absent from
            # AVAILABLE_CLI/check-providers admission.
            return 0
            ;;
        atlascloud)
            status_provider=atlascloud
            available_executor=atlascloud-agent
            ;;
        openai-tools|openai-compatible-agent)
            status_provider=openai-compatible
            available_executor=openai-compatible
            ;;
    esac
    provider_status_is_available "$status_provider" && is_available "$available_executor"
}

# Pick first available provider from a preference list, with fallback
pick_provider() {
    local fallback="${1}"
    shift
    for p in "$@"; do
        is_available "$p" && echo "$p" && return 0
    done
    if octo_provider_allowed "$fallback"; then
        echo "$fallback"
    elif [[ -n "${AVAILABLE_CLI[*]:-}" ]]; then
        echo "${AVAILABLE_CLI[0]}"
    else
        echo ""
    fi
}

# Build family-diverse provider ordering from available CLIs
# Outputs providers sorted: one per family first, then remaining
build_diverse_order() {
    local used_families=""
    local diverse_first=""
    local diverse_rest=""

    # Preferred order for primary diversity.
    for p in codex commandcode agy copilot qwen grok cursor-agent opencode ollama \
        vibe kimi claude-sdk openrouter openai-compatible atlascloud-agent perplexity; do
        is_available "$p" || continue
        local fam
        fam=$(get_family "$p")
        if ! _contains "$used_families" "$fam"; then
            diverse_first="${diverse_first:+$diverse_first }$p"
            used_families="${used_families:+$used_families }$fam"
        else
            diverse_rest="${diverse_rest:+$diverse_rest }$p"
        fi
    done
    echo "${diverse_first}${diverse_rest:+ $diverse_rest}"
}

emit() {
    local provider="$1" label="$2" perspective="$3"
    # Keep allowlist enforcement at the final output boundary so defaults,
    # fallbacks, and future fleet builders cannot emit an unauthorized seat.
    octo_provider_allowed "$provider" || return 0
    perspective="${perspective//$'\r'/ }"
    perspective="${perspective//$'\n'/ }"
    printf '%s|%s|%s\n' "$provider" "$label" "$perspective"
}

emit_if_allowed() {
    emit "$@"
}

# Count unique families across given providers + implicit anthropic
count_families() {
    local families="anthropic"  # Claude is always present
    for p in "$@"; do
        local fam
        fam=$(get_family "$p")
        _contains "$families" "$fam" || families="$families $fam"
    done
    echo "$families" | wc -w | tr -d ' '
}

# ── Research Fleet ────────────────────────────────────────────────────────────
build_research_fleet() {
    local diverse_order
    diverse_order=$(build_diverse_order)
    # shellcheck disable=SC2206
    local diverse_arr=($diverse_order)
    local dcount=${#diverse_arr[@]}

    # If no CLI providers at all, just use claude-sonnet
    if [[ $dcount -eq 0 ]]; then
        if octo_provider_allowed claude-sonnet; then
            diverse_arr=(claude-sonnet)
            dcount=1
        else
            log ERROR "no eligible read-only provider is available for the $WORKFLOW fleet"
            return 1
        fi
    fi

    case "$INTENSITY" in
        quick)
            local p1="${diverse_arr[0]}"
            local p2="${diverse_arr[1]:-claude-sonnet}"
            # Ensure diversity
            if [[ "$(get_family "$p1")" == "$(get_family "$p2")" && "$p1" != "claude-sonnet" ]]; then
                p2="claude-sonnet"
            fi
            emit "$p1" "Problem Analysis" "Analyze the problem space: $PROMPT. Focus on understanding constraints, requirements, and user needs."
            emit "$p2" "Ecosystem Overview" "Research existing solutions and patterns for: $PROMPT. What has been done before? What worked, what failed?"
            ;;
        standard)
            local idx=0
            emit "${diverse_arr[$((idx % dcount))]}" "Problem Analysis" "Analyze the problem space: $PROMPT. Focus on understanding constraints, requirements, and user needs."
            idx=$((idx + 1))
            emit "${diverse_arr[$((idx % dcount))]}" "Ecosystem Overview" "Research existing solutions and patterns for: $PROMPT. What has been done before? What worked, what failed?"
            idx=$((idx + 1))
            emit_if_allowed "claude-sonnet" "Edge Cases" "Explore edge cases and potential challenges for: $PROMPT. What could go wrong? What's often overlooked?"
            emit "${diverse_arr[$((idx % dcount))]}" "Feasibility" "Investigate technical feasibility and dependencies for: $PROMPT. What are the prerequisites?"
            idx=$((idx + 1))

            # Codebase analysis if inside git repo
            if git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
                local src
                src=$(find . -maxdepth 2 -type f \( -name "*.ts" -o -name "*.py" -o -name "*.go" -o -name "*.rs" -o -name "*.java" -o -name "*.js" \) 2>/dev/null | head -1)
                if [[ -n "${src:-}" ]]; then
                    emit_if_allowed "claude-sonnet" "Codebase Analysis" "Analyze the LOCAL CODEBASE in the current directory for: $PROMPT. Run: find . -type f -name '*.ts' -o -name '*.py' -o -name '*.js' | head -30, then read key files. Report: tech stack, architecture patterns, file structure, coding conventions, and how they relate to the prompt. Focus on ACTUAL code, not hypotheticals."
                fi
            fi
            ;;
        deep)
            local idx=0
            emit "${diverse_arr[$((idx % dcount))]}" "Problem Analysis" "Analyze the problem space: $PROMPT. Focus on understanding constraints, requirements, and user needs."
            idx=$((idx + 1))
            emit "${diverse_arr[$((idx % dcount))]}" "Ecosystem Overview" "Research existing solutions and patterns for: $PROMPT. What has been done before? What worked, what failed?"
            idx=$((idx + 1))
            emit_if_allowed "claude-sonnet" "Edge Cases" "Explore edge cases and potential challenges for: $PROMPT. What could go wrong? What's often overlooked?"
            emit "${diverse_arr[$((idx % dcount))]}" "Feasibility" "Investigate technical feasibility and dependencies for: $PROMPT. What are the prerequisites?"
            idx=$((idx + 1))

            # Codebase analysis if inside git repo
            if git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
                local src
                src=$(find . -maxdepth 2 -type f \( -name "*.ts" -o -name "*.py" -o -name "*.go" -o -name "*.rs" -o -name "*.java" -o -name "*.js" \) 2>/dev/null | head -1)
                if [[ -n "${src:-}" ]]; then
                    emit_if_allowed "claude-sonnet" "Codebase Analysis" "Analyze the LOCAL CODEBASE in the current directory for: $PROMPT. Run: find . -type f -name '*.ts' -o -name '*.py' -o -name '*.js' | head -30, then read key files. Report: tech stack, architecture patterns, file structure, coding conventions, and how they relate to the prompt. Focus on ACTUAL code, not hypotheticals."
                fi
            fi

            emit "${diverse_arr[$((idx % dcount))]}" "Cross-Synthesis" "Synthesize cross-cutting concerns for: $PROMPT. What themes emerge across problem space, solutions, and feasibility?"
            idx=$((idx + 1))

            # Web research via Perplexity
            if is_available perplexity; then
                emit "perplexity" "Web Research" "Search the live web for the latest information about: $PROMPT. Find recent articles, documentation, blog posts, GitHub repos, and community discussions. Include source URLs and publication dates. Focus on information from the last 12 months that may not be in training data."
            fi

            # Bonus: any remaining unused providers get unique perspectives
            local used_providers=""
            for ((i=0; i<idx; i++)); do
                local up="${diverse_arr[$((i % dcount))]}"
                _contains "$used_providers" "$up" || used_providers="$used_providers $up"
            done
            octo_provider_allowed claude-sonnet && used_providers="$used_providers claude-sonnet"
            is_available perplexity && used_providers="$used_providers perplexity"

            for extra in "${AVAILABLE_CLI[@]+"${AVAILABLE_CLI[@]}"}"; do
                _contains "$used_providers" "$extra" && continue
                case "$extra" in
                    copilot)
                        emit "copilot" "Alternative Perspective" "Provide an independent analysis of: $PROMPT. Focus on practical trade-offs, real-world adoption patterns, and what experienced developers actually choose. Challenge assumptions from other analyses." ;;
                    qwen)
                        emit "qwen" "Contrarian Analysis" "Play devil's advocate on: $PROMPT. What are the strongest arguments AGAINST the obvious approach? What risks are being systematically underestimated?" ;;
                    cursor-agent)
                        emit "cursor-agent" "Cursor Perspective" "Provide an independent analysis of: $PROMPT. Focus on alternative implementation choices, practical trade-offs, and assumptions that deserve re-examination." ;;
                    opencode)
                        emit "opencode" "Implementation Patterns" "Research concrete implementation patterns for: $PROMPT. Focus on production-grade examples, common pitfalls, and battle-tested approaches. Cite specific repos or documentation." ;;
                    ollama)
                        emit "ollama" "Local Model Perspective" "Analyze: $PROMPT. Provide a grounded, practical perspective focusing on simplicity and maintainability over complexity." ;;
                    openrouter)
                        emit "openrouter" "Diverse Model Check" "Cross-check the analysis of: $PROMPT. Identify any blind spots, groupthink, or consensus bias that other models might share due to similar training data." ;;
                    vibe)
                        emit "vibe" "Mistral Perspective" "Analyze: $PROMPT. Focus on pragmatic implementation choices and assumptions worth challenging." ;;
                    claude-sdk)
                        emit "claude-sdk" "Agent SDK Perspective" "Analyze: $PROMPT. Focus on long-context integration concerns and reliable agent execution." ;;
                    openai-compatible|atlascloud-agent)
                        emit "$extra" "Independent Model Check" "Cross-check the analysis of: $PROMPT. Identify blind spots and implementation trade-offs." ;;
                esac
            done
            ;;
    esac
    return 0
}

# ── Review Fleet ──────────────────────────────────────────────────────────────
# Review seats are provider-neutral. Build a deterministic, family-diverse pool
# from providers that are both admitted by check-providers.sh and declare the
# registry `council` capability. Claude remains an implicit candidate because it
# is the host runtime and therefore is not reported by check-providers.sh.
build_council_order() {
    local provider family canonical used_families="" first="" rest="" candidates="" preferred=""

    # Provider policy controls preference order, not eligibility. Any admitted
    # provider with the registry `council` capability may still fill a seat when
    # preferred providers are unavailable or denied.
    preferred="$(octo_council_default_providers)" || return $?
    for provider in $(printf '%s' "$preferred" | tr ',' ' '); do
        local requested_model="" requested_provider="$provider"
        if [[ "$requested_provider" == *:* ]]; then
            requested_model="${requested_provider#*:}"
            requested_provider="${requested_provider%%:*}"
        fi
        canonical="$(octo_provider_canonical "$requested_provider" 2>/dev/null || true)"
        [[ -n "$canonical" ]] || continue
        octo_provider_has_capability "$canonical" council || continue
        if [[ "$canonical" == "claude" ]]; then
            octo_provider_allowed claude-sonnet || continue
            provider="claude-sonnet${requested_model:+:$requested_model}"
        else
            is_available "$canonical" || continue
            octo_provider_allowed "$canonical" || continue
            provider="$canonical${requested_model:+:$requested_model}"
        fi
        _contains "$candidates" "$provider" || candidates="${candidates}${candidates:+ }${provider}"
    done

    # Append eligible council providers omitted from the preference policy so a
    # usable backend can naturally replace an unavailable one.
    for canonical in $(octo_provider_ids council 2>/dev/null); do
        if [[ "$canonical" == "claude" ]]; then
            octo_provider_allowed claude-sonnet || continue
            provider="claude-sonnet"
        else
            is_available "$canonical" || continue
            octo_provider_allowed "$canonical" || continue
            provider="$canonical"
        fi
        _contains "$candidates" "$provider" || candidates="${candidates}${candidates:+ }${provider}"
    done

    for provider in $candidates; do
        family=$(get_family "$provider")
        if ! _contains "$used_families" "$family"; then
            first="${first}${first:+ }${provider}"
            used_families="${used_families}${used_families:+ }${family}"
        else
            rest="${rest}${rest:+ }${provider}"
        fi
    done
    if [[ -z "$first" && -z "$rest" ]]; then
        log ERROR "no eligible read-only provider is available for the $WORKFLOW fleet"
        return 1
    fi
    printf '%s\n' "${first}${rest:+ $rest}"
}

build_review_fleet() {
    review_validate_configured_seat_overrides || return $?
    local roles=(
        implementation-logic-reviewer
        implementation-security-reviewer
        implementation-architecture-reviewer
        implementation-cve-reviewer
        implementation-diversity-reviewer
        implementation-verifier
        implementation-debater
        implementation-synthesizer
    )
    local labels=("Logic Reviewer" "Security Reviewer" "Architecture Reviewer" "CVE Reviewer" "Diversity Reviewer" "Verifier" "Debater" "Synthesizer")
    local prompts=(
        "Review for correctness and logic bugs, edge cases, regressions in: $PROMPT"
        "Review for OWASP vulnerabilities, injection, auth flaws, data exposure in: $PROMPT"
        "Review architecture, integration, API contracts, breaking changes in: $PROMPT"
        "Check for known CVEs, library advisories, and security bulletins related to: $PROMPT"
        "Review for blind spots, missed assumptions, and provider-family divergence in: $PROMPT"
        "Verify confirmed findings against the code and evidence in: $PROMPT"
        "Challenge disputed findings and test competing interpretations in: $PROMPT"
        "Synthesize the verified review findings for: $PROMPT"
    )

    local i provider
    if [[ -n "${OCTOPUS_REVIEW_SINGLE_PROVIDER:-}" ]]; then
        provider="$(review_single_provider_override)" || return $?
        for ((i=0; i<8; i++)); do
            emit "$provider" "${labels[$i]}" "${prompts[$i]}"
        done
        return 0
    fi

    local order
    order="$(build_council_order)" || return $?
    # shellcheck disable=SC2206
    local providers=($order)
    local count=${#providers[@]}
    [[ $count -gt 0 ]] || return 0

    local verifier_default="${providers[0]}" synthesis_default="${providers[0]}"
    if is_available codex && octo_provider_allowed codex; then
        verifier_default=codex
    fi
    if octo_provider_allowed claude-sonnet; then
        synthesis_default=claude-sonnet
    fi

    local defaults=(
        "${providers[0]}"
        "${providers[$((1 % count))]}"
        "${providers[$((2 % count))]}"
        "${providers[$((3 % count))]}"
        "${providers[$((4 % count))]}"
        "$verifier_default"
        "$verifier_default"
        "$synthesis_default"
    )
    for ((i=0; i<8; i++)); do
        provider="$(review_agent_for_seat "${defaults[$i]}" "${roles[$i]}")" || return $?
        emit "$provider" "${labels[$i]}" "${prompts[$i]}"
    done
    return 0
}

build_review_order() {
    local order
    order="$(build_council_order)" || return $?
    local provider
    for provider in $order; do
        printf '%s\n' "$provider"
    done
}

# ── Debate Fleet ──────────────────────────────────────────────────────────────
build_debate_fleet() {
    local debaters=""
    local used_families=""
    local debater_count=0

    for p in "${AVAILABLE_CLI[@]+"${AVAILABLE_CLI[@]}"}"; do
        # Skip providers not suited for debate (API-only, local models)
        case "$p" in perplexity|openrouter|ollama|atlascloud-agent|claude-sdk|vibe) continue ;; esac

        local fam
        fam=$(get_family "$p")
        if ! _contains "$used_families" "$fam"; then
            debaters="${debaters:+$debaters }$p"
            used_families="${used_families:+$used_families }$fam"
            debater_count=$((debater_count + 1))
        fi
        # Cap at 3 external debaters (+ Claude moderator = 4 total)
        [[ $debater_count -ge 3 ]] && break
    done

    # Ensure at least 1 debater
    if [[ $debater_count -eq 0 ]]; then
        if octo_provider_allowed claude-sonnet; then
            debaters="claude-sonnet"
        else
            log ERROR "no eligible read-only provider is available for the $WORKFLOW fleet"
            return 1
        fi
    fi

    for d in $debaters; do
        emit "$d" "Debater" "Argue your position on: $PROMPT"
    done
    emit_if_allowed "claude-sonnet" "Moderator" "Synthesize debate positions and identify consensus on: $PROMPT"
    return 0
}

# ── Architecture Fleet ────────────────────────────────────────────────────────
build_architecture_fleet() {
    local architects=""
    local used_families=""
    local arch_count=0

    for p in codex agy copilot qwen cursor-agent opencode vibe claude-sdk \
        openai-compatible atlascloud-agent; do
        is_available "$p" || continue
        local fam
        fam=$(get_family "$p")
        if ! _contains "$used_families" "$fam"; then
            architects="${architects:+$architects }$p"
            used_families="${used_families:+$used_families }$fam"
            arch_count=$((arch_count + 1))
        fi
        [[ $arch_count -ge 2 ]] && break
    done

    if [[ $arch_count -eq 0 ]]; then
        if octo_provider_allowed claude-sonnet; then
            architects="claude-sonnet"
        else
            log ERROR "no eligible read-only provider is available for the $WORKFLOW fleet"
            return 1
        fi
    fi

    local i=0
    for a in $architects; do
        if [[ $i -eq 0 ]]; then
            emit "$a" "Architecture Proposal" "Propose a system architecture for: $PROMPT. Include component diagram, data flow, and technology choices."
        else
            emit "$a" "Architecture Review" "Critique and improve the architecture for: $PROMPT. Identify scalability risks, single points of failure, and simpler alternatives."
        fi
        i=$((i + 1))
    done
    emit_if_allowed "claude-sonnet" "Architecture Synthesis" "Synthesize architectural perspectives for: $PROMPT. Recommend the best approach with trade-off analysis."
    return 0
}

# ── Main Dispatch ─────────────────────────────────────────────────────────────
# Normalize workflow name
fleet_status=0
case "$WORKFLOW" in
    research|discover)     build_research_fleet || fleet_status=$? ;;
    review|security)       build_review_fleet || fleet_status=$? ;;
    review-order)          build_review_order || fleet_status=$? ;;
    debate)                build_debate_fleet || fleet_status=$? ;;
    architecture)          build_architecture_fleet || fleet_status=$? ;;
    *)                     build_research_fleet || fleet_status=$? ;;
esac

# ── Fleet Summary (stderr — for diagnostic/logging) ──────────────────────────
if [[ -n "${AVAILABLE_CLI[*]:-}" ]]; then
    families=$(count_families "${AVAILABLE_CLI[@]}")
else
    families=$(count_families)
fi
>&2 echo "FLEET_SUMMARY: workflow=$WORKFLOW intensity=$INTENSITY families=${families} cli_count=${CLI_COUNT} providers=${AVAILABLE_CLI[*]:-none}"
return "$fleet_status" 2>/dev/null || exit "$fleet_status"
