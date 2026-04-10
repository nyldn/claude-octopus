#!/usr/bin/env bash
# Claude Octopus — Environment Doctor Diagnostics
# Extracted from orchestrate.sh
# Source-safe: no main execution block.

# ═══════════════════════════════════════════════════════════════════════════════
# MODULAR DOCTOR SYSTEM (v8.16.0)
# 8 check categories, structured results, category filtering, JSON output
# ═══════════════════════════════════════════════════════════════════════════════

# Result accumulator (parallel arrays for bash 3.x compat)
DOCTOR_RESULTS_NAME=()
DOCTOR_RESULTS_CAT=()
DOCTOR_RESULTS_STATUS=()   # pass|warn|fail
DOCTOR_RESULTS_MSG=()
DOCTOR_RESULTS_DETAIL=()

doctor_add() {
    local name="$1" cat="$2" status="$3" msg="$4" detail="${5:-}"
    DOCTOR_RESULTS_NAME+=("$name")
    DOCTOR_RESULTS_CAT+=("$cat")
    DOCTOR_RESULTS_STATUS+=("$status")
    DOCTOR_RESULTS_MSG+=("$msg")
    DOCTOR_RESULTS_DETAIL+=("$detail")
}

# --- Category 1: Providers ---
# v8.39.0: Update external CLI dependencies to latest versions
cmd_update_clis() {
    echo -e "${CYAN}🐙 Claude Octopus — CLI Update${NC}"
    echo ""

    local updated=0 failed=0

    # Update Codex CLI
    echo -e "  ${YELLOW}→${NC} Updating Codex CLI (@openai/codex)..."
    if npm install -g @openai/codex 2>&1 | sed 's/^/    /'; then
        local codex_ver
        codex_ver=$(codex --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
        echo -e "  ${GREEN}✓${NC} Codex CLI updated to v${codex_ver}"
        ((updated++))
    else
        echo -e "  ${RED}✗${NC} Codex CLI update failed. Try manually: npm install -g @openai/codex"
        ((failed++))
    fi
    echo ""

    # Update Gemini CLI
    echo -e "  ${YELLOW}→${NC} Updating Gemini CLI (@google/gemini-cli)..."
    if npm install -g @google/gemini-cli 2>&1 | sed 's/^/    /'; then
        local gemini_ver
        gemini_ver=$(gemini --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
        echo -e "  ${GREEN}✓${NC} Gemini CLI updated to v${gemini_ver}"
        ((updated++))
    else
        echo -e "  ${RED}✗${NC} Gemini CLI update failed. Try manually: npm install -g @google/gemini-cli"
        ((failed++))
    fi
    echo ""

    # Summary
    if [[ $failed -eq 0 ]]; then
        echo -e "${GREEN}✅ All CLIs updated successfully (${updated} packages)${NC}"
    else
        echo -e "${YELLOW}⚠ ${updated} updated, ${failed} failed${NC}"
    fi
}

doctor_check_providers() {
    # Claude Code version + compatibility
    local cc_ver="${CLAUDE_CODE_VERSION:-}"
    if [[ -n "$cc_ver" ]]; then
        doctor_add "claude-code-version" "providers" "pass" \
            "Claude Code v${cc_ver}" "$(command -v claude 2>/dev/null || echo 'path unknown')"
    else
        doctor_add "claude-code-version" "providers" "warn" \
            "Claude Code version unknown" "Could not detect version"
    fi

    # Codex CLI
    if command -v codex &>/dev/null; then
        local codex_ver codex_path
        codex_ver=$(codex --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
        codex_path=$(command -v codex)
        if [[ "$codex_ver" != "unknown" ]] && [[ "$codex_ver" =~ ^0\.(([0-9]{1,2})|9[0-9])\. ]]; then
            doctor_add "codex-cli" "providers" "warn" \
                "Codex CLI v${codex_ver} (outdated)" \
                "${codex_path} — run orchestrate.sh update-clis or: npm install -g @openai/codex"
        else
            doctor_add "codex-cli" "providers" "pass" \
                "Codex CLI v${codex_ver}" "$codex_path"
        fi
    else
        doctor_add "codex-cli" "providers" "warn" \
            "Codex CLI not installed" "npm install -g @openai/codex"
    fi

    # Gemini CLI
    if command -v gemini &>/dev/null; then
        local gemini_ver gemini_path
        gemini_ver=$(gemini --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
        gemini_path=$(command -v gemini)
        doctor_add "gemini-cli" "providers" "pass" \
            "Gemini CLI v${gemini_ver}" "$gemini_path"
    else
        doctor_add "gemini-cli" "providers" "warn" \
            "Gemini CLI not installed" "npm install -g @google/gemini-cli"
    fi

    # Perplexity API (v8.24.0 - optional)
    if [[ -n "${PERPLEXITY_API_KEY:-}" ]]; then
        doctor_add "perplexity-api" "providers" "pass" \
            "Perplexity API configured" "PERPLEXITY_API_KEY set — web search enabled in discover workflows"
    else
        doctor_add "perplexity-api" "providers" "info" \
            "Perplexity not configured (optional)" "export PERPLEXITY_API_KEY=\"pplx-...\" for live web search"
    fi

    # Ollama (local LLM — optional)
    if command -v ollama &>/dev/null; then
        local ollama_health
        ollama_health=$(curl -sf http://localhost:11434/api/tags 2>/dev/null) || true
        if [[ -n "$ollama_health" ]]; then
            local model_count
            model_count=$(printf '%s' "$ollama_health" | grep -c '"name"' 2>/dev/null || echo "0")
            doctor_add "ollama" "providers" "pass" \
                "Ollama running (${model_count} models)" "http://localhost:11434"
        else
            doctor_add "ollama" "providers" "warn" \
                "Ollama installed but server not running" "Run: ollama serve"
        fi
    else
        doctor_add "ollama" "providers" "info" \
            "Ollama not installed (optional)" "brew install ollama — local LLM for zero-cost workflows"
    fi

    # GitHub Copilot CLI (optional — zero additional cost, uses GitHub subscription)
    if command -v copilot &>/dev/null; then
        local copilot_auth="none"
        if [[ -n "${COPILOT_GITHUB_TOKEN:-}" ]]; then
            copilot_auth="env:COPILOT_GITHUB_TOKEN"
        elif [[ -n "${GH_TOKEN:-}" ]]; then
            copilot_auth="env:GH_TOKEN"
        elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
            copilot_auth="env:GITHUB_TOKEN"
        elif [[ -f "${HOME}/.copilot/config.json" ]]; then
            copilot_auth="keychain"
        elif command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
            copilot_auth="gh-cli"
        fi
        if [[ "$copilot_auth" != "none" ]]; then
            doctor_add "copilot-cli" "providers" "pass" \
                "Copilot CLI installed (auth: ${copilot_auth})" "$(command -v copilot) — research/exploration via copilot -p"
        else
            doctor_add "copilot-cli" "providers" "warn" \
                "Copilot CLI installed but not authenticated" "Run: copilot login (or set COPILOT_GITHUB_TOKEN)"
        fi
    else
        doctor_add "copilot-cli" "providers" "info" \
            "Copilot CLI not installed (optional)" "brew install copilot-cli — zero-cost research via GitHub subscription"
    fi

    # Qwen CLI (optional — free tier)
    if command -v qwen &>/dev/null; then
        local qwen_auth="none"
        if [[ -f "${HOME}/.qwen/oauth_creds.json" ]]; then
            qwen_auth="oauth"
        elif [[ -f "${HOME}/.qwen/config.json" ]]; then
            qwen_auth="config"
        elif [[ -n "${QWEN_API_KEY:-}" ]]; then
            qwen_auth="env:QWEN_API_KEY"
        fi
        if [[ "$qwen_auth" != "none" ]]; then
            doctor_add "qwen-cli" "providers" "pass" \
                "Qwen CLI installed (auth: ${qwen_auth})" "$(command -v qwen) — free-tier research via Qwen OAuth"
        else
            doctor_add "qwen-cli" "providers" "warn" \
                "Qwen CLI installed but not authenticated" "Run: qwen (to trigger OAuth) or set QWEN_API_KEY"
        fi
    else
        doctor_add "qwen-cli" "providers" "info" \
            "Qwen CLI not installed (optional)" "npm install -g @qwen-code/qwen-code — free-tier research via Qwen OAuth"
    fi

    # OpenCode CLI (optional — multi-provider router, v9.11.0)
    if command -v opencode &>/dev/null; then
        local opencode_auth="none"
        # Portable timeout: prefer gtimeout (macOS via coreutils), fallback to timeout
        local _timeout_cmd="timeout"
        command -v gtimeout &>/dev/null && _timeout_cmd="gtimeout"
        if [[ -f "${HOME}/.local/share/opencode/auth.json" ]]; then
            if "$_timeout_cmd" 3 opencode auth list &>/dev/null; then
                opencode_auth="multi"
            else
                opencode_auth="expired"
            fi
        fi
        # Check env-based auth if file-based auth not found
        if [[ "$opencode_auth" == "none" ]]; then
            if [[ -n "${GITHUB_TOKEN:-}" || -n "${OPENROUTER_API_KEY:-}" || -n "${Z_AI_API_KEY:-}" || -n "${MINIMAX_API_KEY:-}" ]]; then
                opencode_auth="env"
            fi
        fi
        if [[ "$opencode_auth" != "none" && "$opencode_auth" != "expired" ]]; then
            doctor_add "opencode-cli" "providers" "pass" \
                "OpenCode CLI installed (auth: ${opencode_auth})" "$(command -v opencode) — multi-provider router (google, openai, z-ai, openrouter)"
        elif [[ "$opencode_auth" == "expired" ]]; then
            doctor_add "opencode-cli" "providers" "warn" \
                "OpenCode CLI installed but auth expired" "Run: opencode auth login (to refresh credentials)"
        else
            doctor_add "opencode-cli" "providers" "warn" \
                "OpenCode CLI installed but not authenticated" "Run: opencode auth login (or set GITHUB_TOKEN/OPENROUTER_API_KEY)"
        fi
    else
        doctor_add "opencode-cli" "providers" "info" \
            "OpenCode CLI not installed (optional)" "npm install -g opencode-ai — multi-provider router for google, openai, z-ai models"
    fi

    # v9.0: Check recent provider fallback history
    local fallback_log="${HOME}/.claude-octopus/provider-fallbacks.log"
    if [[ -f "$fallback_log" ]]; then
        local recent_failures=0 codex_failures=0 gemini_failures=0
        local cutoff
        cutoff=$(date -v-24H +%Y-%m-%d 2>/dev/null || date -d '24 hours ago' +%Y-%m-%d 2>/dev/null || echo "")
        if [[ -n "$cutoff" ]]; then
            while IFS= read -r line; do
                local log_date="${line:1:10}"  # Extract date from [YYYY-MM-DDTHH:MM:SS]
                if [[ "$log_date" > "$cutoff" || "$log_date" == "$cutoff" ]]; then
                    ((recent_failures++)) || true
                    [[ "$line" == *"provider=codex"* ]] && ((codex_failures++)) || true
                    [[ "$line" == *"provider=gemini"* ]] && ((gemini_failures++)) || true
                fi
            done < "$fallback_log"
        else
            recent_failures=$(wc -l < "$fallback_log" | tr -d ' ')
        fi
        if [[ $recent_failures -gt 0 ]]; then
            local detail="Last 24h:"
            [[ $codex_failures -gt 0 ]] && detail="$detail Codex failed ${codex_failures}x"
            [[ $gemini_failures -gt 0 ]] && detail="$detail Gemini failed ${gemini_failures}x"
            doctor_add "provider-fallbacks" "providers" "warn" \
                "${recent_failures} provider fallback(s) in last 24h" \
                "${detail}. Check auth: codex auth / gemini auth. Log: ${fallback_log}"
        else
            doctor_add "provider-fallbacks" "providers" "pass" \
                "No recent provider fallbacks" ""
        fi
    fi
}

# --- Category 2: Auth ---
doctor_check_auth() {
    # Codex auth
    if command -v codex &>/dev/null; then
        if [[ -f "$HOME/.codex/auth.json" ]] || [[ -n "${OPENAI_API_KEY:-}" ]]; then
            local method="auth.json"
            [[ -n "${OPENAI_API_KEY:-}" ]] && method="OPENAI_API_KEY"
            doctor_add "codex-auth" "auth" "pass" \
                "Codex authenticated" "via $method"
        else
            doctor_add "codex-auth" "auth" "fail" \
                "Codex not authenticated" "Run: codex login  OR  export OPENAI_API_KEY=\"sk-...\""
        fi
    fi

    # Gemini auth
    if command -v gemini &>/dev/null; then
        if [[ -f "$HOME/.gemini/oauth_creds.json" ]] || [[ -n "${GEMINI_API_KEY:-}" ]] || [[ -n "${GOOGLE_API_KEY:-}" ]]; then
            local method="oauth_creds.json"
            [[ -n "${GEMINI_API_KEY:-}" ]] && method="GEMINI_API_KEY"
            [[ -n "${GOOGLE_API_KEY:-}" ]] && method="GOOGLE_API_KEY"
            doctor_add "gemini-auth" "auth" "pass" \
                "Gemini authenticated" "via $method"
        else
            doctor_add "gemini-auth" "auth" "fail" \
                "Gemini not authenticated" "Run: gemini  OR  export GEMINI_API_KEY=\"...\""
        fi
    fi

    # Perplexity auth (v8.24.0 - optional, info-only)
    if [[ -n "${PERPLEXITY_API_KEY:-}" ]]; then
        doctor_add "perplexity-auth" "auth" "pass" \
            "Perplexity authenticated" "via PERPLEXITY_API_KEY"
    fi

    # At least one provider must be authenticated
    local any_auth=false
    if [[ -f "$HOME/.codex/auth.json" ]] || [[ -n "${OPENAI_API_KEY:-}" ]] || \
       [[ -f "$HOME/.gemini/oauth_creds.json" ]] || [[ -n "${GEMINI_API_KEY:-}" ]] || [[ -n "${GOOGLE_API_KEY:-}" ]]; then
        any_auth=true
    fi
    if [[ "$any_auth" == "false" ]]; then
        doctor_add "any-provider-auth" "auth" "fail" \
            "No provider authenticated" "At least one of Codex or Gemini must be authenticated"
    else
        doctor_add "any-provider-auth" "auth" "pass" \
            "At least one provider authenticated" ""
    fi

    # Enterprise backend
    local backend="${OCTOPUS_BACKEND:-api}"
    if [[ "$backend" != "api" ]]; then
        doctor_add "enterprise-backend" "auth" "pass" \
            "Enterprise backend: $backend" ""
    fi
}

# --- Category 3: Config ---
doctor_check_config() {
    local plugin_json="$SCRIPT_DIR/../.claude-plugin/plugin.json"

    # Plugin version
    local plugin_ver
    plugin_ver=$(jq -r '.version' "$plugin_json" 2>/dev/null || echo "unknown")
    if [[ "$plugin_ver" != "unknown" ]]; then
        doctor_add "plugin-version" "config" "pass" \
            "Plugin v${plugin_ver}" ""
    else
        doctor_add "plugin-version" "config" "fail" \
            "Cannot read plugin version" "$plugin_json"
    fi

    # Install scope
    local scope="unknown"
    if [[ "$PLUGIN_DIR" == "$HOME/.claude/plugins/"* ]]; then
        scope="user"
    elif [[ "$PLUGIN_DIR" == *"/.claude/plugins/"* ]]; then
        scope="project"
    else
        scope="manual/dev"
    fi
    doctor_add "install-scope" "config" "pass" \
        "Install scope: $scope" "$PLUGIN_DIR"

    # Feature flag / CC version consistency
    local cc_ver="${CLAUDE_CODE_VERSION:-}"
    if [[ -n "$cc_ver" ]]; then
        # Check SUPPORTS_SONNET_46 should be true on v2.1.45+
        if version_compare "$cc_ver" "2.1.45" ">=" 2>/dev/null && [[ "$SUPPORTS_SONNET_46" != "true" ]]; then
            doctor_add "flag-sonnet-46" "config" "warn" \
                "SUPPORTS_SONNET_46 is false on CC v${cc_ver}" \
                "Expected true for v2.1.45+; feature detection may have failed"
        fi
        # Check SUPPORTS_STABLE_BG_AGENTS should be true on v2.1.47+
        if version_compare "$cc_ver" "2.1.47" ">=" 2>/dev/null && [[ "$SUPPORTS_STABLE_BG_AGENTS" != "true" ]]; then
            doctor_add "flag-stable-bg" "config" "warn" \
                "SUPPORTS_STABLE_BG_AGENTS is false on CC v${cc_ver}" \
                "Expected true for v2.1.47+; feature detection may have failed"
        fi
        # Check SUPPORTS_CONFIG_CHANGE_HOOK should be true on v2.1.49+
        if version_compare "$cc_ver" "2.1.49" ">=" 2>/dev/null && [[ "$SUPPORTS_CONFIG_CHANGE_HOOK" != "true" ]]; then
            doctor_add "flag-config-change" "config" "warn" \
                "SUPPORTS_CONFIG_CHANGE_HOOK is false on CC v${cc_ver}" \
                "Expected true for v2.1.49+; feature detection may have failed"
        fi
        # Check SUPPORTS_WORKTREE_ISOLATION should be true on v2.1.50+
        if version_compare "$cc_ver" "2.1.50" ">=" 2>/dev/null && [[ "$SUPPORTS_WORKTREE_ISOLATION" != "true" ]]; then
            doctor_add "flag-worktree" "config" "warn" \
                "SUPPORTS_WORKTREE_ISOLATION is false on CC v${cc_ver}" \
                "Expected true for v2.1.50+; feature detection may have failed"
        fi
        # Check SUPPORTS_HTTP_HOOKS should be true on v2.1.63+
        if version_compare "$cc_ver" "2.1.63" ">=" 2>/dev/null && [[ "$SUPPORTS_HTTP_HOOKS" != "true" ]]; then
            doctor_add "flag-http-hooks" "config" "warn" \
                "SUPPORTS_HTTP_HOOKS is false on CC v${cc_ver}" \
                "Expected true for v2.1.63+; feature detection may have failed"
        fi

        # v2.1.78+ checks
        if version_compare "$cc_ver" "2.1.78" ">=" 2>/dev/null; then
            if [[ "$SUPPORTS_STOP_FAILURE_HOOK" != "true" ]]; then
                doctor_add "flag-stop-failure" "config" "warn" \
                    "SUPPORTS_STOP_FAILURE_HOOK is false on CC v${cc_ver}" \
                    "Expected true for v2.1.78+; StopFailure hook enables API error telemetry"
            fi
            if [[ -z "${CLAUDE_PLUGIN_DATA:-}" ]]; then
                doctor_add "plugin-data-dir" "config" "info" \
                    "CLAUDE_PLUGIN_DATA not set — using legacy ~/.claude-octopus/" \
                    "CC v2.1.78+ provides persistent plugin state via \${CLAUDE_PLUGIN_DATA}"
            fi
        fi

        # v2.1.83+ checks
        if version_compare "$cc_ver" "2.1.83" ">=" 2>/dev/null; then
            if [[ "$SUPPORTS_CWD_CHANGED_HOOK" != "true" ]]; then
                doctor_add "flag-cwd-changed" "config" "warn" \
                    "SUPPORTS_CWD_CHANGED_HOOK is false on CC v${cc_ver}" \
                    "Expected true for v2.1.83+; CwdChanged enables automatic context re-detection"
            fi
        fi
    fi

    # Agent Teams enable check
    if [[ "${SUPPORTS_AGENT_TEAMS:-false}" == "true" && "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-0}" != "1" ]]; then
        doctor_add "agent-teams-disabled" "config" "info" \
            "Agent Teams supported but not enabled" \
            "Set CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 in settings.json env to enable CC native agent teams for /octo:parallel"
    fi

    # v9.13: Circuit breaker state check
    local _cb_dir="${CLAUDE_PLUGIN_DATA:-${WORKSPACE_DIR:-${HOME}/.claude-octopus}}/provider-state"
    if [[ -d "$_cb_dir" ]]; then
        local _open_circuits=""
        for _sf in "$_cb_dir"/*.state; do
            [[ -f "$_sf" ]] || continue
            local _prov _state
            _prov=$(basename "$_sf" .state)
            _state=$(<"$_sf" 2>/dev/null)
            if [[ "$_state" == "open" ]]; then
                _open_circuits="${_open_circuits:+$_open_circuits, }$_prov"
            fi
        done
        if [[ -n "$_open_circuits" ]]; then
            doctor_add "circuit-breaker-open" "providers" "warn" \
                "Circuit breaker OPEN for: $_open_circuits" \
                "These providers hit failure thresholds and are temporarily skipped. They auto-recover after cooldown."
        else
            doctor_add "circuit-breaker-state" "providers" "pass" \
                "All provider circuits closed (healthy)" ""
        fi
    fi

    # Legacy plugin name detection (Issue #196)
    # Users who installed as "claude-octopus@nyldn-plugins" (pre-v9.0 name) get
    # "Plugin claude-octopus not found in marketplace" because the marketplace
    # now lists the plugin as "octo". Detect this and provide the fix.
    local legacy_cache_dir="$HOME/.claude/plugins/cache/nyldn-plugins/claude-octopus"
    if [[ -d "$legacy_cache_dir" ]]; then
        doctor_add "legacy-plugin-name" "config" "fail" \
            "Legacy 'claude-octopus' install detected — causes 'not found in marketplace'" \
            "Fix: claude plugin uninstall claude-octopus && claude plugin install octo@nyldn-plugins"
    elif [[ "$PLUGIN_DIR" == *"/claude-octopus"* && "$PLUGIN_DIR" != *"/claude-octopus/"*"octo"* ]]; then
        # Catch installs where the directory name contains the old name
        doctor_add "legacy-plugin-name" "config" "warn" \
            "Plugin path contains legacy name 'claude-octopus'" \
            "If you see 'not found in marketplace': claude plugin uninstall claude-octopus && claude plugin install octo@nyldn-plugins"
    else
        doctor_add "legacy-plugin-name" "config" "pass" \
            "Plugin name: octo (correct)" ""
    fi

    # OCTOPUS_BACKEND correctly detected
    local backend="${OCTOPUS_BACKEND:-api}"
    doctor_add "backend-detection" "config" "pass" \
        "Backend: $backend" ""
}

# --- Category 4: State ---
doctor_check_state() {
    # state.json integrity
    if [[ -f ".claude-octopus/state.json" ]]; then
        if jq empty ".claude-octopus/state.json" 2>/dev/null; then
            doctor_add "state-json" "state" "pass" \
                "state.json valid" ".claude-octopus/state.json"
        else
            doctor_add "state-json" "state" "fail" \
                "state.json is invalid JSON" "File exists but cannot be parsed"
        fi
    else
        doctor_add "state-json" "state" "pass" \
            "No project state (normal for new projects)" ""
    fi

    # Stale results files (older than 7 days)
    if [[ -d "${WORKSPACE_DIR}/results" ]]; then
        local stale_count
        stale_count=$(find "${WORKSPACE_DIR}/results" -name "*.md" -type f -mtime +7 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$stale_count" -gt 0 ]]; then
            doctor_add "stale-results" "state" "warn" \
                "${stale_count} result file(s) older than 7 days" \
                "In ${WORKSPACE_DIR}/results — consider cleanup with: orchestrate.sh cleanup"
        else
            doctor_add "stale-results" "state" "pass" \
                "No stale result files" ""
        fi
    fi

    # Workspace dir exists and is writable
    if [[ -d "$WORKSPACE_DIR" && -w "$WORKSPACE_DIR" ]]; then
        doctor_add "workspace-writable" "state" "pass" \
            "Workspace writable" "$WORKSPACE_DIR"
    elif [[ -d "$WORKSPACE_DIR" ]]; then
        doctor_add "workspace-writable" "state" "fail" \
            "Workspace not writable" "$WORKSPACE_DIR"
    else
        doctor_add "workspace-writable" "state" "fail" \
            "Workspace directory missing" "$WORKSPACE_DIR"
    fi

    # Preflight cache staleness
    if [[ -f "$PREFLIGHT_CACHE_FILE" ]]; then
        if preflight_cache_valid; then
            doctor_add "preflight-cache" "state" "pass" \
                "Preflight cache valid" "$PREFLIGHT_CACHE_FILE"
        else
            doctor_add "preflight-cache" "state" "warn" \
                "Preflight cache stale" "Will re-run on next workflow invocation"
        fi
    else
        doctor_add "preflight-cache" "state" "pass" \
            "No preflight cache (will create on first run)" ""
    fi
}

# --- Category 5: Hooks ---
doctor_check_hooks() {
    local hooks_json="$SCRIPT_DIR/../.claude-plugin/hooks.json"
    if [[ ! -f "$hooks_json" ]]; then
        doctor_add "hooks-file" "hooks" "fail" \
            "hooks.json not found" "$hooks_json"
        return
    fi

    if ! jq empty "$hooks_json" 2>/dev/null; then
        doctor_add "hooks-file" "hooks" "fail" \
            "hooks.json is invalid JSON" "$hooks_json"
        return
    fi

    doctor_add "hooks-file" "hooks" "pass" \
        "hooks.json valid" "$hooks_json"

    # Extract all command paths from hooks.json and verify each exists
    local commands
    commands=$(jq -r '.. | objects | select(.command?) | .command' "$hooks_json" 2>/dev/null | tr -d '\r' || true)
    if [[ -z "$commands" ]]; then
        return
    fi

    local hook_count=0
    local broken_count=0
    while IFS= read -r cmd_path; do
        [[ -z "$cmd_path" ]] && continue
        ((hook_count++)) || true

        # Resolve ${CLAUDE_PLUGIN_ROOT} to actual plugin dir
        local resolved_path="$cmd_path"
        resolved_path="${resolved_path//\$\{CLAUDE_PLUGIN_ROOT\}/$PLUGIN_DIR}"
        resolved_path="${resolved_path//\$CLAUDE_PLUGIN_ROOT/$PLUGIN_DIR}"

        # Handle paths with arguments, env-var prefixes, and bash wrappers
        local script_path
        # Strip leading env-var assignments (KEY=value ...)
        local cleaned="$resolved_path"
        while [[ "$cleaned" =~ ^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+(.*) ]]; do
            cleaned="${BASH_REMATCH[1]}"
        done
        # Strip leading 'bash ' wrapper
        cleaned="${cleaned#bash }"
        # Remove surrounding quotes
        cleaned="${cleaned#\"}"
        cleaned="${cleaned%\"}"
        script_path=$(echo "$cleaned" | awk '{print $1}')

        if [[ ! -f "$script_path" ]]; then
            doctor_add "hook-script-$(basename "$script_path")" "hooks" "fail" \
                "Hook script missing: $(basename "$script_path")" "$cmd_path -> $script_path"
            ((broken_count++)) || true
        elif [[ ! -x "$script_path" ]]; then
            doctor_add "hook-script-$(basename "$script_path")" "hooks" "warn" \
                "Hook script not executable: $(basename "$script_path")" "$script_path"
            ((broken_count++)) || true
        fi
    done <<< "$commands"

    if [[ $broken_count -eq 0 && $hook_count -gt 0 ]]; then
        doctor_add "hook-scripts-all" "hooks" "pass" \
            "All $hook_count hook scripts valid" ""
    fi
}

# --- Category 6: Scheduler ---
doctor_check_scheduler() {
    local sched_dir="${HOME}/.claude-octopus/scheduler"
    local runtime_dir="${sched_dir}/runtime"
    local pid_file="${runtime_dir}/daemon.pid"
    local jobs_dir="${sched_dir}/jobs"
    local switches_dir="${sched_dir}/switches"

    # Daemon running check
    if [[ -f "$pid_file" ]]; then
        local daemon_pid
        daemon_pid=$(cat "$pid_file" 2>/dev/null)
        if [[ -n "$daemon_pid" ]] && kill -0 "$daemon_pid" 2>/dev/null; then
            doctor_add "scheduler-daemon" "scheduler" "pass" \
                "Scheduler daemon running" "PID $daemon_pid"
        else
            doctor_add "scheduler-daemon" "scheduler" "warn" \
                "Scheduler PID file stale" "PID $daemon_pid not running; start with /octo:scheduler start"
        fi
    else
        doctor_add "scheduler-daemon" "scheduler" "pass" \
            "Scheduler not configured (normal)" "Start with /octo:scheduler start"
    fi

    # Jobs directory
    if [[ -d "$jobs_dir" ]]; then
        local job_count
        job_count=$(find "$jobs_dir" -name "*.json" -type f 2>/dev/null | wc -l | tr -d ' ')
        doctor_add "scheduler-jobs" "scheduler" "pass" \
            "${job_count} scheduled job(s)" "$jobs_dir"
    fi

    # Budget gate
    if [[ -n "${OCTOPUS_MAX_COST_USD:-}" ]]; then
        doctor_add "budget-gate" "scheduler" "pass" \
            "Budget gate: \$${OCTOPUS_MAX_COST_USD}/day" ""
    else
        doctor_add "budget-gate" "scheduler" "warn" \
            "No budget gate configured" "Set OCTOPUS_MAX_COST_USD to limit daily spend"
    fi

    # Kill switches
    if [[ -d "$switches_dir" ]]; then
        local kill_files
        kill_files=$(find "$switches_dir" -name "*.kill" -type f 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$kill_files" -gt 0 ]]; then
            doctor_add "kill-switches" "scheduler" "warn" \
                "${kill_files} kill switch(es) active" "Check ${switches_dir}/*.kill"
        else
            doctor_add "kill-switches" "scheduler" "pass" \
                "No kill switches active" ""
        fi
    fi
}

# --- Category 7: Skills ---
doctor_check_skills() {
    local plugin_json="$SCRIPT_DIR/../.claude-plugin/plugin.json"
    if [[ ! -f "$plugin_json" ]]; then
        doctor_add "plugin-json" "skills" "fail" \
            "plugin.json not found" "$plugin_json"
        return
    fi

    # Verify skill files exist
    local skill_total skill_missing=0
    skill_total=$(jq '.skills | length' "$plugin_json" 2>/dev/null || echo "0")
    local i=0
    while [[ $i -lt $skill_total ]]; do
        local skill_path
        skill_path=$(jq -r ".skills[$i]" "$plugin_json" 2>/dev/null)
        # Resolve relative paths from plugin dir
        local resolved="${PLUGIN_DIR}/${skill_path#./}"
        if [[ ! -f "$resolved" ]]; then
            doctor_add "skill-missing-$(basename "$skill_path")" "skills" "fail" \
                "Skill file missing: $(basename "$skill_path")" "$resolved"
            ((skill_missing++)) || true
        fi
        ((i++)) || true
    done
    if [[ $skill_missing -eq 0 ]]; then
        doctor_add "skills-all" "skills" "pass" \
            "All $skill_total skill files present" ""
    fi

    # Verify command files exist
    local cmd_total cmd_missing=0
    cmd_total=$(jq '.commands | length' "$plugin_json" 2>/dev/null || echo "0")
    i=0
    while [[ $i -lt $cmd_total ]]; do
        local cmd_path
        cmd_path=$(jq -r ".commands[$i]" "$plugin_json" 2>/dev/null)
        local resolved="${PLUGIN_DIR}/${cmd_path#./}"
        if [[ ! -f "$resolved" ]]; then
            doctor_add "cmd-missing-$(basename "$cmd_path")" "skills" "fail" \
                "Command file missing: $(basename "$cmd_path")" "$resolved"
            ((cmd_missing++)) || true
        fi
        ((i++)) || true
    done
    if [[ $cmd_missing -eq 0 ]]; then
        doctor_add "commands-all" "skills" "pass" \
            "All $cmd_total command files present" ""
    fi

    # v8.52: Warn about skill deadlock risk on CC < v2.1.73 (50 skill files)
    if [[ "$SUPPORTS_SKILL_DEADLOCK_FIX" != "true" ]]; then
        doctor_add "skill-deadlock-risk" "skills" "warn" \
            "CC < v2.1.73: git pull with $skill_total skills may cause deadlock/freeze" \
            "Upgrade to Claude Code v2.1.73+ to fix the deadlock with large .claude/skills/ directories"
    fi

    # v8.52: Surface modelOverrides setting if CC v2.1.73+ and user may benefit
    if [[ "$SUPPORTS_MODEL_OVERRIDES" == "true" ]] && [[ "$OCTOPUS_BACKEND" != "api" ]]; then
        local settings_file="${HOME}/.claude/settings.json"
        local has_overrides="false"
        if [[ -f "$settings_file" ]] && command -v jq &>/dev/null; then
            has_overrides=$(jq 'has("modelOverrides")' "$settings_file" 2>/dev/null || echo "false")
        fi
        if [[ "$has_overrides" == "true" ]]; then
            doctor_add "model-overrides-active" "skills" "pass" \
                "CC modelOverrides configured (${OCTOPUS_BACKEND} backend)" \
                "Custom model IDs will be used by CC's model picker"
        else
            doctor_add "model-overrides-tip" "skills" "info" \
                "CC v2.1.73 modelOverrides available for ${OCTOPUS_BACKEND} inference profiles" \
                "Set modelOverrides in ~/.claude/settings.json to map model names to Bedrock ARNs/Vertex endpoints"
        fi
    fi

    # v8.56: Surface /context command for context optimization tips
    if [[ "$SUPPORTS_CONTEXT_SUGGESTIONS" == "true" ]]; then
        doctor_add "context-suggestions" "skills" "info" \
            "CC v2.1.74 /context command available for context window diagnostics" \
            "Run /context in Claude Code to get actionable optimization tips for context-heavy sessions"
    fi

    # v8.56: Surface autoMemoryDirectory setting if CC v2.1.74+
    if [[ "$SUPPORTS_AUTO_MEMORY_DIR" == "true" ]]; then
        local settings_file="${HOME}/.claude/settings.json"
        local has_memory_dir="false"
        if [[ -f "$settings_file" ]] && command -v jq &>/dev/null; then
            has_memory_dir=$(jq 'has("autoMemoryDirectory")' "$settings_file" 2>/dev/null || echo "false")
        fi
        if [[ "$has_memory_dir" == "true" ]]; then
            doctor_add "auto-memory-dir" "skills" "pass" \
                "CC autoMemoryDirectory configured (custom auto-memory path)" ""
        fi
    fi

    # v8.57: Surface /effort command availability
    if [[ "$SUPPORTS_EFFORT_COMMAND" == "true" ]]; then
        doctor_add "effort-command" "skills" "info" \
            "CC v2.1.76 /effort command available for mid-session effort adjustment" \
            "Use /effort in Claude Code to change model effort level (low/medium/high) during a session"
    fi

    # v8.57: Surface worktree.sparsePaths for large monorepo optimization
    if [[ "$SUPPORTS_WORKTREE_SPARSE_PATHS" == "true" ]]; then
        local settings_file="${HOME}/.claude/settings.json"
        local has_sparse="false"
        if [[ -f "$settings_file" ]] && command -v jq &>/dev/null; then
            has_sparse=$(jq 'has("worktree") and (.worktree | has("sparsePaths"))' "$settings_file" 2>/dev/null || echo "false")
        fi
        if [[ "$has_sparse" == "true" ]]; then
            doctor_add "worktree-sparse-paths" "skills" "pass" \
                "CC worktree.sparsePaths configured (sparse checkout for --worktree)" ""
        else
            doctor_add "worktree-sparse-paths-tip" "skills" "info" \
                "CC v2.1.76 worktree.sparsePaths available for large monorepo optimization" \
                "Set worktree.sparsePaths in settings to check out only specific directories in --worktree mode"
        fi
    fi

    # v8.57: Surface MCP elicitation + PostCompact hook availability
    if [[ "$SUPPORTS_MCP_ELICITATION" == "true" ]]; then
        doctor_add "mcp-elicitation" "skills" "info" \
            "CC v2.1.76 MCP elicitation available (MCP servers can request structured user input)" \
            "MCP servers can now prompt for structured input mid-task via interactive dialogs"
    fi

    # v8.57: Warn about --plugin-dir behavioral change (one path per flag in v2.1.76+)
    if [[ "$SUPPORTS_PLUGIN_DIR_OVERRIDE" == "true" ]] && version_compare "$CLAUDE_CODE_VERSION" "2.1.76" ">="; then
        doctor_add "plugin-dir-one-path" "skills" "info" \
            "CC v2.1.76 --plugin-dir accepts one path per flag (use repeated flags for multiple)" \
            "If using multiple plugin dirs, change --plugin-dir 'a b' to --plugin-dir a --plugin-dir b"
    fi

    # v9.5: CC v2.1.77+ doctor tips
    if [[ "$SUPPORTS_PLUGIN_VALIDATE_FRONTMATTER" == "true" ]]; then
        doctor_add "plugin-validate" "skills" "info" \
            "CC v2.1.77 claude plugin validate checks frontmatter + hooks.json schema" \
            "Run 'claude plugin validate .' to catch YAML parse errors and schema violations in skills, agents, and hooks"
    fi

    if [[ "$SUPPORTS_ALLOW_READ_SANDBOX" == "true" ]]; then
        doctor_add "allow-read-sandbox" "skills" "info" \
            "CC v2.1.77 allowRead sandbox setting available" \
            "Use allowRead in sandbox settings to re-allow read access within denyRead regions"
    fi

    if [[ "$SUPPORTS_BRANCH_COMMAND" == "true" ]]; then
        doctor_add "branch-command" "skills" "info" \
            "CC v2.1.77 /fork renamed to /branch" \
            "Use /branch to create conversation branches (the /fork alias still works)"
    fi

    if [[ "$SUPPORTS_AGENT_NO_RESUME_PARAM" == "true" ]]; then
        doctor_add "sendmessage-resume" "skills" "pass" \
            "CC v2.1.77 agent resume uses SendMessage (Agent resume param removed)" \
            "Octopus resume commands use SendMessage for agent continuation automatically"
    fi

    if [[ "$SUPPORTS_BG_BASH_5GB_KILL" == "true" ]]; then
        doctor_add "bg-bash-5gb" "skills" "info" \
            "CC v2.1.77 background bash processes killed at 5GB output" \
            "Long-running background Bash tasks producing >5GB will be terminated. Agent tool dispatches are unaffected."
    fi

    # v9.5: Wired medium flags as doctor tips (previously banner-only or dead)
    if [[ "$SUPPORTS_COPY_INDEX" == "true" ]]; then
        doctor_add "copy-index" "skills" "info" \
            "CC v2.1.77 /copy N copies the Nth-latest response" \
            "Use /copy 3 to copy the third-most-recent assistant response to clipboard"
    fi

    if [[ "$SUPPORTS_COMPOUND_BASH_PERMISSION_FIX" == "true" ]]; then
        doctor_add "compound-bash-fix" "skills" "info" \
            "CC v2.1.77 compound bash always-allow applies per sub-command" \
            "Each sub-command in a compound bash expression is checked individually against always-allow rules"
    fi

    if [[ "$SUPPORTS_RESUME_TRUNCATION_FIX" == "true" ]]; then
        doctor_add "resume-truncation-fix" "skills" "info" \
            "CC v2.1.77 --resume no longer truncates history" \
            "Long conversations resumed with --resume now preserve full history instead of truncating"
    fi

    if [[ "$SUPPORTS_PRETOOLUSE_DENY_PRIORITY" == "true" ]]; then
        doctor_add "pretooluse-deny-priority" "skills" "info" \
            "CC v2.1.77 PreToolUse deny rules always take priority" \
            "Enterprise deny rules in PreToolUse hooks now override user allow and skill allowed-tools"
    fi

    if [[ "$SUPPORTS_SENDMESSAGE_AUTO_RESUME" == "true" ]]; then
        doctor_add "sendmessage-auto-resume" "skills" "info" \
            "CC v2.1.77 SendMessage auto-resumes stopped agents" \
            "Stopped agents are automatically resumed when you send them a message via SendMessage"
    fi

    if [[ "$SUPPORTS_PARALLEL_TOOL_RESILIENCE" == "true" ]]; then
        doctor_add "parallel-tool-resilience" "skills" "info" \
            "CC v2.1.72 parallel tool failures handled gracefully" \
            "A failed Read/WebFetch/Glob no longer cancels sibling parallel tool calls"
    fi

    if [[ "$SUPPORTS_BG_PROCESS_CLEANUP" == "true" ]]; then
        doctor_add "bg-process-cleanup" "skills" "info" \
            "CC v2.1.73 background bash auto-cleaned from subagents" \
            "Background bash processes spawned by subagents are automatically cleaned up on agent exit"
    fi

    # ── v9.19.0: CC v2.1.87-92 doctor tips ──────────────────────────────────────

    if [[ "$SUPPORTS_POST_COMPACT_HOOK" == "true" ]]; then
        doctor_add "post-compact-hook" "skills" "pass" \
            "CC v2.1.76 PostCompact hook active — workflow context recovers after compaction" \
            "Pre-compact state is re-injected automatically via PostCompact hook"
    fi

    if [[ "$SUPPORTS_BARE_FLAG" == "true" ]]; then
        doctor_add "bare-flag" "skills" "pass" \
            "CC v2.1.87 --bare flag active — subprocess synthesis runs faster" \
            "Octopus uses --bare for claude -p subprocess calls to skip hooks/LSP loading"
    fi

    if [[ "$SUPPORTS_MODEL_CAP_ENV_VARS" == "true" ]]; then
        doctor_add "model-cap-env-vars" "skills" "info" \
            "CC v2.1.87 ANTHROPIC_DEFAULT_*_MODEL_SUPPORTS env vars available" \
            "3rd-party provider capabilities are detected automatically for routing decisions"
    fi

    if [[ "$SUPPORTS_CONSOLE_AUTH" == "true" ]]; then
        doctor_add "console-auth" "skills" "info" \
            "CC v2.1.87 --console auth available (Anthropic Console API billing)" \
            "Use 'claude --console' to authenticate via the Anthropic Console for API-billed usage"
    fi

    if [[ "$SUPPORTS_PLUGIN_EXECUTABLES" == "true" ]]; then
        doctor_add "plugin-executables" "skills" "pass" \
            "CC v2.1.91 plugin executables active — 'octopus' available as bare command" \
            "Run 'octopus doctor' or 'octopus version' directly from the terminal"
    fi

    if [[ "$SUPPORTS_MCP_RESULT_SIZE" == "true" ]]; then
        doctor_add "mcp-result-size" "skills" "info" \
            "CC v2.1.91 MCP result size override available (up to 500K chars)" \
            "MCP tools can use _meta[\"anthropic/maxResultSizeChars\"] for larger results"
    fi

    if [[ "$SUPPORTS_MARKETPLACE_OFFLINE" == "true" ]]; then
        doctor_add "marketplace-offline" "skills" "info" \
            "CC v2.1.90 marketplace offline mode available" \
            "Set CLAUDE_CODE_PLUGIN_KEEP_MARKETPLACE_ON_FAILURE=1 for graceful degradation on flaky networks"
    fi

    if [[ "$SUPPORTS_DISABLE_SKILL_SHELL" == "true" ]]; then
        doctor_add "disable-skill-shell" "skills" "info" \
            "CC v2.1.91 disableSkillShellExecution setting available" \
            "When enabled, skills cannot invoke shell commands — orchestrate.sh workflows require this to be false"
    fi

    if [[ "$SUPPORTS_RATE_LIMIT_STATUSLINE" == "true" ]]; then
        doctor_add "rate-limit-hud-fallback" "skills" "pass" \
            "CC v2.1.80 rate_limits field used as HUD fallback" \
            "Octopus HUD uses CC-provided rate limits when OAuth API is unavailable"
    fi

    if [[ "$SUPPORTS_MANAGED_SETTINGS_D" == "true" ]]; then
        local _settings_fragment="${HOME}/.claude/managed-settings.d/octopus-defaults.json"
        if [[ -f "$_settings_fragment" ]]; then
            doctor_add "managed-settings-fragment" "skills" "pass" \
                "CC v2.1.83 managed-settings.d/ fragment installed" \
                "octopus-defaults.json active in ~/.claude/managed-settings.d/ (git instructions off, auto-memory dir set)"
        else
            doctor_add "managed-settings-fragment" "skills" "info" \
                "CC v2.1.83 managed-settings.d/ fragment not yet installed" \
                "Restart session to deploy octopus-defaults.json to ~/.claude/managed-settings.d/"
        fi
    fi

    if [[ "$SUPPORTS_ELICITATION_HOOKS" == "true" ]]; then
        doctor_add "elicitation-hooks" "skills" "pass" \
            "CC v2.1.76 Elicitation/ElicitationResult hooks active" \
            "MCP servers can request structured user input mid-task; events logged to ~/.claude-octopus/logs/elicitation.log"
    fi

    if [[ "$SUPPORTS_SESSION_ID_HEADER" == "true" ]]; then
        doctor_add "session-id-header" "skills" "info" \
            "CC v2.1.89 X-Claude-Code-Session-Id header available" \
            "Proxy servers can aggregate requests by session ID for telemetry and routing"
    fi

    if [[ "$SUPPORTS_DEEP_LINK_5K" == "true" ]]; then
        doctor_add "deep-link-5k" "skills" "info" \
            "CC v2.1.88 deep links expanded to 5,000 chars" \
            "claude-cli://open?q= links can carry longer prompts with scroll-to-review"
    fi

    if [[ "$SUPPORTS_WORKTREE_HTTP_HOOKS" == "true" ]]; then
        doctor_add "worktree-http-hooks" "skills" "info" \
            "CC v2.1.87 WorktreeCreate supports type:http hooks" \
            "Worktree hooks can POST JSON to a URL instead of running a shell command"
    fi

    if [[ "$SUPPORTS_MULTILINE_DEEP_LINKS" == "true" ]]; then
        doctor_add "multiline-deep-links" "skills" "info" \
            "CC v2.1.91 multi-line deep link prompts available" \
            "claude-cli://open?q= supports encoded newlines (%0A) for multi-step prompts"
    fi

    # v9.20.0: Output compression
    if [[ -x "${CLAUDE_PLUGIN_ROOT:-}/hooks/output-compressor.sh" ]]; then
        if [[ "${OCTOPUS_COMPRESS_ENABLED:-true}" == "true" ]]; then
            doctor_add "output-compressor" "skills" "pass" \
                "Output compressor active — large tool results get compressed summaries" \
                "PostToolUse hook injects summaries for JSON arrays, logs, HTML, verbose output >3K chars. Use 'octo-compress stats' to see savings."
        else
            doctor_add "output-compressor" "skills" "info" \
                "Output compressor installed but disabled" \
                "Set OCTOPUS_COMPRESS_ENABLED=true to enable automatic compression of large tool outputs"
        fi
    fi

    if [[ -x "${CLAUDE_PLUGIN_ROOT:-}/bin/octo-compress" ]]; then
        doctor_add "octo-compress-cli" "skills" "pass" \
            "octo-compress CLI available — pipe verbose output for token savings" \
            "Usage: npm install 2>&1 | octo-compress — compresses JSON arrays, logs, HTML, verbose text"
    fi
}

# --- Category 8: Conflicts ---
doctor_check_conflicts() {
    local claude_plugins_dir="$HOME/.claude/plugins"
    local conflicts=0

    if [[ -d "$claude_plugins_dir/oh-my-claude-code" ]]; then
        doctor_add "conflict-oh-my-claude" "conflicts" "warn" \
            "oh-my-claude-code detected" "Has own cost-aware routing — may overlap with Octopus provider selection"
        ((conflicts++)) || true
    fi

    if [[ -d "$claude_plugins_dir/claude-flow" ]]; then
        doctor_add "conflict-claude-flow" "conflicts" "warn" \
            "claude-flow detected" "May spawn competing subagents"
        ((conflicts++)) || true
    fi

    if [[ -d "$claude_plugins_dir/agents" ]] || [[ -d "$claude_plugins_dir/wshobson-agents" ]]; then
        doctor_add "conflict-wshobson-agents" "conflicts" "warn" \
            "wshobson/agents detected" "Large context consumption"
        ((conflicts++)) || true
    fi

    if [[ $conflicts -eq 0 ]]; then
        doctor_add "no-conflicts" "conflicts" "pass" \
            "No conflicting plugins detected" ""
    fi

    # v8.57: Detect companion plugins (complementary, not conflicting)
    local claude_mem_dir=""
    for dir in "$HOME"/.claude/plugins/cache/thedotmack/claude-mem/*/; do
        [[ -d "$dir" ]] && claude_mem_dir="$dir" && break
    done
    if [[ -n "$claude_mem_dir" ]]; then
        local mem_version
        mem_version=$(basename "${claude_mem_dir%/}" 2>/dev/null || echo "unknown")
        doctor_add "companion-claude-mem" "conflicts" "pass" \
            "claude-mem v${mem_version} detected (companion — persistent cross-session memory)" \
            "Octopus workflows can use claude-mem MCP tools (search, timeline, get_observations) for past session context"
    fi
}

# --- Category 9: Smoke Test (v8.19.0 - Issue #34) ---
doctor_check_smoke() {
    # Cache status
    if [[ -f "$SMOKE_TEST_CACHE_FILE" ]]; then
        local cache_time cache_key cache_status current_time cache_age
        cache_time=$(head -1 "$SMOKE_TEST_CACHE_FILE" 2>/dev/null || echo "0")
        cache_key=$(sed -n '2p' "$SMOKE_TEST_CACHE_FILE" 2>/dev/null || echo "")
        cache_status=$(sed -n '3p' "$SMOKE_TEST_CACHE_FILE" 2>/dev/null || echo "1")
        current_time=$(date +%s)
        cache_age=$((current_time - cache_time))

        if [[ $cache_age -lt $PREFLIGHT_CACHE_TTL && "$cache_key" == "$(smoke_test_cache_key)" ]]; then
            if [[ "$cache_status" == "0" ]]; then
                doctor_add "smoke-cache" "smoke" "pass" \
                    "Smoke test cache valid (passed ${cache_age}s ago)" "$cache_key"
            else
                doctor_add "smoke-cache" "smoke" "fail" \
                    "Smoke test cache valid (FAILED ${cache_age}s ago)" "$cache_key"
            fi
        else
            doctor_add "smoke-cache" "smoke" "warn" \
                "Smoke test cache expired or stale" "Will re-test on next run"
        fi
    else
        doctor_add "smoke-cache" "smoke" "warn" \
            "No smoke test cache found" "Will test on next run"
    fi

    # Current model config
    local codex_model gemini_model
    codex_model=$(get_agent_model "codex" 2>/dev/null || echo "not configured")
    gemini_model=$(get_agent_model "gemini" 2>/dev/null || echo "not configured")

    doctor_add "smoke-codex-model" "smoke" "pass" \
        "Codex model: ${codex_model}" "OCTOPUS_CODEX_MODEL=${OCTOPUS_CODEX_MODEL:-<default>}"
    doctor_add "smoke-gemini-model" "smoke" "pass" \
        "Gemini model: ${gemini_model}" "OCTOPUS_GEMINI_MODEL=${OCTOPUS_GEMINI_MODEL:-<default>}"

    # Skip flag
    if [[ "$SKIP_SMOKE_TEST" == "true" ]]; then
        doctor_add "smoke-skip" "smoke" "warn" \
            "Smoke test DISABLED (--skip-smoke-test or OCTOPUS_SKIP_SMOKE_TEST=true)" \
            "Not recommended — provider failures will only be caught at runtime"
    fi
}

# --- Category 10: Agents (v8.26.0 - Changelog Integration) ---
doctor_check_agents() {
    local config_file="${PLUGIN_DIR}/agents/config.yaml"
    if [[ ! -f "$config_file" ]]; then
        doctor_add "agents-config" "agents" "fail" \
            "agents/config.yaml not found" "Expected at: $config_file"
        return
    fi

    local agent_count
    agent_count=$(grep -c '^\s\{2\}[a-z]' "$config_file" 2>/dev/null || echo "0")
    doctor_add "agents-count" "agents" "pass" \
        "${agent_count} agent definitions found" ""

    local worktree_agents
    worktree_agents=$(grep -c 'isolation: worktree' "$config_file" 2>/dev/null || echo "0")
    doctor_add "agents-worktree" "agents" "pass" \
        "${worktree_agents} agents with worktree isolation" ""

    if [[ "$SUPPORTS_AGENTS_CLI" == "true" ]]; then
        local cli_output
        cli_output=$(claude agents 2>/dev/null | head -20 || echo "")
        if [[ -n "$cli_output" ]]; then
            local cli_count
            cli_count=$(echo "$cli_output" | grep -c "^" || echo "0")
            doctor_add "agents-cli" "agents" "pass" \
                "Claude agents CLI: ${cli_count} agents registered" ""
        else
            doctor_add "agents-cli" "agents" "warn" \
                "Claude agents CLI returned no data" "Run 'claude agents' manually"
        fi
    else
        doctor_add "agents-cli" "agents" "info" \
            "Claude agents CLI not available (requires v2.1.50+)" ""
    fi

    if [[ -n "${CLAUDE_CODE_VERSION:-}" ]]; then
        if version_compare "$CLAUDE_CODE_VERSION" "2.1.50" "<" 2>/dev/null; then
            doctor_add "agents-version" "agents" "warn" \
                "Claude Code < v2.1.50 — multi-agent memory leaks possible" \
                "Recommend upgrading for worktree isolation and embrace stability"
        else
            doctor_add "agents-version" "agents" "pass" \
                "Claude Code v${CLAUDE_CODE_VERSION} — multi-agent stable" ""
        fi
    fi
}

# --- Category 11: Failure Recurrence (v8.34.0 — Idea Meritocracy E46/E47) ---
# Parses .octo/decisions.jsonl for repeated failure patterns
doctor_check_recurrence() {
    local jsonl_file="${WORKSPACE_DIR}/.octo/decisions.jsonl"
    if [[ ! -f "$jsonl_file" ]]; then
        doctor_add "recurrence-data" "recurrence" "info" \
            "No decision history yet — recurrence detection starts after first workflow" ""
        return
    fi

    local total_decisions
    total_decisions=$(wc -l < "$jsonl_file" 2>/dev/null | tr -d ' ')
    if [[ "$total_decisions" -eq 0 ]]; then
        doctor_add "recurrence-data" "recurrence" "info" \
            "Decision log empty — no patterns to detect" ""
        return
    fi

    doctor_add "recurrence-data" "recurrence" "pass" \
        "${total_decisions} decisions logged" ""

    # Count quality-gate failures (the most actionable pattern)
    local qg_failures
    qg_failures=$(grep -c '"type":"quality-gate"' "$jsonl_file" 2>/dev/null || true)
    qg_failures="${qg_failures:-0}"
    if [[ "$qg_failures" -ge 3 ]]; then
        doctor_add "recurrence-qg" "recurrence" "warn" \
            "${qg_failures} quality gate failures recorded" \
            "Recurring failures may indicate a systemic issue. Run /octo:issues to review."
    elif [[ "$qg_failures" -gt 0 ]]; then
        doctor_add "recurrence-qg" "recurrence" "info" \
            "${qg_failures} quality gate failure(s) recorded" ""
    fi

    # Check for failures in the last 48 hours
    local cutoff_epoch
    if [[ "$OCTOPUS_PLATFORM" == "Darwin" ]]; then
        cutoff_epoch=$(date -v-2d +%s 2>/dev/null || echo "0")
    else
        cutoff_epoch=$(date -d "2 days ago" +%s 2>/dev/null || echo "0")
    fi

    if [[ "$cutoff_epoch" -gt 0 ]]; then
        local recent_failures=0
        while IFS= read -r line; do
            local ts
            ts=$(echo "$line" | grep -o '"timestamp":"[^"]*"' | sed 's/"timestamp":"//;s/"//' || true)
            if [[ -n "$ts" ]]; then
                local line_epoch
                if [[ "$OCTOPUS_PLATFORM" == "Darwin" ]]; then
                    line_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null || echo "0")
                else
                    line_epoch=$(date -d "$ts" +%s 2>/dev/null || echo "0")
                fi
                if [[ "$line_epoch" -ge "$cutoff_epoch" ]]; then
                    ((recent_failures++))
                fi
            fi
        done < <(grep '"type":"quality-gate"' "$jsonl_file" 2>/dev/null || true)

        if [[ "$recent_failures" -ge 3 ]]; then
            doctor_add "recurrence-recent" "recurrence" "warn" \
                "${recent_failures} quality gate failures in last 48h — pattern detected" \
                "Multiple recent failures suggest an active systemic issue"
        elif [[ "$recent_failures" -gt 0 ]]; then
            doctor_add "recurrence-recent" "recurrence" "pass" \
                "${recent_failures} quality gate failure(s) in last 48h" ""
        fi
    fi

    # Check source concentration (same source failing repeatedly)
    local top_source
    top_source=$(grep '"type":"quality-gate"' "$jsonl_file" 2>/dev/null | \
        grep -o '"source":"[^"]*"' | sort | uniq -c | sort -rn | head -1 || true)
    if [[ -n "$top_source" ]]; then
        local count source_name
        count=$(echo "$top_source" | awk '{print $1}')
        source_name=$(echo "$top_source" | grep -o '"source":"[^"]*"' | sed 's/"source":"//;s/"//')
        if [[ "$count" -ge 3 ]]; then
            doctor_add "recurrence-source" "recurrence" "warn" \
                "Recurring failure source: ${source_name} (${count}x)" \
                "Same workflow failing repeatedly — investigate root cause"
        fi
    fi
}

# --- Output: Human-readable ---
doctor_output_human() {
    local verbose="${1:-false}"
    local total=${#DOCTOR_RESULTS_NAME[@]}
    local pass_count=0 warn_count=0 fail_count=0
    local current_cat=""

    for ((i=0; i<total; i++)); do
        local status="${DOCTOR_RESULTS_STATUS[$i]}"
        case "$status" in
            pass) ((pass_count++)) ;;
            warn) ((warn_count++)) ;;
            fail) ((fail_count++)) ;;
        esac
    done

    for ((i=0; i<total; i++)); do
        local name="${DOCTOR_RESULTS_NAME[$i]}"
        local cat="${DOCTOR_RESULTS_CAT[$i]}"
        local status="${DOCTOR_RESULTS_STATUS[$i]}"
        local msg="${DOCTOR_RESULTS_MSG[$i]}"
        local detail="${DOCTOR_RESULTS_DETAIL[$i]}"

        # Skip passing checks in non-verbose mode
        if [[ "$verbose" != "true" && "$status" == "pass" ]]; then
            continue
        fi

        # Print category header on change
        if [[ "$cat" != "$current_cat" ]]; then
            current_cat="$cat"
            echo -e "\n${BOLD}${BLUE}[$cat]${NC}"
        fi

        # Status icon
        local icon
        case "$status" in
            pass) icon="${GREEN}✓${NC}" ;;
            warn) icon="${YELLOW}⚠${NC}" ;;
            fail) icon="${RED}✗${NC}" ;;
        esac

        echo -e "  ${icon} ${msg}"
        if [[ -n "$detail" && "$verbose" == "true" ]]; then
            echo -e "    ${DIM}${detail}${NC}"
        fi
    done

    # All-clear message in non-verbose mode
    if [[ "$verbose" != "true" && $warn_count -eq 0 && $fail_count -eq 0 ]]; then
        echo -e "\n  ${GREEN}✓${NC} All checks passed. Use ${DIM}--verbose${NC} to see details."
    fi

    # Summary line
    echo ""
    local summary="${BOLD}Summary:${NC} ${GREEN}${pass_count} passed${NC}"
    [[ $warn_count -gt 0 ]] && summary+=", ${YELLOW}${warn_count} warning(s)${NC}"
    [[ $fail_count -gt 0 ]] && summary+=", ${RED}${fail_count} failure(s)${NC}"
    echo -e "$summary"

    if [[ $fail_count -gt 0 ]]; then
        return 1
    fi
    return 0
}

# --- Output: JSON ---
doctor_output_json() {
    local total=${#DOCTOR_RESULTS_NAME[@]}
    local json="["
    for ((i=0; i<total; i++)); do
        [[ $i -gt 0 ]] && json+=","
        # Escape strings for JSON safety
        local name="${DOCTOR_RESULTS_NAME[$i]}"
        local cat="${DOCTOR_RESULTS_CAT[$i]}"
        local status="${DOCTOR_RESULTS_STATUS[$i]}"
        local msg="${DOCTOR_RESULTS_MSG[$i]//\"/\\\"}"
        local detail="${DOCTOR_RESULTS_DETAIL[$i]//\"/\\\"}"
        json+="{\"name\":\"$name\",\"category\":\"$cat\",\"status\":\"$status\",\"message\":\"$msg\",\"detail\":\"$detail\"}"
    done
    json+="]"
    echo "$json"
}

# --- Main Doctor Runner ---
do_doctor() {
    local category_filter=""
    local verbose=false
    local json_output=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verbose|-v) verbose=true ;;
            --json) json_output=true ;;
            -*) ;; # ignore unknown flags
            *) [[ -z "$category_filter" ]] && category_filter="$1" ;;
        esac
        shift
    done

    # Reset results
    DOCTOR_RESULTS_NAME=()
    DOCTOR_RESULTS_CAT=()
    DOCTOR_RESULTS_STATUS=()
    DOCTOR_RESULTS_MSG=()
    DOCTOR_RESULTS_DETAIL=()

    # Run checks (filtered if category specified)
    local categories=(providers auth config state smoke hooks scheduler skills conflicts agents recurrence)
    for cat in "${categories[@]}"; do
        if [[ -z "$category_filter" || "$category_filter" == "$cat" ]]; then
            "doctor_check_${cat}"
        fi
    done

    # Output
    if [[ "$json_output" == "true" ]]; then
        doctor_output_json
    else
        echo -e "${MAGENTA}═══════════════════════════════════════════════════════════${NC}"
        echo -e "${MAGENTA}  Claude Octopus Doctor${NC}"
        echo -e "${MAGENTA}═══════════════════════════════════════════════════════════${NC}"
        doctor_output_human "$verbose"
    fi
}
