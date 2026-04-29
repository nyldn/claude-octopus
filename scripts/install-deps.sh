#!/usr/bin/env bash
# Claude Octopus Dependency Installer
# ═══════════════════════════════════════════════════════════════════════════════
# Called by /octo:setup and /octo:doctor to detect and install dependencies.
# Usage: install-deps.sh [check|install|install-statusline|install-plugins]
#   check             — Report missing deps as structured output
#   install           — Install all missing deps (npm, brew, statusline, plugins)
#   install-statusline — Install just the statusline resolver
#   install-plugins   — Show plugin install commands for recommended plugins

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "${PLUGIN_ROOT}/scripts/lib/cursor-agent.sh" 2>/dev/null || true

# ── Helpers ───────────────────────────────────────────────────────────────────

has_cmd() { command -v "$1" &>/dev/null; }

node_major() {
    if has_cmd node; then
        node -e 'console.log(process.versions.node.split(".")[0])' 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# ── Check: enumerate missing deps ────────────────────────────────────────────

check_deps() {
    local missing=()
    local warnings=()
    local ok=()

    # Node.js
    if has_cmd node; then
        local nv
        nv=$(node_major)
        if [[ "$nv" -ge 16 ]]; then
            ok+=("node:Node.js $(node --version) (Tier 1 HUD ready)")
        else
            warnings+=("node_old:Node.js v${nv} detected — Tier 1 HUD needs 16+, falling back to Tier 2")
        fi
    else
        missing+=("node:Node.js — needed for Tier 1 HUD (Tier 2/3 still work)")
    fi

    # jq (Tier 2 statusline)
    if has_cmd jq; then
        ok+=("jq:jq $(jq --version 2>/dev/null || echo 'installed')")
    else
        warnings+=("jq:jq not installed — Tier 2 statusline unavailable, using Tier 3 pure bash")
    fi

    # Codex CLI
    if has_cmd codex; then
        ok+=("codex:Codex CLI installed")
    else
        missing+=("codex:Codex CLI — npm install -g @openai/codex")
    fi

    # Gemini CLI
    if has_cmd gemini; then
        ok+=("gemini:Gemini CLI installed")
    else
        missing+=("gemini:Gemini CLI — npm install -g @google/gemini-cli")
    fi

    # Ollama (optional — local LLM)
    if has_cmd ollama; then
        if curl -sf http://localhost:11434/api/tags &>/dev/null; then
            ok+=("ollama:Ollama installed and running")
        else
            warnings+=("ollama_stopped:Ollama installed but server not running — run: ollama serve")
        fi
    else
        warnings+=("ollama:Ollama not installed (optional) — brew install ollama for zero-cost local LLM")
    fi

    # GitHub Copilot CLI (optional — zero additional cost)
    if has_cmd copilot; then
        ok+=("copilot:Copilot CLI installed")
    else
        warnings+=("copilot:Copilot CLI not installed (optional) — brew install copilot-cli for zero-cost research")
    fi

    # Qwen CLI (optional — free tier)
    if has_cmd qwen; then
        ok+=("qwen:Qwen CLI installed")
    else
        warnings+=("qwen:Qwen CLI not installed (optional) — npm install -g @qwen-code/qwen-code for free-tier research")
    fi

    # Cursor Agent CLI (optional — Grok 4.20 via Cursor subscription)
    if declare -f _is_cursor_agent_binary >/dev/null 2>&1 && _is_cursor_agent_binary; then
        ok+=("cursor-agent:Cursor Agent CLI installed")
    else
        warnings+=("cursor-agent:Cursor Agent CLI not installed (optional) — curl -fsSL https://cursor.com/install | bash")
    fi

    # RTK (optional — bash output compression)
    if has_cmd rtk; then
        local rtk_ver
        rtk_ver=$(rtk --version 2>/dev/null | head -1) || rtk_ver="unknown"
        local rtk_hook="no"
        local settings_file="${HOME}/.claude/settings.json"
        if [[ -f "$settings_file" ]] && grep -q 'rtk' "$settings_file" 2>/dev/null; then
            rtk_hook="yes"
        fi
        if [[ "$rtk_hook" == "yes" ]]; then
            ok+=("rtk:RTK ${rtk_ver} installed, hook active (bash output compression enabled)")
        else
            warnings+=("rtk:RTK ${rtk_ver} installed but Claude Code hook not configured. Run: rtk init -g")
        fi
    else
        warnings+=("rtk:RTK not installed (optional) — saves 60-90% tokens on bash output. Install: brew install rtk && rtk init -g. Run /octo:doctor for guided setup.")
    fi

    # Statusline resolver
    local resolver="$HOME/.claude-octopus/statusline.sh"
    if [[ -f "$resolver" ]]; then
        ok+=("statusline:Statusline resolver installed")
    else
        missing+=("statusline:Statusline resolver — auto-updates version on plugin upgrades")
    fi

    # Statusline settings.json check
    local settings="$HOME/.claude/settings.json"
    if [[ -f "$settings" ]]; then
        if grep -q 'plugins/cache/nyldn-plugins/octo/[0-9]' "$settings" 2>/dev/null; then
            warnings+=("statusline_stale:settings.json has versioned statusline path — will go stale on updates")
        elif grep -q 'claude-octopus/statusline.sh' "$settings" 2>/dev/null; then
            ok+=("statusline_cfg:settings.json uses stable resolver path")
        elif grep -q 'octopus-statusline' "$settings" 2>/dev/null; then
            ok+=("statusline_cfg:Statusline configured (custom path)")
        fi
    fi

    # Recommended plugins
    local plugins_json="$HOME/.claude/settings.json"
    if [[ -f "$plugins_json" ]]; then
        if grep -q '"claude-mem@thedotmack": true' "$plugins_json" 2>/dev/null; then
            ok+=("claude-mem:claude-mem plugin installed")
        else
            missing+=("claude-mem:claude-mem plugin — persistent cross-session memory")
        fi
        if grep -q '"document-skills@anthropic-agent-skills": true' "$plugins_json" 2>/dev/null; then
            ok+=("document-skills:document-skills plugin installed")
        else
            warnings+=("document-skills:document-skills plugin — PDF/DOCX/PPTX/XLSX export (optional, needed for /octo:km)")
        fi
    fi

    # Output
    echo "=== DEPENDENCY CHECK ==="
    echo ""
    if [[ ${#ok[@]} -gt 0 ]]; then
        echo "✅ Installed:"
        for item in "${ok[@]}"; do
            echo "   ✓ ${item#*:}"
        done
    fi
    if [[ ${#warnings[@]} -gt 0 ]]; then
        echo ""
        echo "⚠️  Warnings:"
        for item in "${warnings[@]}"; do
            echo "   ⚠ ${item#*:}"
        done
    fi
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo ""
        echo "❌ Missing:"
        for item in "${missing[@]}"; do
            echo "   ✗ ${item#*:}"
        done
    fi
    echo ""
    if [[ ${#missing[@]} -eq 0 && ${#warnings[@]} -eq 0 ]]; then
        echo "STATUS=healthy"
    elif [[ ${#missing[@]} -eq 0 ]]; then
        echo "STATUS=warnings"
    else
        echo "STATUS=missing_deps"
        echo "MISSING_COUNT=${#missing[@]}"
    fi
}

# ── Install: statusline resolver ──────────────────────────────────────────────

install_statusline() {
    local src="$PLUGIN_ROOT/hooks/statusline-resolver.sh"
    local dst="$HOME/.claude-octopus/statusline.sh"

    if [[ ! -f "$src" ]]; then
        echo "ERROR: statusline-resolver.sh not found in plugin" >&2
        return 1
    fi

    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    chmod +x "$dst"
    echo "✓ Installed statusline resolver to $dst"

    # Fix settings.json if stale
    local settings="$HOME/.claude/settings.json"
    if [[ -f "$settings" ]] && grep -q 'plugins/cache/nyldn-plugins/octo/[0-9]' "$settings" 2>/dev/null; then
        local tmp="${settings}.octotmp.$$"
        if sed "s|bash.*plugins/cache/nyldn-plugins/octo/[0-9][^\"]*|bash ~/.claude-octopus/statusline.sh|g" \
            "$settings" > "$tmp" 2>/dev/null; then
            mv "$tmp" "$settings"
            echo "✓ Updated settings.json to use stable resolver path"
        else
            rm -f "$tmp"
            echo "⚠ Could not auto-fix settings.json — update statusLine command manually"
        fi
    fi
}

# ── Install: show plugin install commands ─────────────────────────────────────

install_plugins() {
    local settings="$HOME/.claude/settings.json"
    local any_missing=false

    echo "=== RECOMMENDED PLUGINS ==="
    echo ""

    if [[ -f "$settings" ]] && ! grep -q '"claude-mem@thedotmack": true' "$settings" 2>/dev/null; then
        echo "📦 claude-mem — Persistent cross-session memory"
        echo "   Enables /mem-search, /make-plan, /do workflows"
        echo "   Install: /plugin install claude-mem@thedotmack"
        echo ""
        any_missing=true
    fi

    if [[ -f "$settings" ]] && ! grep -q '"document-skills@anthropic-agent-skills": true' "$settings" 2>/dev/null; then
        echo "📦 document-skills — Document export (PDF, DOCX, PPTX, XLSX)"
        echo "   Required for /octo:km Knowledge Work mode"
        echo "   Install: /plugin install document-skills@anthropic-agent-skills"
        echo ""
        any_missing=true
    fi

    if [[ "$any_missing" == "false" ]]; then
        echo "✓ All recommended plugins are installed"
    else
        echo "---"
        echo "Note: Plugin installs require the /plugin command in Claude Code."
        echo "Copy and paste the install commands above."
    fi
}

# ── Install: all missing deps ─────────────────────────────────────────────────

install_all() {
    echo "=== INSTALLING DEPENDENCIES ==="
    echo ""

    # Statusline resolver (always safe to install/update)
    install_statusline
    echo ""

    # jq
    if ! has_cmd jq; then
        if has_cmd brew; then
            echo "Installing jq via Homebrew..."
            brew install jq 2>&1 && echo "✓ jq installed" || echo "⚠ jq install failed — Tier 2 statusline unavailable"
        elif has_cmd apt-get; then
            echo "Installing jq via apt..."
            sudo apt-get install -y jq 2>&1 && echo "✓ jq installed" || echo "⚠ jq install failed"
        else
            echo "⚠ Cannot auto-install jq — install manually (brew install jq / apt install jq)"
        fi
        echo ""
    fi

    # Codex CLI
    if ! has_cmd codex; then
        if has_cmd npm; then
            echo "Installing Codex CLI..."
            npm install -g @openai/codex 2>&1 && echo "✓ Codex CLI installed" || echo "⚠ Codex install failed — try: sudo npm install -g @openai/codex"
        else
            echo "⚠ Cannot install Codex CLI — npm not found. Install Node.js first: https://nodejs.org/"
        fi
        echo ""
    fi

    # Gemini CLI
    if ! has_cmd gemini; then
        if has_cmd npm; then
            echo "Installing Gemini CLI..."
            npm install -g @google/gemini-cli 2>&1 && echo "✓ Gemini CLI installed" || echo "⚠ Gemini install failed — try: sudo npm install -g @google/gemini-cli"
        else
            echo "⚠ Cannot install Gemini CLI — npm not found. Install Node.js first: https://nodejs.org/"
        fi
        echo ""
    fi

    # Plugins (can't auto-install — show commands)
    install_plugins
}

# ── Main ──────────────────────────────────────────────────────────────────────

case "${1:-check}" in
    check)             check_deps ;;
    install)           install_all ;;
    install-statusline) install_statusline ;;
    install-plugins)   install_plugins ;;
    *)
        echo "Usage: install-deps.sh [check|install|install-statusline|install-plugins]" >&2
        exit 1
        ;;
esac
