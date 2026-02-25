#!/usr/bin/env bash
# MCP Provider Detection - Claude Code v2.1.0+ MCP list_changed Integration
# Fast provider capability detection using MCP when available

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if MCP CLI is available (Claude Code v2.1.0+)
has_mcp_support() {
    command -v mcp &>/dev/null || return 1

    # Check if mcp list command works
    mcp list &>/dev/null || return 1

    return 0
}

# Detect provider using MCP (fast)
detect_provider_mcp() {
    local provider="$1"

    case "$provider" in
        codex)
            # Check if codex MCP tool is available
            if mcp list 2>/dev/null | grep -q "codex"; then
                echo "available"
                return 0
            fi
            ;;
        gemini)
            # Check if gemini MCP tool is available
            if mcp list 2>/dev/null | grep -q "gemini"; then
                echo "available"
                return 0
            fi
            ;;
        perplexity)
            # Check if perplexity MCP tool is available
            if mcp list 2>/dev/null | grep -q "perplexity"; then
                echo "available"
                return 0
            fi
            ;;
    esac

    echo "unavailable"
    return 1
}

# Detect provider using command-line check (fallback)
detect_provider_cli() {
    local provider="$1"

    case "$provider" in
        codex)
            if command -v codex &>/dev/null; then
                echo "available"
                return 0
            fi
            ;;
        gemini)
            if command -v gemini &>/dev/null; then
                echo "available"
                return 0
            fi
            ;;
        perplexity)
            # v8.24.0: Perplexity uses API key, not CLI (Issue #22)
            if [[ -n "${PERPLEXITY_API_KEY:-}" ]]; then
                echo "available"
                return 0
            fi
            ;;
        claude)
            # Claude is always available in Claude Code
            echo "available"
            return 0
            ;;
    esac

    echo "unavailable"
    return 1
}

# Detect all providers
detect_all_providers() {
    local use_mcp="${1:-auto}"

    local codex_status gemini_status perplexity_status claude_status

    # Determine detection method
    local use_mcp_method="false"
    if [[ "$use_mcp" == "auto" ]]; then
        if has_mcp_support; then
            use_mcp_method="true"
        fi
    elif [[ "$use_mcp" == "true" ]]; then
        use_mcp_method="true"
    fi

    # Detect providers (|| true guards against set -e with unavailable providers)
    if [[ "$use_mcp_method" == "true" ]]; then
        codex_status=$(detect_provider_mcp "codex") || true
        gemini_status=$(detect_provider_mcp "gemini") || true
        perplexity_status=$(detect_provider_mcp "perplexity") || true
    else
        codex_status=$(detect_provider_cli "codex") || true
        gemini_status=$(detect_provider_cli "gemini") || true
        perplexity_status=$(detect_provider_cli "perplexity") || true
    fi
    claude_status="available"  # Always available

    # Output JSON
    cat <<EOF
{
  "detection_method": "$([ "$use_mcp_method" == "true" ] && echo "mcp" || echo "cli")",
  "providers": {
    "codex": {
      "status": "$codex_status",
      "emoji": "🔴"
    },
    "gemini": {
      "status": "$gemini_status",
      "emoji": "🟡"
    },
    "perplexity": {
      "status": "$perplexity_status",
      "emoji": "🟣"
    },
    "claude": {
      "status": "$claude_status",
      "emoji": "🔵"
    }
  }
}
EOF
}

# Get provider availability string for banner
get_provider_banner() {
    local json_output="$1"

    local codex_status=$(echo "$json_output" | jq -r '.providers.codex.status')
    local gemini_status=$(echo "$json_output" | jq -r '.providers.gemini.status')
    local perplexity_status=$(echo "$json_output" | jq -r '.providers.perplexity.status')
    local claude_status=$(echo "$json_output" | jq -r '.providers.claude.status')

    local codex_display="🔴 Codex CLI: "
    local gemini_display="🟡 Gemini CLI: "
    local perplexity_display="🟣 Perplexity: "
    local claude_display="🔵 Claude: "

    if [[ "$codex_status" == "available" ]]; then
        codex_display="${codex_display}Available ✓"
    else
        codex_display="${codex_display}Not installed ✗"
    fi

    if [[ "$gemini_status" == "available" ]]; then
        gemini_display="${gemini_display}Available ✓"
    else
        gemini_display="${gemini_display}Not installed ✗"
    fi

    if [[ "$perplexity_status" == "available" ]]; then
        perplexity_display="${perplexity_display}Available ✓"
    else
        perplexity_display="${perplexity_display}Not configured ✗"
    fi

    claude_display="${claude_display}Available ✓"

    echo "$codex_display"
    echo "$gemini_display"
    echo "$perplexity_display"
    echo "$claude_display"
}

# Check if provider is available (exit code based)
is_provider_available() {
    local provider="$1"
    local use_mcp="${2:-auto}"

    local use_mcp_method="false"
    if [[ "$use_mcp" == "auto" ]]; then
        if has_mcp_support; then
            use_mcp_method="true"
        fi
    elif [[ "$use_mcp" == "true" ]]; then
        use_mcp_method="true"
    fi

    local status
    if [[ "$use_mcp_method" == "true" ]]; then
        status=$(detect_provider_mcp "$provider")
    else
        status=$(detect_provider_cli "$provider")
    fi

    [[ "$status" == "available" ]]
}

# Main command dispatcher
case "${1:-}" in
    detect-all)
        detect_all_providers "${2:-auto}"
        ;;
    banner)
        detection_result=$(detect_all_providers "${2:-auto}")
        get_provider_banner "$detection_result"
        ;;
    check)
        if is_provider_available "$2" "${3:-auto}"; then
            echo "available"
            exit 0
        else
            echo "unavailable"
            exit 1
        fi
        ;;
    has-mcp)
        if has_mcp_support; then
            echo "yes"
            exit 0
        else
            echo "no"
            exit 1
        fi
        ;;
    *)
        cat <<EOF
Usage: mcp-provider-detection.sh COMMAND [ARGS]

Commands:
  detect-all [METHOD]      Detect all providers (METHOD: auto|mcp|cli)
                           Returns JSON with provider statuses
  banner [METHOD]          Get provider availability banner text
  check PROVIDER [METHOD]  Check if provider is available (exit code)
  has-mcp                  Check if MCP support is available

Providers: codex, gemini, perplexity, claude

EOF
        exit 1
        ;;
esac
