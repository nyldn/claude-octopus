#!/usr/bin/env bash
# lib/preflight.sh — Preflight checks and provider detection
# Extracted from orchestrate.sh (v9.7.x decomposition)
# shellcheck source=/dev/null

if ! declare -f _is_cursor_agent_binary >/dev/null 2>&1; then
    _preflight_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${_preflight_lib_dir}/cursor-agent.sh" 2>/dev/null || true
fi

# Command: detect-providers
# Output parseable provider status for Claude Code skill
cmd_detect_providers() {
    echo "Detecting Claude Code version..."
    echo ""

    # Check Claude Code version first
    check_claude_version
    echo ""

    # If outdated, show prominent warning
    local claude_status=$(check_claude_version | grep CLAUDE_CODE_STATUS | cut -d= -f2)
    local claude_version=$(check_claude_version | grep CLAUDE_CODE_VERSION | cut -d= -f2)
    local min_version=$(check_claude_version | grep CLAUDE_CODE_MINIMUM | cut -d= -f2)

    if [[ "$claude_status" == "outdated" ]]; then
        echo "⚠️  WARNING: Claude Code is outdated!"
        echo ""
        echo "  Current version: $claude_version"
        echo "  Required version: $min_version or higher"
        echo ""
        echo "Claude Octopus requires Claude Code $min_version+ for full functionality."
        echo ""
        echo "How to update:"
        echo ""
        echo "  If installed via npm:"
        echo "    npm update -g @anthropic/claude-code"
        echo ""
        echo "  If installed via brew:"
        echo "    brew upgrade claude-code"
        echo ""
        echo "  If installed via download:"
        echo "    Visit https://github.com/anthropics/claude-code/releases"
        echo ""
        echo "After updating, please restart Claude Code for changes to take effect."
        echo ""
        echo "═══════════════════════════════════════════════════════════════════"
        echo ""
    elif [[ "$claude_status" == "ok" ]]; then
        echo "✓ Claude Code version: $claude_version (meets minimum $min_version)"
        echo ""
    fi

    echo "Detecting providers..."
    echo ""

    # Check Codex CLI
    if command -v codex &>/dev/null; then
        echo "CODEX_STATUS=ok"
        if [[ -f "$HOME/.codex/auth.json" ]]; then
            echo "CODEX_AUTH=oauth"
        elif [[ -n "${OPENAI_API_KEY:-}" ]]; then
            echo "CODEX_AUTH=api-key"
        else
            echo "CODEX_AUTH=none"
        fi
    else
        echo "CODEX_STATUS=missing"
        echo "CODEX_AUTH=none"
    fi
    echo ""

    # Check Gemini CLI
    if command -v gemini &>/dev/null; then
        echo "GEMINI_STATUS=ok"
        if [[ -f "$HOME/.gemini/oauth_creds.json" ]]; then
            echo "GEMINI_AUTH=oauth"
        elif [[ -n "${GEMINI_API_KEY:-}" ]]; then
            echo "GEMINI_AUTH=api-key"
        else
            echo "GEMINI_AUTH=none"
        fi
    else
        echo "GEMINI_STATUS=missing"
        echo "GEMINI_AUTH=none"
    fi
    echo ""

    # Check Perplexity API (v8.24.0 - Issue #22)
    if [[ -n "${PERPLEXITY_API_KEY:-}" ]]; then
        echo "PERPLEXITY_STATUS=ok"
        echo "PERPLEXITY_AUTH=api-key"
    else
        echo "PERPLEXITY_STATUS=not-configured"
        echo "PERPLEXITY_AUTH=none"
    fi
    echo ""

    # Check Ollama (optional — local LLM, v9.9.0)
    if command -v ollama &>/dev/null; then
        if curl -sf http://localhost:11434/api/tags &>/dev/null; then
            local model_count
            model_count=$(curl -sf http://localhost:11434/api/tags 2>/dev/null | grep -c '"name"' 2>/dev/null || echo "0")
            echo "OLLAMA_STATUS=running"
            echo "OLLAMA_MODELS=$model_count"
        else
            echo "OLLAMA_STATUS=stopped"
            echo "OLLAMA_MODELS=0"
        fi
    else
        echo "OLLAMA_STATUS=not-installed"
        echo "OLLAMA_MODELS=0"
    fi
    echo ""

    # Check Copilot CLI (optional — zero-cost via GitHub subscription, v9.9.0)
    if command -v copilot &>/dev/null; then
        local copilot_auth="none"
        if [[ -n "${COPILOT_GITHUB_TOKEN:-}" ]]; then
            copilot_auth="pat"
        elif [[ -n "${GH_TOKEN:-}" ]] || [[ -n "${GITHUB_TOKEN:-}" ]]; then
            copilot_auth="env-token"
        elif [[ -f "${HOME}/.copilot/config.json" ]]; then
            copilot_auth="keychain"
        elif command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
            copilot_auth="gh-cli"
        fi
        echo "COPILOT_STATUS=ok"
        echo "COPILOT_AUTH=$copilot_auth"
    else
        echo "COPILOT_STATUS=not-installed"
        echo "COPILOT_AUTH=none"
    fi
    echo ""

    # Check OpenCode CLI (optional — multi-provider router, v9.11.0)
    if command -v opencode &>/dev/null; then
        local opencode_auth="none"
        if [[ -f "${HOME}/.local/share/opencode/auth.json" ]]; then
            # Verify auth is valid (with timeout to prevent interactive prompts)
            if timeout 3 opencode auth list &>/dev/null 2>&1; then
                opencode_auth="multi"
            else
                opencode_auth="expired"
            fi
        fi
        echo "OPENCODE_STATUS=ok"
        echo "OPENCODE_AUTH=$opencode_auth"
    else
        echo "OPENCODE_STATUS=not-installed"
        echo "OPENCODE_AUTH=none"
    fi
    echo ""

    # Check Qwen CLI (optional — free tier via Qwen OAuth, v9.10.0)
    if command -v qwen &>/dev/null; then
        local qwen_auth="none"
        if [[ -f "${HOME}/.qwen/oauth_creds.json" ]]; then
            qwen_auth="oauth"
        elif [[ -f "${HOME}/.qwen/config.json" ]]; then
            qwen_auth="config"
        elif [[ -n "${QWEN_API_KEY:-}" ]]; then
            qwen_auth="api-key"
        fi
        echo "QWEN_STATUS=ok"
        echo "QWEN_AUTH=$qwen_auth"
    else
        echo "QWEN_STATUS=not-installed"
        echo "QWEN_AUTH=none"
    fi
    echo ""

    # Check Cursor Agent CLI (optional — Grok 4.20 via Cursor subscription, v9.23.0)
    if declare -f _is_cursor_agent_binary >/dev/null 2>&1 && _is_cursor_agent_binary; then
        local cursor_auth="none"
        if [[ -n "${CURSOR_API_KEY:-}" ]]; then
            cursor_auth="env:CURSOR_API_KEY"
        elif grep -Eq '"authInfo"[[:space:]]*:[[:space:]]*\{' "${HOME}/.cursor/cli-config.json" 2>/dev/null; then
            cursor_auth="cursor-session"
        fi
        echo "CURSOR_AGENT_STATUS=ok"
        echo "CURSOR_AGENT_AUTH=$cursor_auth"
    else
        echo "CURSOR_AGENT_STATUS=not-installed"
        echo "CURSOR_AGENT_AUTH=none"
    fi
    echo ""

    # Write to cache
    mkdir -p "$WORKSPACE_DIR"
    local codex_status=$(command -v codex &>/dev/null && echo "ok" || echo "missing")
    local codex_auth=$([[ -f "$HOME/.codex/auth.json" ]] && echo "oauth" || [[ -n "${OPENAI_API_KEY:-}" ]] && echo "api-key" || echo "none")
    local gemini_status=$(command -v gemini &>/dev/null && echo "ok" || echo "missing")
    local gemini_auth=$([[ -f "$HOME/.gemini/oauth_creds.json" ]] && echo "oauth" || [[ -n "${GEMINI_API_KEY:-}" ]] && echo "api-key" || echo "none")
    local perplexity_status=$([[ -n "${PERPLEXITY_API_KEY:-}" ]] && echo "ok" || echo "not-configured")
    local perplexity_auth=$([[ -n "${PERPLEXITY_API_KEY:-}" ]] && echo "api-key" || echo "none")
    local ollama_status=$(command -v ollama &>/dev/null && { curl -sf http://localhost:11434/api/tags &>/dev/null && echo "running" || echo "stopped"; } || echo "not-installed")
    local copilot_status=$(command -v copilot &>/dev/null && echo "ok" || echo "not-installed")
    local qwen_status=$(command -v qwen &>/dev/null && echo "ok" || echo "not-installed")
    local opencode_status=$(command -v opencode &>/dev/null && echo "ok" || echo "not-installed")
    local cursor_agent_status="not-installed"
    if declare -f _is_cursor_agent_binary >/dev/null 2>&1 && _is_cursor_agent_binary; then
        cursor_agent_status="ok"
    fi
    local cursor_agent_auth=$([[ -n "${CURSOR_API_KEY:-}" ]] && echo "env:CURSOR_API_KEY" || { grep -Eq '"authInfo"[[:space:]]*:[[:space:]]*\{' "${HOME}/.cursor/cli-config.json" 2>/dev/null && echo "cursor-session"; } || echo "none")

    cat > "$WORKSPACE_DIR/.provider-cache" <<EOF
# Auto-generated on $(date)
# Valid for 1 hour - re-run detect-providers to refresh

# Codex Status
CODEX_STATUS=$codex_status
CODEX_AUTH=$codex_auth

# Gemini Status
GEMINI_STATUS=$gemini_status
GEMINI_AUTH=$gemini_auth

# Perplexity Status (v8.24.0)
PERPLEXITY_STATUS=$perplexity_status
PERPLEXITY_AUTH=$perplexity_auth

# Ollama Status (v9.9.0)
OLLAMA_STATUS=$ollama_status

# Copilot Status (v9.9.0)
COPILOT_STATUS=$copilot_status

# Qwen Status (v9.10.0)
QWEN_STATUS=$qwen_status

# OpenCode Status (v9.11.0)
OPENCODE_STATUS=$opencode_status

# Cursor Agent Status (v9.23.0)
CURSOR_AGENT_STATUS=$cursor_agent_status
CURSOR_AGENT_AUTH=$cursor_agent_auth

# Timestamp
CACHE_TIME=$(date +%s)
EOF

    echo "Detection complete. Cache written to $WORKSPACE_DIR/.provider-cache"
    echo ""

    # Show summary
    echo "Summary:"
    if [[ "$codex_status" == "ok" && "$codex_auth" != "none" ]]; then
        echo "  ✓ Codex: Installed and authenticated ($codex_auth)"
    elif [[ "$codex_status" == "ok" ]]; then
        echo "  ⚠ Codex: Installed but not authenticated"
    else
        echo "  ✗ Codex: Not installed"
    fi

    if [[ "$gemini_status" == "ok" && "$gemini_auth" != "none" ]]; then
        echo "  ✓ Gemini: Installed and authenticated ($gemini_auth)"
    elif [[ "$gemini_status" == "ok" ]]; then
        echo "  ⚠ Gemini: Installed but not authenticated"
    else
        echo "  ✗ Gemini: Not installed"
    fi

    # Perplexity (optional, v8.24.0)
    if [[ "$perplexity_status" == "ok" ]]; then
        echo "  ✓ Perplexity: Configured ($perplexity_auth) — web search enabled in discover workflows"
    else
        echo "  ○ Perplexity: Not configured (optional — adds live web search to research)"
    fi

    # Ollama (optional, v9.9.0)
    if [[ "$ollama_status" == "running" ]]; then
        echo "  ✓ Ollama: Running — zero-cost local LLM"
    elif [[ "$ollama_status" == "stopped" ]]; then
        echo "  ⚠ Ollama: Installed but server not running (run: ollama serve)"
    else
        echo "  ○ Ollama: Not installed (optional — brew install ollama)"
    fi

    # Copilot (optional, v9.9.0)
    if [[ "$copilot_status" == "ok" ]]; then
        echo "  ✓ Copilot: Installed — zero-cost research via GitHub subscription"
    else
        echo "  ○ Copilot: Not installed (optional — brew install copilot-cli)"
    fi

    # Qwen (optional, v9.10.0)
    if [[ "$qwen_status" == "ok" ]]; then
        echo "  ✓ Qwen: Installed — free-tier research via Qwen OAuth"
    else
        echo "  ○ Qwen: Not installed (optional — npm install -g @qwen-code/qwen-code)"
    fi
    if [[ "$opencode_status" == "ok" ]]; then
        echo "  ✓ OpenCode: Installed — multi-provider router (google, openai, openrouter)"
    else
        echo "  ○ OpenCode: Not installed (optional — npm install -g opencode)"
    fi
    # Cursor Agent (optional, v9.23.0)
    if [[ "$cursor_agent_status" == "ok" && "$cursor_agent_auth" != "none" ]]; then
        echo "  ✓ Cursor Agent: Installed and authenticated ($cursor_agent_auth) — Grok 4.20 via Cursor subscription"
    elif [[ "$cursor_agent_status" == "ok" ]]; then
        echo "  ⚠ Cursor Agent: Installed but not authenticated"
    else
        echo "  ○ Cursor Agent: Not installed (optional — requires Cursor IDE v9.23.0+)"
    fi
    echo ""

    # Provide guidance based on results
    if [[ "$codex_status" == "missing" && "$gemini_status" == "missing" && "$cursor_agent_status" != "ok" ]]; then
        echo "⚠ No providers installed. You need at least ONE provider to use Claude Octopus."
        echo ""
        echo "Next steps:"
        echo "  1. Install Codex CLI: npm install -g @openai/codex"
        echo "     OR"
        echo "  2. Install Gemini CLI: npm install -g @google/gemini-cli"
        echo "     OR"
        echo "  3. Install Cursor Agent CLI: https://cursor.com/install"
        echo ""
        echo "Then configure authentication - see: /claude-octopus:setup"
    elif ! { [[ "$codex_status" == "ok" && "$codex_auth" != "none" ]] || [[ "$gemini_status" == "ok" && "$gemini_auth" != "none" ]] || [[ "$cursor_agent_status" == "ok" && "$cursor_agent_auth" != "none" ]]; }; then
        echo "⚠ Provider(s) installed but not authenticated."
        echo ""
        echo "Next steps:"
        if [[ "$codex_status" == "ok" && "$codex_auth" == "none" ]]; then
            echo "  Codex: export OPENAI_API_KEY=\"sk-...\" (or run: codex login)"
        fi
        if [[ "$gemini_status" == "ok" && "$gemini_auth" == "none" ]]; then
            echo "  Gemini: export GEMINI_API_KEY=\"AIza...\" (or run: gemini)"
        fi
        if [[ "$cursor_agent_status" == "ok" && "$cursor_agent_auth" == "none" ]]; then
            echo "  Cursor Agent: export CURSOR_API_KEY=\"...\" (or run: agent login)"
        fi
        echo ""
        echo "See: /claude-octopus:setup for full instructions"
    else
        echo "✓ You're all set! At least one provider is ready to use."
        echo ""
        if [[ "$codex_status" == "ok" && "$codex_auth" != "none" && "$gemini_status" == "ok" && "$gemini_auth" != "none" ]]; then
            echo "  Both Codex and Gemini are configured - you'll get the best results!"
        elif [[ "$codex_status" == "ok" && "$codex_auth" != "none" ]]; then
            echo "  Codex is configured. You can optionally add Gemini for multi-provider workflows."
        elif [[ "$gemini_status" == "ok" && "$gemini_auth" != "none" ]]; then
            echo "  Gemini is configured. You can optionally add Codex for multi-provider workflows."
        elif [[ "$cursor_agent_status" == "ok" && "$cursor_agent_auth" != "none" ]]; then
            echo "  Cursor Agent is configured. You can optionally add Codex or Gemini for multi-provider workflows."
        fi
        if [[ "$perplexity_status" != "ok" ]]; then
            echo ""
            echo "  💡 Optional: Add Perplexity for live web search in research workflows:"
            echo "     export PERPLEXITY_API_KEY=\"pplx-...\"  # https://www.perplexity.ai/settings/api"
        fi
        echo ""
        echo "What you can do now (just talk naturally in Claude Code):"
        echo "  • \"Research OAuth authentication patterns\""
        echo "  • \"Build a user authentication system\""
        echo "  • \"Review this code for security issues\""
        echo "  • \"Use adversarial review to critique my implementation\""
    fi
    echo ""
}

# Pre-flight dependency validation
# Performance: Uses 1-hour cache to avoid repeated CLI checks
# v7.9.1: Supports single-provider mode (only need ONE of Codex or Gemini or Cursor Agent)
preflight_check() {
    local force_check="${1:-false}"

    # Performance: Return cached result if valid (unless forced)
    if [[ "$force_check" != "true" ]] && preflight_cache_valid; then
        local cached_status
        cached_status=$(preflight_cache_read)
        if [[ "$cached_status" == "0" ]]; then
            log DEBUG "Preflight check: using cached result (passed)"
            return 0
        fi
    fi

    log INFO "Running pre-flight checks... 🐙"
    local errors=0
    local has_codex=false
    local has_gemini=false
    local has_cursor_agent=false
    local codex_auth=false
    local gemini_auth=false
    local cursor_agent_auth=false

    # Check Codex CLI
    if command -v codex &>/dev/null; then
        has_codex=true
        log DEBUG "Codex CLI: $(command -v codex)"
        if [[ -f "$HOME/.codex/auth.json" ]] || [[ -n "${OPENAI_API_KEY:-}" ]]; then
            codex_auth=true
        fi
    fi

    # Check Gemini CLI
    if command -v gemini &>/dev/null; then
        has_gemini=true
        log DEBUG "Gemini CLI: $(command -v gemini)"
        if [[ -f "$HOME/.gemini/oauth_creds.json" ]] || [[ -n "${GEMINI_API_KEY:-}" ]] || [[ -n "${GOOGLE_API_KEY:-}" ]]; then
            gemini_auth=true
        fi
    fi

    # Check Cursor Agent CLI
    if declare -f _is_cursor_agent_binary >/dev/null 2>&1 && _is_cursor_agent_binary; then
        has_cursor_agent=true
        log DEBUG "Cursor Agent CLI: $(command -v agent)"
        if [[ -n "${CURSOR_API_KEY:-}" ]] || grep -Eq '"authInfo"[[:space:]]*:[[:space:]]*\{' "${HOME}/.cursor/cli-config.json" 2>/dev/null; then
            cursor_agent_auth=true
        fi
    fi

    # v7.9.1: Only need ONE provider to work
    if [[ "$has_codex" == "false" && "$has_gemini" == "false" && "$has_cursor_agent" == "false" ]]; then
        echo ""
        echo -e "${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║  ❌ NO AI PROVIDERS FOUND                                     ║${NC}"
        echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "Claude Octopus needs at least ${YELLOW}ONE${NC} external AI provider."
        echo ""
        echo -e "${CYAN}Option 1: Install Codex CLI (OpenAI)${NC}"
        echo -e "  npm install -g @openai/codex"
        echo -e "  codex login  ${DIM}# OAuth recommended${NC}"
        echo ""
        echo -e "${CYAN}Option 2: Install Gemini CLI (Google)${NC}"
        echo -e "  npm install -g @google/gemini-cli"
        echo -e "  gemini       ${DIM}# OAuth recommended${NC}"
        echo ""
        echo -e "${CYAN}Option 3: Install Cursor Agent CLI${NC}"
        echo -e "  curl -fsSL https://cursor.com/install | bash"
        echo -e "  agent login  ${DIM}# Cursor session${NC}"
        echo ""
        echo -e "Run ${GREEN}/octo:setup${NC} for guided configuration."
        echo ""
        preflight_cache_write "1"
        return 1
    fi

    # Check if at least one provider is authenticated
    if [[ "$codex_auth" == "false" && "$gemini_auth" == "false" && "$cursor_agent_auth" == "false" ]]; then
        echo ""
        echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}║  ⚠️  PROVIDERS FOUND BUT NOT AUTHENTICATED                    ║${NC}"
        echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        if [[ "$has_codex" == "true" ]]; then
            echo -e "${CYAN}Codex CLI installed but needs authentication:${NC}"
            echo -e "  codex login  ${DIM}# OAuth (recommended)${NC}"
            echo -e "  ${DIM}OR export OPENAI_API_KEY=\"sk-...\"${NC}"
            echo ""
        fi
        if [[ "$has_gemini" == "true" ]]; then
            echo -e "${CYAN}Gemini CLI installed but needs authentication:${NC}"
            echo -e "  gemini       ${DIM}# OAuth (recommended)${NC}"
            echo -e "  ${DIM}OR export GEMINI_API_KEY=\"...\"${NC}"
            echo ""
        fi
        if [[ "$has_cursor_agent" == "true" ]]; then
            echo -e "${CYAN}Cursor Agent CLI installed but needs authentication:${NC}"
            echo -e "  agent login  ${DIM}# Cursor session${NC}"
            echo -e "  ${DIM}OR export CURSOR_API_KEY=\"...\"${NC}"
            echo ""
        fi
        echo -e "Run ${GREEN}/octo:setup${NC} for guided configuration."
        echo ""
        preflight_cache_write "1"
        return 1
    fi

    # Show what's available
    local available_providers=""
    [[ "$codex_auth" == "true" ]] && available_providers="${available_providers}Codex "
    [[ "$gemini_auth" == "true" ]] && available_providers="${available_providers}Gemini "
    [[ "$cursor_agent_auth" == "true" ]] && available_providers="${available_providers}Cursor-Agent "
    log INFO "Available providers: $available_providers"

    # v8.48: Codex OAuth token freshness check (P1-A)
    # Warn early if token is expired/expiring — saves a failed smoke test round-trip
    if [[ "$codex_auth" == "true" ]]; then
        if ! check_codex_auth_freshness; then
            # Token expired but another authenticated provider may still work — degrade gracefully
            if [[ "$gemini_auth" == "true" ]] || [[ "$cursor_agent_auth" == "true" ]]; then
                if [[ "$gemini_auth" == "true" && "$cursor_agent_auth" == "true" ]]; then
                    log WARN "Codex OAuth expired; continuing with Gemini/Cursor Agent only"
                elif [[ "$gemini_auth" == "true" ]]; then
                    log WARN "Codex OAuth expired; continuing with Gemini only"
                else
                    log WARN "Codex OAuth expired; continuing with Cursor Agent only"
                fi
            else
                log ERROR "Codex OAuth expired and no other authenticated provider"
                preflight_cache_write "1"
                return 1
            fi
        fi
    fi

    # Check Claude CLI (optional - for grapple/squeeze)
    if command -v claude &>/dev/null; then
        log DEBUG "Claude CLI: $(command -v claude)"
    fi

    # v8.16: Detect enterprise backend
    detect_enterprise_backend

    # Support legacy GOOGLE_API_KEY
    if [[ -z "${GEMINI_API_KEY:-}" && -n "${GOOGLE_API_KEY:-}" ]]; then
        export GEMINI_API_KEY="$GOOGLE_API_KEY"
        log DEBUG "Using GOOGLE_API_KEY as GEMINI_API_KEY (legacy fallback)"
    fi

    # Check workspace
    if [[ ! -d "$WORKSPACE_DIR" ]]; then
        log WARN "Workspace not initialized. Running init..."
        init_workspace
    fi

    # Legacy plugin name warning (Issue #196)
    # Detect if user still has the old "claude-octopus" install alongside or instead of "octo"
    local claude_plugins_dir="$HOME/.claude/plugins"
    if [[ -d "$claude_plugins_dir/cache/nyldn-plugins/claude-octopus" ]]; then
        log WARN "Legacy install detected: 'claude-octopus' (renamed to 'octo' in v9.0)"
        echo -e "${YELLOW}⚠${NC}  You have a leftover 'claude-octopus' install that causes 'not found in marketplace'."
        echo -e "   Fix: ${CYAN}claude plugin uninstall claude-octopus && claude plugin install octo@nyldn-plugins${NC}"
    fi

    # Check for potentially conflicting plugins (informational only)
    local conflicts=0

    if [[ -d "$claude_plugins_dir/oh-my-claude-code" ]]; then
        log WARN "Detected: oh-my-claude-code (has own cost-aware routing)"
        ((conflicts++)) || true
    fi

    if [[ -d "$claude_plugins_dir/claude-flow" ]]; then
        log WARN "Detected: claude-flow (may spawn competing subagents)"
        ((conflicts++)) || true
    fi

    if [[ -d "$claude_plugins_dir/agents" ]] || [[ -d "$claude_plugins_dir/wshobson-agents" ]]; then
        log WARN "Detected: wshobson/agents (large context consumption)"
        ((conflicts++)) || true
    fi

    if [[ $conflicts -gt 0 ]]; then
        log INFO "Found $conflicts potentially overlapping orchestrator(s)"
        log INFO "  Claude Octopus uses external CLIs, so conflicts are unlikely"
    fi

    if [[ $errors -gt 0 ]]; then
        log ERROR "$errors pre-flight check(s) failed"
        preflight_cache_write "1"  # Cache failure
        return 1
    fi

    log INFO "Pre-flight checks passed 🐙"
    echo -e "${GREEN}✓${NC} All 8 tentacles accounted for and ready to work!"

    # v8.19: Provider smoke test (Issue #34)
    if ! provider_smoke_test "$force_check"; then
        log ERROR "Provider smoke test failed"
        preflight_cache_write "1"
        return 1
    fi

    preflight_cache_write "0"  # Cache success
    return 0
}
