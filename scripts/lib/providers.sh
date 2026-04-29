#!/usr/bin/env bash
# Claude Octopus — Provider Detection & Version Checking
# ═══════════════════════════════════════════════════════════════════════════════
# Extracted from orchestrate.sh in v9.7.7 monolith decomposition.
# Contains: version_compare, detect_claude_code_version, detect_enterprise_backend,
#           detect_fast_mode, check_provider_health, check_all_providers
# Source-safe: no main execution block.
# ═══════════════════════════════════════════════════════════════════════════════

if ! declare -f _is_cursor_agent_binary >/dev/null 2>&1; then
    _providers_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${_providers_lib_dir}/cursor-agent.sh" 2>/dev/null || true
fi

# Version comparison utility
version_compare() {
    local version1="$1"
    local version2="$2"
    local operator="$3"

    # Split versions into components
    IFS='.' read -ra V1 <<< "$version1"
    IFS='.' read -ra V2 <<< "$version2"

    # Compare major.minor.patch
    for i in 0 1 2; do
        local v1_part="${V1[$i]:-0}"
        local v2_part="${V2[$i]:-0}"

        if (( v1_part > v2_part )); then
            [[ "$operator" == ">=" || "$operator" == ">" ]] && return 0
            return 1
        elif (( v1_part < v2_part )); then
            [[ "$operator" == "<=" || "$operator" == "<" ]] && return 0
            return 1
        fi
    done

    # Versions are equal
    [[ "$operator" == ">=" || "$operator" == "<=" || "$operator" == "==" ]] && return 0
    return 1
}

detect_claude_code_version() {
    # v9.16.0: Non-Claude hosts skip CC version detection entirely
    # Codex and Gemini have their own feature sets; CC version flags don't apply
    if [[ "$OCTOPUS_HOST" == "codex" || "$OCTOPUS_HOST" == "gemini" ]]; then
        CLAUDE_CODE_VERSION=""
        log "INFO" "${OCTOPUS_HOST} host detected — skipping Claude Code version detection"
        # Enable basic capabilities that work on any host with bash
        SUPPORTS_BASH_TOOL=true
        SUPPORTS_MCP=false  # MCP integration is host-specific
        return 0
    fi
    # v8.36.0: Support Factory AI Droid runtime alongside Claude Code
    if [[ "$OCTOPUS_HOST" == "factory" ]]; then
        if command -v droid &>/dev/null; then
            CLAUDE_CODE_VERSION=$(droid --version 2>/dev/null | grep -m1 -oE '[0-9]+\.[0-9]+\.[0-9]+')
            log "INFO" "Factory AI Droid detected (v${CLAUDE_CODE_VERSION:-unknown})"
        fi
        # Factory's plugin format is interop with Claude Code — enable all modern features
        # Factory supports the full plugin API (hooks, skills, commands, agents)
        if [[ -z "$CLAUDE_CODE_VERSION" ]]; then
            # Assume latest feature parity if version can't be detected
            CLAUDE_CODE_VERSION="2.1.69"
            log "INFO" "Factory AI host: assuming feature parity with Claude Code v2.1.69"
        fi
    elif ! command -v claude &>/dev/null; then
        # Check common install locations not on PATH in non-interactive shells
        local _claude_path=""
        for _try_path in "$HOME/.local/bin/claude" "/usr/local/bin/claude" "$HOME/.claude/bin/claude"; do
            if [[ -x "$_try_path" ]]; then
                _claude_path="$_try_path"
                break
            fi
        done
        if [[ -n "$_claude_path" ]]; then
            # Add directory to PATH for this session
            export PATH="$(dirname "$_claude_path"):$PATH"
            log "INFO" "Claude Code CLI found at $_claude_path (added to PATH)"
        else
            log "WARN" "Claude Code CLI not found, using fallback mode"
            return 1
        fi
    fi
    if command -v claude &>/dev/null; then
        # Get version from Claude CLI
        CLAUDE_CODE_VERSION=$(claude --version 2>/dev/null | grep -m1 -oE '[0-9]+\.[0-9]+\.[0-9]+')
    fi

    if [[ -z "$CLAUDE_CODE_VERSION" ]]; then
        log "WARN" "Could not detect host platform version, using fallback mode"
        return 1
    fi

    # Check for v2.1.12+ features (bash wildcards, basic task management)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.12" ">="; then
        SUPPORTS_TASK_MANAGEMENT=true
        SUPPORTS_BASH_WILDCARDS=true
    fi

    # Check for v2.1.16+ features (fork context, agent field)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.16" ">="; then
        SUPPORTS_FORK_CONTEXT=true
        SUPPORTS_AGENT_FIELD=true
    fi

    # Check for v2.1.30+ features (native token counts in Task tool results)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.30" ">="; then
        SUPPORTS_NATIVE_TASK_METRICS=true
    fi

    # Check for v2.1.32+ features (agent teams, auto memory)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.32" ">="; then
        SUPPORTS_AGENT_TEAMS=true
        SUPPORTS_AUTO_MEMORY=true
    fi

    # Check for v2.1.33+ features (persistent memory, hook events, agent type routing, agent memory, statusline API)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.33" ">="; then
        SUPPORTS_PERSISTENT_MEMORY=true
        SUPPORTS_HOOK_EVENTS=true
        SUPPORTS_AGENT_TYPE_ROUTING=true
        SUPPORTS_AGENT_MEMORY=true
        SUPPORTS_STATUSLINE_API=true
    fi

    # Check for v2.1.34+ features (stable agent teams, sandbox security, agent continuation)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.34" ">="; then
        SUPPORTS_STABLE_AGENT_TEAMS=true
        SUPPORTS_CONTINUATION=true
    fi

    # Check for v2.1.36+ features (fast mode for Opus 4.6)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.36" ">="; then
        SUPPORTS_FAST_OPUS=true
    fi

    # Check for v2.1.38+ features (Agent Teams Bridge - unified task ledger)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.38" ">="; then
        SUPPORTS_AGENT_TEAMS_BRIDGE=true
    fi

    # Check for v2.1.41+ features (auth CLI, anchor mentions, OTel speed)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.41" ">="; then
        SUPPORTS_AUTH_CLI=true
        SUPPORTS_ANCHOR_MENTIONS=true
        SUPPORTS_OTEL_SPEED=true
    fi

    # Check for v2.1.42+ features (prompt cache optimization, fast startup, effort callout)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.42" ">="; then
        SUPPORTS_PROMPT_CACHE_OPT=true
        SUPPORTS_FAST_STARTUP=true
        SUPPORTS_EFFORT_CALLOUT=true
    fi

    # Check for v2.1.43+ features (enterprise backend fixes, structured outputs)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.43" ">="; then
        SUPPORTS_ENTERPRISE_FIX=true
        SUPPORTS_STRUCTURED_OUTPUTS=true
    fi

    # Check for v2.1.44+ features (stable auth refresh)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.44" ">="; then
        SUPPORTS_STABLE_AUTH=true
    fi

    # Check for v2.1.45+ features (Sonnet 4.6, per-project plugins, immediate plugin install)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.45" ">="; then
        SUPPORTS_SONNET_46=true
        SUPPORTS_PER_PROJECT_PLUGINS=true
        SUPPORTS_IMMEDIATE_PLUGIN_INSTALL=true
    fi

    # Check for v2.1.47+ features (stable bg agents, hook last_message, agent model field, deferred hooks, parallel file safety)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.47" ">="; then
        SUPPORTS_STABLE_BG_AGENTS=true
        SUPPORTS_HOOK_LAST_MESSAGE=true
        SUPPORTS_AGENT_MODEL_FIELD=true
        SUPPORTS_DEFERRED_SESSION_HOOKS=true
        SUPPORTS_PARALLEL_FILE_SAFETY=true
    fi

    # Check for v2.1.49+ features (ConfigChange hook, plugin scope fix, SDK model caps)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.49" ">="; then
        SUPPORTS_CONFIG_CHANGE_HOOK=true
        SUPPORTS_PLUGIN_SCOPE_AUTODETECT=true
        SUPPORTS_SDK_MODEL_CAPS=true
    fi

    # Check for v2.1.50+ features (worktree isolation, worktree hooks, agents CLI, fast opus 1M)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.50" ">="; then
        SUPPORTS_WORKTREE_ISOLATION=true
        SUPPORTS_WORKTREE_HOOKS=true
        SUPPORTS_AGENTS_CLI=true
        SUPPORTS_FAST_OPUS_1M=true
    fi

    # Check for v2.1.51+ features (remote control, npm registries, fast bash, disk persist, account env vars, managed settings)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.51" ">="; then
        SUPPORTS_REMOTE_CONTROL=true
        SUPPORTS_NPM_PLUGIN_REGISTRIES=true
        SUPPORTS_FAST_BASH=true
        SUPPORTS_AGGRESSIVE_DISK_PERSIST=true
        SUPPORTS_ACCOUNT_ENV_VARS=true
        SUPPORTS_MANAGED_SETTINGS_PLATFORM=true
    fi

    # Check for v2.1.59+ features (native auto-memory, agent memory GC, smart bash prefixes)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.59" ">="; then
        SUPPORTS_NATIVE_AUTO_MEMORY=true
        SUPPORTS_AGENT_MEMORY_GC=true
        SUPPORTS_SMART_BASH_PREFIXES=true
    fi

    # Check for v2.1.63+ features (HTTP hooks, shared worktree config, memory fixes, batch, MCP opt-out)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.63" ">="; then
        SUPPORTS_HTTP_HOOKS=true
        SUPPORTS_WORKTREE_SHARED_CONFIG=true
        export SUPPORTS_WORKTREE_SHARED_CONFIG  # Exported for worktree-setup.sh hook
        SUPPORTS_MEMORY_LEAK_FIXES=true
        SUPPORTS_BATCH_COMMAND=true
        SUPPORTS_MCP_OPT_OUT=true
        SUPPORTS_SKILL_CACHE_RESET=true
    fi

    # Check for v2.1.66+ features (reduced error logging)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.66" ">="; then
        SUPPORTS_REDUCED_ERROR_LOGGING=true
    fi

    # Check for v2.1.68+ features (Opus medium effort default, ultrathink, Opus 4.0/4.1 removed)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.68" ">="; then
        SUPPORTS_OPUS_MEDIUM_EFFORT=true
        SUPPORTS_ULTRATHINK=true
        SUPPORTS_OPUS_40_REMOVED=true
    fi

    # Check for v2.1.69+ features (CLAUDE_SKILL_DIR, InstructionsLoaded hook, agent fields in hooks, etc.)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.69" ">="; then
        SUPPORTS_SKILL_DIR_VAR=true
        SUPPORTS_INSTRUCTIONS_LOADED_HOOK=true
        SUPPORTS_HOOK_AGENT_FIELDS=true
        SUPPORTS_STATUSLINE_WORKTREE=true
        SUPPORTS_RELOAD_PLUGINS=true
        SUPPORTS_DISABLE_GIT_INSTRUCTIONS=true
        SUPPORTS_GIT_SUBDIR_PLUGINS=true
    fi

    # Check for v2.1.72+ features (Agent model override, effort redesign, cron disable env, parallel tool resilience)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.72" ">="; then
        SUPPORTS_AGENT_MODEL_OVERRIDE=true
        SUPPORTS_EFFORT_REDESIGN=true
        SUPPORTS_DISABLE_CRON_ENV=true
        SUPPORTS_PARALLEL_TOOL_RESILIENCE=true
    fi

    # Check for v2.1.73+ features (modelOverrides, subagent model fix, bg cleanup, skill deadlock fix)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.73" ">="; then
        SUPPORTS_MODEL_OVERRIDES=true
        SUPPORTS_SUBAGENT_MODEL_FIX=true
        SUPPORTS_BG_PROCESS_CLEANUP=true
        SUPPORTS_SKILL_DEADLOCK_FIX=true
    fi

    # Check for v2.1.74+ features (autoMemoryDirectory, full model IDs, /context, plugin-dir override)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.74" ">="; then
        SUPPORTS_AUTO_MEMORY_DIR=true
        SUPPORTS_FULL_MODEL_IDS=true
        SUPPORTS_CONTEXT_SUGGESTIONS=true
        SUPPORTS_PLUGIN_DIR_OVERRIDE=true
    fi

    if version_compare "$CLAUDE_CODE_VERSION" "2.1.76" ">="; then
        SUPPORTS_MCP_ELICITATION=true
        SUPPORTS_WORKTREE_SPARSE_PATHS=true
        SUPPORTS_EFFORT_COMMAND=true
        SUPPORTS_BG_PARTIAL_RESULTS=true
        SUPPORTS_POST_COMPACT_HOOK=true
        SUPPORTS_ELICITATION_HOOKS=true
    fi

    # Check for v2.1.77+ features (allowRead sandbox, /copy N, compound bash fix, resume truncation fix,
    #   PreToolUse deny priority, SendMessage auto-resume, Agent resume param removed, plugin validate,
    #   /fork→/branch rename, bg bash 5GB kill)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.77" ">="; then
        SUPPORTS_ALLOW_READ_SANDBOX=true
        SUPPORTS_COPY_INDEX=true
        SUPPORTS_COMPOUND_BASH_PERMISSION_FIX=true
        SUPPORTS_RESUME_TRUNCATION_FIX=true
        SUPPORTS_PRETOOLUSE_DENY_PRIORITY=true
        SUPPORTS_SENDMESSAGE_AUTO_RESUME=true
        SUPPORTS_AGENT_NO_RESUME_PARAM=true
        SUPPORTS_PLUGIN_VALIDATE_FRONTMATTER=true
        SUPPORTS_BRANCH_COMMAND=true
        SUPPORTS_BG_BASH_5GB_KILL=true
    fi

    # Check for v2.1.78+ features (StopFailure hook, CLAUDE_PLUGIN_DATA, agent effort/maxTurns/disallowedTools)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.78" ">="; then
        SUPPORTS_STOP_FAILURE_HOOK=true
        SUPPORTS_PLUGIN_DATA_DIR=true
        SUPPORTS_AGENT_EFFORT=true
    fi

    # Check for v2.1.80+ features (effort frontmatter, rate_limits statusline field)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.80" ">="; then
        SUPPORTS_SKILL_EFFORT=true
        SUPPORTS_RATE_LIMIT_STATUSLINE=true
    fi

    # Check for v2.1.83+ features (CwdChanged/FileChanged hooks, managed-settings.d/, env scrub, initialPrompt)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.83" ">="; then
        SUPPORTS_CWD_CHANGED_HOOK=true
        SUPPORTS_FILE_CHANGED_HOOK=true
        SUPPORTS_MANAGED_SETTINGS_D=true
        SUPPORTS_ENV_SCRUB=true
        SUPPORTS_AGENT_INITIAL_PROMPT=true
        SUPPORTS_TASKOUTPUT_DEPRECATED=true
    fi

    # Check for v2.1.84+ features (TaskCreated hook, paths: frontmatter, userConfig)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.84" ">="; then
        SUPPORTS_TASK_CREATED_HOOK=true
        SUPPORTS_SKILL_PATHS=true
        SUPPORTS_USER_CONFIG=true
    fi

    # Check for v2.1.85+ features (conditional if on hooks, PreToolUse answering AskUserQuestion)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.85" ">="; then
        SUPPORTS_HOOK_CONDITIONAL_IF=true
        SUPPORTS_HOOK_ASK_ANSWER=true
    fi

    # Check for v2.1.86+ features (skill description 250 char cap)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.86" ">="; then
        SUPPORTS_SKILL_DESC_250=true
    fi

    # Check for v2.1.87+ features (--bare flag, model capability env vars, console auth, worktree HTTP hooks)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.87" ">="; then
        SUPPORTS_BARE_FLAG=true
        SUPPORTS_MODEL_CAP_ENV_VARS=true
        SUPPORTS_CONSOLE_AUTH=true
        SUPPORTS_WORKTREE_HTTP_HOOKS=true
    fi

    # Check for v2.1.88+ features (deep link expansion to 5K chars)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.88" ">="; then
        SUPPORTS_DEEP_LINK_5K=true
    fi

    # Check for v2.1.89+ features (session ID header, PermissionDenied hook, defer permission, NO_FLICKER)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.89" ">="; then
        SUPPORTS_SESSION_ID_HEADER=true
        SUPPORTS_PERMISSION_DENIED_HOOK=true
        SUPPORTS_DEFER_PERMISSION=true
        SUPPORTS_NO_FLICKER=true
    fi

    # Check for v2.1.90+ features (marketplace offline mode)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.90" ">="; then
        SUPPORTS_MARKETPLACE_OFFLINE=true
    fi

    # Check for v2.1.91+ features (plugin executables, MCP result size, disable skill shell, multiline deep links)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.91" ">="; then
        SUPPORTS_PLUGIN_EXECUTABLES=true
        SUPPORTS_MCP_RESULT_SIZE=true
        SUPPORTS_DISABLE_SKILL_SHELL=true
        SUPPORTS_MULTILINE_DEEP_LINKS=true
    fi

    # Check for v2.1.94+ features (keep-coding-instructions, session title hook, skill name invocation, default effort high)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.94" ">="; then
        SUPPORTS_KEEP_CODING_INSTRUCTIONS=true
        SUPPORTS_SESSION_TITLE_HOOK=true
        SUPPORTS_SKILL_NAME_INVOCATION=true
        SUPPORTS_DEFAULT_EFFORT_HIGH=true
    fi

    # Check for v2.1.97+ features (statusline refreshInterval)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.97" ">="; then
        SUPPORTS_STATUSLINE_REFRESH_INTERVAL=true
    fi

    # Check for v2.1.98+ features (exclude dynamic prompt, Perforce mode, Monitor tool, TRACEPARENT)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.98" ">="; then
        SUPPORTS_EXCLUDE_DYNAMIC_PROMPT=true
        SUPPORTS_PERFORCE_MODE=true
        SUPPORTS_MONITOR_TOOL=true
        SUPPORTS_TRACEPARENT=true
    fi

    # Check for v2.1.101+ features (settings resilience, OS CA certs, auto cloud env)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.101" ">="; then
        SUPPORTS_SETTINGS_RESILIENCE=true
        SUPPORTS_OS_CA_CERTS=true
        SUPPORTS_AUTO_CLOUD_ENV=true
    fi

    # v9.23: Claude Code v2.1.105+ (blockable PreCompact, plugin monitors, worktree path reuse, MCP truncate recipes)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.105" ">="; then
        SUPPORTS_PRECOMPACT_BLOCKING=true
        SUPPORTS_PLUGIN_MONITORS=true
        SUPPORTS_ENTER_WORKTREE_PATH=true
        SUPPORTS_MCP_TRUNCATE_RECIPES=true
    fi

    # v9.23: Claude Code v2.1.108+ (1-hour prompt cache, session recap, built-in slash via Skill)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.108" ">="; then
        SUPPORTS_PROMPT_CACHE_1H=true
        SUPPORTS_SESSION_RECAP=true
        SUPPORTS_BUILTIN_SLASH_VIA_SKILL=true
    fi

    # v9.23: Claude Code v2.1.110+ (TaskCreated hook, PermissionRequest re-check, PreToolUse ctx on fail, TUI, OTel raw bodies, PowerShell)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.110" ">="; then
        SUPPORTS_TASKCREATED_HOOK=true
        SUPPORTS_PERMISSIONREQ_RECHECK=true
        SUPPORTS_PRETOOL_CTX_ON_FAIL=true
        SUPPORTS_TUI_FULLSCREEN=true
        SUPPORTS_OTEL_RAW_BODIES=true
        SUPPORTS_POWERSHELL_TOOL=true
    fi

    # v9.23: Claude Code v2.1.111+ (Opus 4.7 + xhigh effort, auto mode GA, /ultrareview)
    if version_compare "$CLAUDE_CODE_VERSION" "2.1.111" ">="; then
        SUPPORTS_XHIGH_EFFORT=true
        SUPPORTS_OPUS_4_7=true
        SUPPORTS_AUTO_MODE_GA=true
        SUPPORTS_ULTRAREVIEW=true
    fi

    log "INFO" "Claude Code v$CLAUDE_CODE_VERSION detected"
    log "INFO" "Task Management: $SUPPORTS_TASK_MANAGEMENT | Fork Context: $SUPPORTS_FORK_CONTEXT | Agent Teams: $SUPPORTS_AGENT_TEAMS"
    log "INFO" "Persistent Memory: $SUPPORTS_PERSISTENT_MEMORY | Hook Events: $SUPPORTS_HOOK_EVENTS | Agent Type Routing: $SUPPORTS_AGENT_TYPE_ROUTING"
    log "INFO" "Stable Agent Teams: $SUPPORTS_STABLE_AGENT_TEAMS | Agent Memory: $SUPPORTS_AGENT_MEMORY | Fast Opus: $SUPPORTS_FAST_OPUS"
    log "INFO" "Native Task Metrics: $SUPPORTS_NATIVE_TASK_METRICS | Agent Teams Bridge: $SUPPORTS_AGENT_TEAMS_BRIDGE"
    log "INFO" "Auth CLI: $SUPPORTS_AUTH_CLI | Anchor Mentions: $SUPPORTS_ANCHOR_MENTIONS | OTel Speed: $SUPPORTS_OTEL_SPEED"
    log "INFO" "Prompt Cache Opt: $SUPPORTS_PROMPT_CACHE_OPT | Enterprise Fix: $SUPPORTS_ENTERPRISE_FIX | Stable Auth: $SUPPORTS_STABLE_AUTH"
    log "INFO" "Sonnet 4.6: $SUPPORTS_SONNET_46 | Per-Project Plugins: $SUPPORTS_PER_PROJECT_PLUGINS"
    log "INFO" "Stable BG Agents: $SUPPORTS_STABLE_BG_AGENTS | Hook Last Message: $SUPPORTS_HOOK_LAST_MESSAGE | Agent Model Field: $SUPPORTS_AGENT_MODEL_FIELD"
    log "INFO" "ConfigChange Hook: $SUPPORTS_CONFIG_CHANGE_HOOK | Plugin Scope Auto: $SUPPORTS_PLUGIN_SCOPE_AUTODETECT | SDK Model Caps: $SUPPORTS_SDK_MODEL_CAPS"
    log "INFO" "Worktree Isolation: $SUPPORTS_WORKTREE_ISOLATION | Worktree Hooks: $SUPPORTS_WORKTREE_HOOKS | Agents CLI: $SUPPORTS_AGENTS_CLI | Fast Opus 1M: $SUPPORTS_FAST_OPUS_1M"
    log "INFO" "Remote Control: $SUPPORTS_REMOTE_CONTROL | NPM Registries: $SUPPORTS_NPM_PLUGIN_REGISTRIES | Fast Bash: $SUPPORTS_FAST_BASH | Disk Persist: $SUPPORTS_AGGRESSIVE_DISK_PERSIST"
    log "INFO" "Native Auto-Memory: $SUPPORTS_NATIVE_AUTO_MEMORY | Agent Memory GC: $SUPPORTS_AGENT_MEMORY_GC | Smart Bash Prefixes: $SUPPORTS_SMART_BASH_PREFIXES"
    log "INFO" "HTTP Hooks: $SUPPORTS_HTTP_HOOKS | Shared WT Config: $SUPPORTS_WORKTREE_SHARED_CONFIG | Batch: $SUPPORTS_BATCH_COMMAND | MCP Opt-Out: $SUPPORTS_MCP_OPT_OUT"
    log "INFO" "Continuation: $SUPPORTS_CONTINUATION | Skill Cache Reset: $SUPPORTS_SKILL_CACHE_RESET"
    log "INFO" "Opus Medium Effort: $SUPPORTS_OPUS_MEDIUM_EFFORT | Ultrathink: $SUPPORTS_ULTRATHINK | Opus 4.0 Removed: $SUPPORTS_OPUS_40_REMOVED"
    log "INFO" "Skill Dir Var: $SUPPORTS_SKILL_DIR_VAR | Instructions Hook: $SUPPORTS_INSTRUCTIONS_LOADED_HOOK | Hook Agent Fields: $SUPPORTS_HOOK_AGENT_FIELDS"
    log "INFO" "Statusline Worktree: $SUPPORTS_STATUSLINE_WORKTREE | Reload Plugins: $SUPPORTS_RELOAD_PLUGINS | Disable Git Instructions: $SUPPORTS_DISABLE_GIT_INSTRUCTIONS"
    log "INFO" "Agent Model Override: $SUPPORTS_AGENT_MODEL_OVERRIDE | Effort Redesign: $SUPPORTS_EFFORT_REDESIGN | Disable Cron Env: $SUPPORTS_DISABLE_CRON_ENV"
    log "INFO" "Model Overrides: $SUPPORTS_MODEL_OVERRIDES | Subagent Model Fix: $SUPPORTS_SUBAGENT_MODEL_FIX | Parallel Tool Resilience: $SUPPORTS_PARALLEL_TOOL_RESILIENCE"
    log "INFO" "BG Process Cleanup: $SUPPORTS_BG_PROCESS_CLEANUP | Skill Deadlock Fix: $SUPPORTS_SKILL_DEADLOCK_FIX"
    log "INFO" "Auto Memory Dir: $SUPPORTS_AUTO_MEMORY_DIR | Full Model IDs: $SUPPORTS_FULL_MODEL_IDS | Context Suggestions: $SUPPORTS_CONTEXT_SUGGESTIONS"
    log "INFO" "Plugin Dir Override: $SUPPORTS_PLUGIN_DIR_OVERRIDE | MCP Elicitation: $SUPPORTS_MCP_ELICITATION | Worktree Sparse Paths: $SUPPORTS_WORKTREE_SPARSE_PATHS"
    log "INFO" "Effort Command: $SUPPORTS_EFFORT_COMMAND | BG Partial Results: $SUPPORTS_BG_PARTIAL_RESULTS"
    log "INFO" "Allow Read Sandbox: $SUPPORTS_ALLOW_READ_SANDBOX | SendMessage Auto Resume: $SUPPORTS_SENDMESSAGE_AUTO_RESUME | Agent No Resume Param: $SUPPORTS_AGENT_NO_RESUME_PARAM"
    log "INFO" "Plugin Validate Frontmatter: $SUPPORTS_PLUGIN_VALIDATE_FRONTMATTER | Branch Command: $SUPPORTS_BRANCH_COMMAND | BG Bash 5GB Kill: $SUPPORTS_BG_BASH_5GB_KILL"
    log "INFO" "StopFailure Hook: $SUPPORTS_STOP_FAILURE_HOOK | Plugin Data Dir: $SUPPORTS_PLUGIN_DATA_DIR | Agent Effort: $SUPPORTS_AGENT_EFFORT"
    log "INFO" "CwdChanged Hook: $SUPPORTS_CWD_CHANGED_HOOK | FileChanged Hook: $SUPPORTS_FILE_CHANGED_HOOK | Managed Settings.d: $SUPPORTS_MANAGED_SETTINGS_D"
    log "INFO" "Env Scrub: $SUPPORTS_ENV_SCRUB | Agent Initial Prompt: $SUPPORTS_AGENT_INITIAL_PROMPT"
    log "INFO" "PostCompact Hook: $SUPPORTS_POST_COMPACT_HOOK | Elicitation Hooks: $SUPPORTS_ELICITATION_HOOKS"
    log "INFO" "Bare Flag: $SUPPORTS_BARE_FLAG | Model Cap Env Vars: $SUPPORTS_MODEL_CAP_ENV_VARS | Console Auth: $SUPPORTS_CONSOLE_AUTH"
    log "INFO" "Worktree HTTP Hooks: $SUPPORTS_WORKTREE_HTTP_HOOKS | Session ID Header: $SUPPORTS_SESSION_ID_HEADER | Deep Link 5K: $SUPPORTS_DEEP_LINK_5K"
    log "INFO" "Marketplace Offline: $SUPPORTS_MARKETPLACE_OFFLINE | Plugin Executables: $SUPPORTS_PLUGIN_EXECUTABLES | MCP Result Size: $SUPPORTS_MCP_RESULT_SIZE"
    log "INFO" "Disable Skill Shell: $SUPPORTS_DISABLE_SKILL_SHELL | Multiline Deep Links: $SUPPORTS_MULTILINE_DEEP_LINKS"
    log "INFO" "PermissionDenied Hook: $SUPPORTS_PERMISSION_DENIED_HOOK | Defer Permission: $SUPPORTS_DEFER_PERMISSION | NO_FLICKER: $SUPPORTS_NO_FLICKER"
    log "INFO" "Keep Coding Instructions: $SUPPORTS_KEEP_CODING_INSTRUCTIONS | Session Title Hook: $SUPPORTS_SESSION_TITLE_HOOK | Skill Name Invocation: $SUPPORTS_SKILL_NAME_INVOCATION"
    log "INFO" "Default Effort High: $SUPPORTS_DEFAULT_EFFORT_HIGH | Statusline Refresh Interval: $SUPPORTS_STATUSLINE_REFRESH_INTERVAL"
    log "INFO" "Exclude Dynamic Prompt: $SUPPORTS_EXCLUDE_DYNAMIC_PROMPT | Perforce Mode: $SUPPORTS_PERFORCE_MODE | Monitor Tool: $SUPPORTS_MONITOR_TOOL | Traceparent: $SUPPORTS_TRACEPARENT"
    log "INFO" "Settings Resilience: $SUPPORTS_SETTINGS_RESILIENCE | OS CA Certs: $SUPPORTS_OS_CA_CERTS | Auto Cloud Env: $SUPPORTS_AUTO_CLOUD_ENV"

    # v8.29.0: Context window control
    OCTOPUS_CONTEXT_WINDOW="${OCTOPUS_CONTEXT_WINDOW:-auto}"
    if [[ "$OCTOPUS_CONTEXT_WINDOW" == "standard" && "$SUPPORTS_FAST_OPUS_1M" == "true" ]]; then
        export CLAUDE_CODE_DISABLE_1M_CONTEXT=1
        log "INFO" "1M context window disabled by OCTOPUS_CONTEXT_WINDOW=standard"
    elif [[ "$OCTOPUS_CONTEXT_WINDOW" == "auto" ]]; then
        # auto: let Claude Code decide based on model and mode
        unset CLAUDE_CODE_DISABLE_1M_CONTEXT 2>/dev/null || true
    fi

    # v8.34.0: Disable built-in git instructions to save ~2K tokens (v2.1.69+)
    if [[ "$SUPPORTS_DISABLE_GIT_INSTRUCTIONS" == "true" ]]; then
        export CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS=1
        log "INFO" "Built-in git instructions disabled (SUPPORTS_DISABLE_GIT_INSTRUCTIONS)"
    fi

    # v9.19.0: --bare flag for subprocess synthesis (CC v2.1.87+)
    # Skips hooks/LSP/plugin sync when running claude -p subprocesses, reducing latency.
    # CC v2.1.114 regression (#288): --bare breaks subprocess auth on some installs,
    # causing "Not logged in" exits with exit code 0. Runtime-probe before enabling,
    # and honour OCTOPUS_DISABLE_BARE=1 opt-out.
    _BARE_OPT=""
    if [[ "$SUPPORTS_BARE_FLAG" == "true" && "${OCTOPUS_DISABLE_BARE:-0}" != "1" ]]; then
        # Quick auth probe: pipe a trivial prompt and check for login nag
        local _bare_probe
        _bare_probe=$(echo "x" | claude --bare --print --model claude-haiku-4-5-20251001 2>/dev/null | head -1 || true)
        if [[ "$_bare_probe" == *"Not logged in"* || "$_bare_probe" == *"Please run /login"* ]]; then
            log "WARN" "--bare flag breaks subprocess auth on this install (issue #288) — disabled. Set OCTOPUS_DISABLE_BARE=1 to suppress this probe."
        else
            _BARE_OPT=" --bare"
            log "INFO" "Subprocess synthesis uses --bare flag for faster claude -p calls"
        fi
    fi
    export _BARE_OPT

    # v9.19.0: Surface 3p provider capabilities via env vars (CC v2.1.87+)
    if [[ "$SUPPORTS_MODEL_CAP_ENV_VARS" == "true" ]]; then
        # Read any ANTHROPIC_DEFAULT_*_MODEL_SUPPORTS env vars for 3p routing
        local _cap_count=0
        for _cap_var in $(env 2>/dev/null | grep '^ANTHROPIC_DEFAULT_.*_MODEL_SUPPORTS=' | cut -d= -f1); do
            ((_cap_count++)) || true
        done
        if [[ $_cap_count -gt 0 ]]; then
            log "INFO" "3P model capabilities: ${_cap_count} ANTHROPIC_DEFAULT_*_MODEL_SUPPORTS env vars detected"
        fi
    fi

    # v8.5: Detect /fast toggle after version detection
    detect_fast_mode
    log "INFO" "User /fast mode: $USER_FAST_MODE"

    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# ENTERPRISE BACKEND DETECTION (v8.16 - Claude Code v2.1.42+)
# Detects whether Claude Code is running on an enterprise backend
# (AWS Bedrock, Google Vertex AI, or Anthropic Foundry)
# ═══════════════════════════════════════════════════════════════════════════════

detect_enterprise_backend() {
    # Bedrock: AWS credentials + region
    if [[ -n "${AWS_BEDROCK_REGION:-}" ]] || [[ -n "${AWS_REGION:-}" && -n "${AWS_ACCESS_KEY_ID:-}" ]]; then
        OCTOPUS_BACKEND="bedrock"
        OCTOPUS_AUTH_REFRESH_INTERVAL="${OCTOPUS_AUTH_REFRESH_INTERVAL:-150}"
        log "INFO" "Enterprise backend detected: AWS Bedrock (auth refresh: ${OCTOPUS_AUTH_REFRESH_INTERVAL}s)"
        return 0
    fi

    # Vertex: GCP project
    if [[ -n "${GOOGLE_CLOUD_PROJECT:-}" ]] || [[ -n "${VERTEX_PROJECT:-}" ]]; then
        OCTOPUS_BACKEND="vertex"
        log "INFO" "Enterprise backend detected: Google Vertex AI"
        return 0
    fi

    # Foundry: Anthropic enterprise
    if [[ -n "${ANTHROPIC_FOUNDRY_ORG:-}" ]] || [[ -n "${ANTHROPIC_FOUNDRY_BASE_URL:-}" ]]; then
        OCTOPUS_BACKEND="foundry"
        log "INFO" "Enterprise backend detected: Anthropic Foundry"
        return 0
    fi

    # Auth CLI detection (v2.1.41+): parse `claude auth status` output
    if [[ "$SUPPORTS_AUTH_CLI" == "true" ]]; then
        local auth_output
        auth_output=$(claude auth status 2>/dev/null || true)
        if [[ "$auth_output" == *"bedrock"* || "$auth_output" == *"Bedrock"* ]]; then
            OCTOPUS_BACKEND="bedrock"
            OCTOPUS_AUTH_REFRESH_INTERVAL="${OCTOPUS_AUTH_REFRESH_INTERVAL:-150}"
            log "INFO" "Enterprise backend detected via auth CLI: AWS Bedrock"
        elif [[ "$auth_output" == *"vertex"* || "$auth_output" == *"Vertex"* ]]; then
            OCTOPUS_BACKEND="vertex"
            log "INFO" "Enterprise backend detected via auth CLI: Google Vertex AI"
        elif [[ "$auth_output" == *"foundry"* || "$auth_output" == *"Foundry"* ]]; then
            OCTOPUS_BACKEND="foundry"
            log "INFO" "Enterprise backend detected via auth CLI: Anthropic Foundry"
        fi
    fi

    OCTOPUS_BACKEND="${OCTOPUS_BACKEND:-api}"
    log "DEBUG" "Backend: $OCTOPUS_BACKEND"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# /FAST TOGGLE DETECTION (v8.5 - Claude Code v2.1.36+)
# Detects whether user has enabled /fast mode in their Claude Code session
# ═══════════════════════════════════════════════════════════════════════════════
USER_FAST_MODE="false"

detect_fast_mode() {
    # Check 1: Explicit env var from Claude Code (if exposed)
    if [[ "${CLAUDE_CODE_FAST_MODE:-}" == "true" || "${CLAUDE_CODE_FAST_MODE:-}" == "1" ]]; then
        USER_FAST_MODE="true"
        log "INFO" "/fast mode detected via CLAUDE_CODE_FAST_MODE env var"
        return 0
    fi

    # Check 2: Check Claude Code settings.json for fast mode state
    local settings_file="${HOME}/.claude/settings.json"
    if [[ -f "$settings_file" ]] && command -v jq &>/dev/null; then
        local fast_setting
        fast_setting=$(jq -r '.preferences.fastMode // .fastMode // false' "$settings_file" 2>/dev/null) || fast_setting="false"
        if [[ "$fast_setting" == "true" ]]; then
            USER_FAST_MODE="true"
            log "INFO" "/fast mode detected via settings.json"
            return 0
        fi
    fi

    # Check 3: Check local project settings
    local local_settings="${HOME}/.claude/projects/$(pwd | tr '/' '-')/settings.json"
    if [[ -f "$local_settings" ]] && command -v jq &>/dev/null; then
        local fast_local
        fast_local=$(jq -r '.preferences.fastMode // .fastMode // false' "$local_settings" 2>/dev/null) || fast_local="false"
        if [[ "$fast_local" == "true" ]]; then
            USER_FAST_MODE="true"
            log "INFO" "/fast mode detected via project settings"
            return 0
        fi
    fi

    USER_FAST_MODE="false"
    return 0
}

# Check if a provider is healthy (CLI available + credentials present)
# Returns 0 if healthy, 1 if unhealthy. Prints diagnostic to stderr.
check_provider_health() {
    local provider="$1"
    local errors=0

    case "$provider" in
        codex)
            if ! command -v codex &>/dev/null; then
                echo "codex CLI not found in PATH" >&2
                return 1
            fi
            # Check for either OAuth or API key
            if [[ -z "${OPENAI_API_KEY:-}" ]]; then
                # Try resolving from profile/.env before failing
                resolve_provider_env "OPENAI_API_KEY" 2>/dev/null
            fi
            if [[ -z "${OPENAI_API_KEY:-}" ]]; then
                # Check if OAuth is configured via auth.json (codex auth status was removed in v0.114)
                if [[ ! -f "${HOME}/.codex/auth.json" ]]; then
                    echo "codex: no OPENAI_API_KEY and no ~/.codex/auth.json (run: codex auth)" >&2
                    return 1
                fi
            fi
            ;;
        gemini)
            if ! command -v gemini &>/dev/null; then
                echo "gemini CLI not found in PATH" >&2
                return 1
            fi
            # v9.2.1: Check OAuth creds first (Issue #177)
            if [[ -f "$HOME/.gemini/oauth_creds.json" ]]; then
                return 0
            fi
            # Try resolving env vars from profile/.env for non-interactive shells
            if [[ -z "${GEMINI_API_KEY:-}" ]]; then
                resolve_provider_env "GEMINI_API_KEY" 2>/dev/null
            fi
            if [[ -z "${GOOGLE_API_KEY:-}" ]] && [[ -z "${GEMINI_API_KEY:-}" ]]; then
                resolve_provider_env "GOOGLE_API_KEY" 2>/dev/null
            fi
            if [[ -z "${GEMINI_API_KEY:-}" ]] && [[ -z "${GOOGLE_API_KEY:-}" ]]; then
                # Gemini CLI may use gcloud auth
                if ! command -v gcloud &>/dev/null; then
                    echo "gemini: GEMINI_API_KEY not found in non-interactive shell. If your key is in ~/.bashrc, move it to ~/.profile or ~/.env instead (bashrc is skipped in non-interactive shells)" >&2
                    return 1
                fi
            fi
            ;;
        claude)
            if ! command -v claude &>/dev/null; then
                echo "claude CLI not found in PATH" >&2
                return 1
            fi
            ;;
        perplexity)
            if [[ -z "${PERPLEXITY_API_KEY:-}" ]]; then
                echo "perplexity: PERPLEXITY_API_KEY not set" >&2
                return 1
            fi
            ;;
        openrouter)
            if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
                echo "openrouter: OPENROUTER_API_KEY not set" >&2
                return 1
            fi
            ;;
        ollama)
            if ! command -v ollama &>/dev/null; then
                echo "ollama CLI not found in PATH" >&2
                return 1
            fi
            # Check server is running
            if ! curl -sf http://localhost:11434/api/tags &>/dev/null; then
                echo "ollama: server not running (run: ollama serve)" >&2
                return 1
            fi
            ;;
        copilot)
            if ! command -v copilot &>/dev/null; then
                echo "copilot CLI not found in PATH" >&2
                return 1
            fi
            # Check auth via the same precedence chain as copilot_is_available()
            if [[ -z "${COPILOT_GITHUB_TOKEN:-}" ]] && \
               [[ -z "${GH_TOKEN:-}" ]] && \
               [[ -z "${GITHUB_TOKEN:-}" ]] && \
               [[ ! -f "${HOME}/.copilot/config.json" ]]; then
                if ! command -v gh &>/dev/null || ! gh auth status &>/dev/null 2>&1; then
                    echo "copilot: not authenticated (run: copilot login)" >&2
                    return 1
                fi
            fi
            ;;
        qwen)
            if ! command -v qwen &>/dev/null; then
                echo "qwen CLI not found in PATH" >&2
                return 1
            fi
            # Check auth: OAuth creds or config in ~/.qwen/, or API key env var
            if [[ ! -f "${HOME}/.qwen/oauth_creds.json" ]] && \
               [[ ! -f "${HOME}/.qwen/config.json" ]] && \
               [[ -z "${QWEN_API_KEY:-}" ]]; then
                echo "qwen: not authenticated (run: qwen to trigger OAuth, or set QWEN_API_KEY)" >&2
                return 1
            fi
            ;;
        cursor-agent)
            if ! command -v agent &>/dev/null; then
                echo "cursor-agent: CLI not found in PATH" >&2
                return 1
            fi
            # Verify binary identity — `agent` is a generic name
            if ! declare -f _is_cursor_agent_binary >/dev/null 2>&1 || ! _is_cursor_agent_binary; then
                echo "cursor-agent: 'agent' binary is not Cursor Agent CLI" >&2
                return 1
            fi
            # Check auth: env var or Cursor session (authInfo in cli-config.json)
            if [[ -z "${CURSOR_API_KEY:-}" ]] && \
               ! grep -Eq '"authInfo"[[:space:]]*:[[:space:]]*\{' "${HOME}/.cursor/cli-config.json" 2>/dev/null; then
                echo "cursor-agent: not authenticated (run: agent login or set CURSOR_API_KEY)" >&2
                return 1
            fi
            ;;
    esac
    return 0
}

# Run health checks for all configured providers, return summary
# Usage: check_all_providers
check_all_providers() {
    local healthy=0 unhealthy=0
    local -a results=()

    for provider in codex gemini claude perplexity openrouter ollama copilot qwen cursor-agent; do
        local diag
        if diag=$(check_provider_health "$provider" 2>&1); then
            results+=("  ✓ $provider")
            ((healthy++))
        else
            results+=("  ✗ $provider: $diag")
            ((unhealthy++))
        fi
    done

    echo "Provider Health Check:"
    printf '%s\n' "${results[@]}"
    echo "  ($healthy healthy, $unhealthy unavailable)"
}

# ── Extracted from orchestrate.sh (optimization sweep) ──

# ═══════════════════════════════════════════════════════════════════════════════
# OPENROUTER INTEGRATION (v4.8)
# Universal fallback using OpenRouter API (400+ models)
# ═══════════════════════════════════════════════════════════════════════════════

# Select OpenRouter model based on task type
get_openrouter_model() {
    local task_type="$1"
    local complexity="${2:-2}"

    # Apply routing preference suffix
    local routing_suffix=""
    if [[ -n "$OPENROUTER_ROUTING_OVERRIDE" ]]; then
        routing_suffix="$OPENROUTER_ROUTING_OVERRIDE"
    elif [[ "$PROVIDER_OPENROUTER_ROUTING_PREF" != "default" ]]; then
        routing_suffix=":${PROVIDER_OPENROUTER_ROUTING_PREF}"
    fi

    case "$task_type" in
        coding|review)
            case "$complexity" in
                3) echo "anthropic/claude-opus-4-6${routing_suffix}" ;;   # v8.0: Opus for premium
                1) echo "anthropic/claude-haiku${routing_suffix}" ;;
                *) echo "anthropic/claude-sonnet-4${routing_suffix}" ;;
            esac
            ;;
        image)
            echo "google/gemini-2.0-flash${routing_suffix}"
            ;;
        research|design)
            echo "anthropic/claude-sonnet-4${routing_suffix}"
            ;;
        *)
            echo "anthropic/claude-sonnet-4${routing_suffix}"
            ;;
    esac
}

# Execute prompt via OpenRouter API
execute_openrouter() {
    local prompt="$1"
    local task_type="${2:-general}"
    local complexity="${3:-2}"

    if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
        log ERROR "OPENROUTER_API_KEY not set"
        return 1
    fi

    local model
    model=$(get_openrouter_model "$task_type" "$complexity")

    [[ "$VERBOSE" == "true" ]] && log DEBUG "OpenRouter request: model=$model" || true

    # Build JSON payload (properly escape all special characters)
    local escaped_prompt
    escaped_prompt=$(json_escape "$prompt")

    local payload
    payload=$(cat << EOF
{
  "model": "$model",
  "messages": [
    {"role": "user", "content": "$escaped_prompt"}
  ]
}
EOF
)

    local response
    response=$(curl -s -X POST "https://openrouter.ai/api/v1/chat/completions" \
        -H "Authorization: Bearer ${OPENROUTER_API_KEY}" \
        -H "Content-Type: application/json" \
        -H "Connection: keep-alive" \
        -H "HTTP-Referer: https://github.com/nyldn/claude-octopus" \
        -H "X-Title: Claude Octopus" \
        -d "$payload")

    # Extract content from response (fast regex extraction)
    local content=""
    if json_extract "$response" "content"; then
        content="$REPLY"
    fi

    if [[ -z "$content" ]]; then
        # Check for error
        if [[ "$response" =~ \"error\":\{([^\}]*)\} ]]; then
            log ERROR "OpenRouter error: ${BASH_REMATCH[1]}"
            return 1
        fi
        log WARN "Empty response from OpenRouter"
        echo "$response"  # Return raw response for debugging
    else
        # Unescape the content
        echo "$content" | sed 's/\\n/\n/g; s/\\t/\t/g; s/\\"/"/g'
    fi
}

# ── detect_providers: multi-CLI + auth detection (moved from orchestrate.sh v9.22.1) ──
detect_providers() {
    local result=""

    # Detect Codex CLI
    if command -v codex &>/dev/null; then
        local codex_auth="none"
        if [[ -f "$HOME/.codex/auth.json" ]]; then
            codex_auth="oauth"
        elif [[ -n "${OPENAI_API_KEY:-}" ]]; then
            codex_auth="api-key"
        fi
        result="${result}codex:${codex_auth} "
    fi

    # Detect Gemini CLI
    if command -v gemini &>/dev/null; then
        local gemini_auth="none"
        if [[ -f "$HOME/.gemini/oauth_creds.json" ]]; then
            gemini_auth="oauth"
        elif [[ -n "${GEMINI_API_KEY:-}" ]]; then
            gemini_auth="api-key"
        fi
        result="${result}gemini:${gemini_auth} "
    fi

    # Detect Claude CLI (always available in Claude Code context)
    if command -v claude &>/dev/null; then
        local claude_auth="oauth"
        # v8.8: Use claude auth status for reliable auth verification
        if [[ "$SUPPORTS_AUTH_CLI" == "true" ]]; then
            if claude auth status &>/dev/null; then
                claude_auth="verified"
            else
                claude_auth="oauth"  # Fallback: assume oauth in Claude Code context
                log "DEBUG" "claude auth status returned non-zero, assuming oauth context"
            fi
        fi
        result="${result}claude:${claude_auth} "
    fi

    # Detect OpenRouter (API key only)
    if [[ -n "${OPENROUTER_API_KEY:-}" ]]; then
        result="${result}openrouter:api-key "
    fi

    # Detect Perplexity (API key only)
    if [[ -n "${PERPLEXITY_API_KEY:-}" ]]; then
        result="${result}perplexity:api-key "
    fi

    # Detect Ollama (CLI + server)
    if command -v ollama &>/dev/null; then
        if curl -sf http://localhost:11434/api/tags &>/dev/null; then
            result="${result}ollama:running "
        else
            result="${result}ollama:installed "
        fi
    fi

    # Detect Copilot CLI (v9.9.0)
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
        result="${result}copilot:${copilot_auth} "
    fi

    # Detect Qwen CLI (v9.10.0 — free tier)
    if command -v qwen &>/dev/null; then
        local qwen_auth="none"
        if [[ -f "${HOME}/.qwen/oauth_creds.json" ]]; then
            qwen_auth="oauth"
        elif [[ -f "${HOME}/.qwen/config.json" ]]; then
            qwen_auth="config"
        elif [[ -n "${QWEN_API_KEY:-}" ]]; then
            qwen_auth="api-key"
        fi
        result="${result}qwen:${qwen_auth} "
    fi

    # Detect Cursor Agent CLI (Grok via Cursor subscription)
    if declare -f _is_cursor_agent_binary >/dev/null 2>&1 && _is_cursor_agent_binary; then
        local cursor_auth="none"
        if [[ -n "${CURSOR_API_KEY:-}" ]]; then
            cursor_auth="env:CURSOR_API_KEY"
        elif grep -Eq '"authInfo"[[:space:]]*:[[:space:]]*\{' "${HOME}/.cursor/cli-config.json" 2>/dev/null; then
            cursor_auth="cursor-session"
        fi
        result="${result}cursor-agent:${cursor_auth} "
    fi

    # Detect OpenCode CLI (v9.11.0 — multi-provider router)
    if command -v opencode &>/dev/null; then
        local opencode_auth="none"
        if [[ -f "${HOME}/.local/share/opencode/auth.json" ]]; then
            # Verify auth is actually valid via auth list (with timeout to prevent hang)
            if timeout 3 opencode auth list &>/dev/null 2>&1; then
                opencode_auth="multi"
            else
                opencode_auth="expired"
            fi
        fi
        result="${result}opencode:${opencode_auth} "
    fi

    # Fail gracefully with helpful message if no providers found
    if [[ -z "$result" ]]; then
        log WARN "No AI providers detected. Install at least one:"
        log WARN "  - Codex: npm i -g @openai/codex"
        log WARN "  - Gemini: npm i -g @google/gemini-cli"
        log WARN "  - Claude: Available in Claude Code context"
        log WARN "  - OpenRouter: Set OPENROUTER_API_KEY environment variable"
        log WARN "  - Copilot: brew install copilot-cli (zero additional cost)"
        log WARN "  - Ollama: brew install ollama (free local LLM)"
        log WARN "  - Qwen: npm i -g @qwen-code/qwen-code (free tier)"
        log WARN "  - OpenCode: npm i -g opencode (multi-provider router)"
        echo "none:unavailable"
        return 1
    fi

    echo "$result" | xargs  # Trim whitespace
}
