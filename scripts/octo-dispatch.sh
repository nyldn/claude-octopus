#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# octo-dispatch — Standalone provider dispatch with automatic model resolution
# ═══════════════════════════════════════════════════════════════════════════════
#
# WHY: When Claude bypasses orchestrate.sh (ad-hoc review, custom analysis),
# it manually constructs CLI commands and hardcodes wrong/stale model names.
# This script provides a simple interface that ALWAYS reads providers.json.
#
# Usage:
#   echo "your prompt" | octo-dispatch <provider> [--phase <phase>] [--role <role>]
#   octo-dispatch <provider> "your prompt" [--phase <phase>] [--role <role>]
#   octo-dispatch --resolve <provider>   # Just print the model, don't dispatch
#
# Examples:
#   echo "Review this code for bugs" | octo-dispatch codex
#   echo "Check for OWASP issues"    | octo-dispatch gemini
#   echo "Analyze architecture"       | octo-dispatch qwen
#   octo-dispatch --resolve codex     # prints: gpt-5.4-pro
#   octo-dispatch --resolve gemini    # prints: gemini-3.1-pro-preview
#
# Model resolution uses the same 7-tier precedence as orchestrate.sh:
#   Env Var > Session Override > Phase/Role Routing > Capability > Tier > Config Default > Hardcoded
#
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source model resolution (the single source of truth)
source "${SCRIPT_DIR}/lib/model-resolver.sh"

# Minimal logging (avoid sourcing all of orchestrate.sh)
log() {
    local level="$1"; shift
    echo "[octo-dispatch] ${level}: $*" >&2
}

# ── Parse arguments ──────────────────────────────────────────────────────────

RESOLVE_ONLY=false
PROVIDER=""
PHASE=""
ROLE=""
PROMPT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --resolve)
            RESOLVE_ONLY=true
            shift
            ;;
        --phase)
            if [[ $# -lt 2 || "${2:-}" == -* ]]; then
                log ERROR "--phase requires a value"
                exit 1
            fi
            PHASE="$2"
            shift 2
            ;;
        --role)
            if [[ $# -lt 2 || "${2:-}" == -* ]]; then
                log ERROR "--role requires a value"
                exit 1
            fi
            ROLE="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: octo-dispatch <provider> [prompt] [--phase <phase>] [--role <role>]"
            echo "       echo 'prompt' | octo-dispatch <provider>"
            echo "       octo-dispatch --resolve <provider>"
            echo ""
            echo "Providers: codex, gemini, qwen, claude, openrouter, perplexity, ollama"
            echo ""
            echo "Resolves the correct model from ~/.claude-octopus/config/providers.json"
            echo "and dispatches using the provider's CLI with proper flags."
            exit 0
            ;;
        -*)
            log ERROR "Unknown flag: $1"
            exit 1
            ;;
        *)
            if [[ -z "$PROVIDER" ]]; then
                PROVIDER="$1"
            else
                PROMPT="$1"
            fi
            shift
            ;;
    esac
done

if [[ -z "$PROVIDER" ]]; then
    log ERROR "Provider required. Usage: octo-dispatch <provider> [prompt]"
    exit 1
fi

# ── Resolve model ────────────────────────────────────────────────────────────

MODEL=$(resolve_octopus_model "$PROVIDER" "$PROVIDER" "$PHASE" "$ROLE")

if [[ -z "$MODEL" || "$MODEL" == "null" ]]; then
    log ERROR "Could not resolve model for provider '$PROVIDER'"
    exit 1
fi

if [[ "$RESOLVE_ONLY" == "true" ]]; then
    echo "$MODEL"
    exit 0
fi

# ── Read prompt from stdin if not provided as argument ───────────────────────

if [[ -z "$PROMPT" ]]; then
    if [[ -t 0 ]]; then
        log ERROR "No prompt provided. Pass as argument or pipe via stdin."
        exit 1
    fi
    PROMPT=$(cat)
fi

# ── Platform detection ───────────────────────────────────────────────────────

OCTOPUS_PLATFORM="$(uname)"

# ── Dispatch ─────────────────────────────────────────────────────────────────

log INFO "Provider: $PROVIDER | Model: $MODEL"

case "$PROVIDER" in
    codex)
        local_sandbox="${OCTOPUS_CODEX_SANDBOX:-workspace-write}"
        printf '%s\n' "$PROMPT" | codex exec \
            --skip-git-repo-check \
            --full-auto \
            --model "$MODEL" \
            --sandbox "$local_sandbox" \
            -
        ;;
    gemini)
        if [[ "$OCTOPUS_PLATFORM" == "Darwin" && -z "${GEMINI_API_KEY:-}" ]]; then
            printf '%s\n' "$PROMPT" | env NODE_NO_WARNINGS=1 GEMINI_FORCE_FILE_STORAGE=true \
                gemini -o text --approval-mode yolo -m "$MODEL"
        else
            printf '%s\n' "$PROMPT" | env NODE_NO_WARNINGS=1 \
                gemini -o text --approval-mode yolo -m "$MODEL"
        fi
        ;;
    qwen)
        if [[ "$OCTOPUS_PLATFORM" == "Darwin" && -z "${QWEN_API_KEY:-}" ]]; then
            printf '%s\n' "$PROMPT" | env NODE_NO_WARNINGS=1 QWEN_FORCE_FILE_STORAGE=true \
                qwen -o text --approval-mode yolo -m "$MODEL"
        else
            printf '%s\n' "$PROMPT" | env NODE_NO_WARNINGS=1 \
                qwen -o text --approval-mode yolo -m "$MODEL"
        fi
        ;;
    claude|claude-sonnet)
        # Resolve model via providers.json — never hardcode "sonnet"/"opus"
        printf '%s\n' "$PROMPT" | claude --print --model "$MODEL"
        ;;
    claude-opus)
        printf '%s\n' "$PROMPT" | claude --print --model "$MODEL"
        ;;
    perplexity)
        # Perplexity uses API, not CLI — delegate to orchestrate.sh function
        log ERROR "Perplexity dispatch requires orchestrate.sh (API-based). Use orchestrate.sh directly."
        exit 1
        ;;
    openrouter)
        log ERROR "OpenRouter dispatch requires orchestrate.sh (API-based). Use orchestrate.sh directly."
        exit 1
        ;;
    ollama)
        printf '%s\n' "$PROMPT" | ollama run "$MODEL"
        ;;
    *)
        log ERROR "Unknown provider: $PROVIDER"
        exit 1
        ;;
esac
