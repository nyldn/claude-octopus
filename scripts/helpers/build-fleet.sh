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
source "${SCRIPT_DIR}/../lib/cursor-agent.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/../lib/provider-allowlist.sh" 2>/dev/null || true

WORKFLOW="${1:-research}"
INTENSITY="${2:-standard}"
PROMPT="${3:-}"

# ── Provider → Model Family Mapping ──────────────────────────────────────────
get_family() {
    case "$1" in
        codex|codex-*)       echo "openai" ;;
        gemini|gemini-*)     echo "google" ;;
        agy|agy-*|antigravity) echo "google-antigravity" ;;
        claude-sonnet|claude-opus|claude|claude-*) echo "anthropic" ;;
        perplexity|perplexity-*) echo "perplexity" ;;
        copilot|copilot-*)   echo "microsoft" ;;
        qwen|qwen-*)         echo "alibaba" ;;
        opencode|opencode-*) echo "multi" ;;
        ollama|ollama-*)     echo "local" ;;
        cursor-agent|cursor-agent-*) echo "xai" ;;
        openrouter|openrouter-*) echo "multi" ;;
        *)                   echo "unknown" ;;
    esac
}

# ── Provider Detection ────────────────────────────────────────────────────────
# Order = preference for primary slot assignment
AVAILABLE_CLI=()
if octo_provider_allowed codex && command -v codex >/dev/null 2>&1; then AVAILABLE_CLI+=(codex); fi
if octo_provider_allowed gemini && command -v gemini >/dev/null 2>&1; then AVAILABLE_CLI+=(gemini); fi
if octo_provider_allowed agy && command -v agy >/dev/null 2>&1; then AVAILABLE_CLI+=(agy); fi
if octo_provider_allowed copilot && command -v copilot >/dev/null 2>&1; then AVAILABLE_CLI+=(copilot); fi
if octo_provider_allowed qwen && command -v qwen >/dev/null 2>&1; then AVAILABLE_CLI+=(qwen); fi
if octo_provider_allowed opencode && command -v opencode >/dev/null 2>&1; then AVAILABLE_CLI+=(opencode); fi
if octo_provider_allowed ollama && command -v ollama >/dev/null 2>&1 && curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then AVAILABLE_CLI+=(ollama); fi
if octo_provider_allowed cursor-agent && declare -f _is_cursor_agent_binary >/dev/null 2>&1 && _is_cursor_agent_binary; then
    if [[ -n "${CURSOR_API_KEY:-}" ]] || grep -Eq '"authInfo"[[:space:]]*:[[:space:]]*\{' "${HOME}/.cursor/cli-config.json" 2>/dev/null; then
        AVAILABLE_CLI+=(cursor-agent)
    fi
fi
octo_provider_allowed perplexity && [[ -n "${PERPLEXITY_API_KEY:-}" ]] && AVAILABLE_CLI+=(perplexity)
octo_provider_allowed openrouter && [[ -n "${OPENROUTER_API_KEY:-}" ]] && AVAILABLE_CLI+=(openrouter)

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
    _contains "${AVAILABLE_CLI[*]:-}" "$p"
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
        # shellcheck disable=SC2086 # Intentional split to read the first provider.
        set -- ${AVAILABLE_CLI[*]}
        echo "$1"
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

    # Preferred order for primary diversity: codex, gemini, agy, copilot, qwen, cursor-agent, opencode, ollama
    for p in codex gemini agy copilot qwen cursor-agent opencode ollama; do
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
    printf '%s|%s|%s\n' "$1" "$2" "$3"
}

emit_if_allowed() {
    octo_provider_allowed "$1" || return 0
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
            return 0
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

            for extra in ${AVAILABLE_CLI[*]:-}; do
                _contains "$used_providers" "$extra" && continue
                case "$extra" in
                    copilot)
                        emit "copilot" "Alternative Perspective" "Provide an independent analysis of: $PROMPT. Focus on practical trade-offs, real-world adoption patterns, and what experienced developers actually choose. Challenge assumptions from other analyses." ;;
                    qwen)
                        emit "qwen" "Contrarian Analysis" "Play devil's advocate on: $PROMPT. What are the strongest arguments AGAINST the obvious approach? What risks are being systematically underestimated?" ;;
                    cursor-agent)
                        emit "cursor-agent" "XAI Perspective" "Provide an independent analysis of: $PROMPT. Focus on alternative implementation choices, practical trade-offs, and assumptions that deserve re-examination." ;;
                    opencode)
                        emit "opencode" "Implementation Patterns" "Research concrete implementation patterns for: $PROMPT. Focus on production-grade examples, common pitfalls, and battle-tested approaches. Cite specific repos or documentation." ;;
                    ollama)
                        emit "ollama" "Local Model Perspective" "Analyze: $PROMPT. Provide a grounded, practical perspective focusing on simplicity and maintainability over complexity." ;;
                    openrouter)
                        emit "openrouter" "Diverse Model Check" "Cross-check the analysis of: $PROMPT. Identify any blind spots, groupthink, or consensus bias that other models might share due to similar training data." ;;
                esac
            done
            ;;
    esac
    return 0
}

# ── Review Fleet ──────────────────────────────────────────────────────────────
build_review_fleet() {
    local logic_provider
    logic_provider=$(pick_provider "claude-sonnet" codex opencode copilot)
    [[ -n "$logic_provider" ]] && emit "$logic_provider" "Logic Reviewer" "Review for correctness and logic bugs, edge cases, regressions in: $PROMPT"

    local sec_provider
    sec_provider=$(pick_provider "claude-sonnet" gemini qwen copilot)
    # Ensure different from logic reviewer
    if [[ -n "$sec_provider" && "$sec_provider" == "$logic_provider" && "$sec_provider" != "claude-sonnet" ]]; then
        local alternate_provider
        alternate_provider=$(pick_provider "" claude-sonnet)
        if [[ -n "$alternate_provider" && "$alternate_provider" != "$logic_provider" ]]; then
            sec_provider="$alternate_provider"
        fi
    fi
    [[ -n "$sec_provider" ]] && emit "$sec_provider" "Security Reviewer" "Review for OWASP vulnerabilities, injection, auth flaws, data exposure in: $PROMPT"

    emit_if_allowed "claude-sonnet" "Architecture Reviewer" "Review architecture, integration, API contracts, breaking changes in: $PROMPT"

    local cve_provider
    if is_available perplexity; then
        cve_provider="perplexity"
    else
        cve_provider=$(pick_provider "claude-sonnet" gemini copilot qwen)
    fi
    [[ -n "$cve_provider" ]] && emit "$cve_provider" "CVE Reviewer" "Check for known CVEs, library advisories, and security bulletins related to: $PROMPT"
    return 0
}

# ── Debate Fleet ──────────────────────────────────────────────────────────────
build_debate_fleet() {
    local debaters=""
    local used_families=""
    local debater_count=0

    for p in ${AVAILABLE_CLI[*]:-}; do
        # Skip providers not suited for debate (API-only, local models)
        case "$p" in perplexity|openrouter|ollama) continue ;; esac

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
    [[ $debater_count -eq 0 ]] && debaters="claude-sonnet"

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

    for p in codex gemini copilot qwen cursor-agent opencode; do
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

    [[ $arch_count -eq 0 ]] && octo_provider_allowed claude-sonnet && architects="claude-sonnet"

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
case "$WORKFLOW" in
    research|discover)     build_research_fleet ;;
    review|security)       build_review_fleet ;;
    debate)                build_debate_fleet ;;
    architecture)          build_architecture_fleet ;;
    *)                     build_research_fleet ;;
esac

# ── Fleet Summary (stderr — for diagnostic/logging) ──────────────────────────
if [[ -n "${AVAILABLE_CLI[*]:-}" ]]; then
    # shellcheck disable=SC2086 # Provider names are single shell words.
    families=$(count_families ${AVAILABLE_CLI[*]})
else
    families=$(count_families)
fi
>&2 echo "FLEET_SUMMARY: workflow=$WORKFLOW intensity=$INTENSITY families=${families} cli_count=${CLI_COUNT} providers=${AVAILABLE_CLI[*]:-none}"
