#!/usr/bin/env bash
# Claude Octopus - Multi-Agent Orchestrator
# Coordinates multiple AI agents (Codex CLI, Gemini CLI) for parallel task execution
# https://github.com/nyldn/claude-octopus

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# Self-heal: ensure the stable symlink exists for LLM Bash tool access.
# The SessionStart hook normally creates this, but if doctor (or any command)
# is invoked before the hook fires, the symlink may be missing. (fixes #318)
if [[ ! -e "${HOME}/.claude-octopus/plugin" ]]; then
    mkdir -p "${HOME}/.claude-octopus"
    ln -sfn "$PLUGIN_DIR" "${HOME}/.claude-octopus/plugin"
fi

# Cache platform detection — avoids repeated subprocess spawns (v8.33.0)
OCTOPUS_PLATFORM="$(uname)"

# v8.36.0: Host runtime detection — Claude Code vs Factory AI Droid vs Codex vs Gemini
# Factory's plugin interop resolves ${CLAUDE_PLUGIN_ROOT} automatically,
# but we detect the host for version checking and env var fallbacks.
# v9.16.0: Extended for Codex CLI and Gemini CLI host detection (Direction A)
if [[ -n "${DROID_PLUGIN_ROOT:-}" ]]; then
    OCTOPUS_HOST="factory"
    # Factory provides DROID_PLUGIN_ROOT; ensure CLAUDE_PLUGIN_ROOT is also set
    export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$DROID_PLUGIN_ROOT}"
elif [[ -n "${CODEX_HOME:-}" || -n "${CODEX_SANDBOX:-}" || -n "${CODEX_PLUGIN_ROOT:-}" ]]; then
    OCTOPUS_HOST="codex"  # HOST:codex — Codex CLI is the host runtime
elif [[ -n "${GEMINI_HOME:-}" || -n "${GEMINI_PLUGIN_ROOT:-}" ]]; then
    OCTOPUS_HOST="gemini"  # HOST:gemini — Gemini CLI is the host runtime
elif [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
    OCTOPUS_HOST="claude"
else
    OCTOPUS_HOST="standalone"
fi

# Keep debug flag defined even when nounset is enabled by sourced scripts.
OCTOPUS_DEBUG="${OCTOPUS_DEBUG:-false}"

# Workspace location - uses home directory for global installation
PROJECT_ROOT="${PWD}"

# Source state manager utilities
source "${SCRIPT_DIR}/state-manager.sh"

# Source metrics tracker (v7.25.0)
source "${SCRIPT_DIR}/metrics-tracker.sh"

# Source provider router (v8.7.0)
source "${SCRIPT_DIR}/provider-router.sh"

# Source agent teams bridge (v8.7.0)
source "${SCRIPT_DIR}/agent-teams-bridge.sh"

# Source Wave 1 extractions (v9.3.0 decomposition)
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/utils.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/similarity.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/models.sh" 2>/dev/null || true

# Source intelligence library (v8.20.0)
source "${SCRIPT_DIR}/lib/intelligence.sh" 2>/dev/null || true

# Source persona packs library (v8.21.0)
source "${SCRIPT_DIR}/lib/personas.sh" 2>/dev/null || true

# Source routing library (v8.21.0)
source "${SCRIPT_DIR}/lib/routing.sh" 2>/dev/null || true

# Security utilities: anti-injection, secure tempfiles, output guards
source "${SCRIPT_DIR}/lib/secure.sh" 2>/dev/null || true

# Provider detection & version checking (v9.7.7 extraction)
# Strict source (no silencing) for libs critical to core workflows — surfaces syntax errors
source "${SCRIPT_DIR}/lib/providers.sh"
source "${SCRIPT_DIR}/lib/preflight.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/dispatch.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/progressive.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/review.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/workflows.sh"
source "${SCRIPT_DIR}/lib/doctor.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/agent-sync.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/persona-loader.sh" 2>/dev/null || true

# Error tracking & UX progress (v9.7.x extraction)
source "${SCRIPT_DIR}/lib/error-tracking.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/factory.sh" 2>/dev/null || true

# Heartbeat monitoring & timeout functions (v9.7.x extraction)
source "${SCRIPT_DIR}/lib/heartbeat.sh" 2>/dev/null || true

# Research workflow functions (empathize_research, synthesize_research)
source "${SCRIPT_DIR}/lib/research.sh" 2>/dev/null || true

# Authentication helpers (v9.7.x extraction)
source "${SCRIPT_DIR}/lib/auth.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/model-resolver.sh"

# Agent lifecycle & management (v9.7.5 extraction)
source "${SCRIPT_DIR}/lib/agents.sh" 2>/dev/null || true

# Sentinel & strategy workflow functions (v9.7.x extraction)
source "${SCRIPT_DIR}/lib/sentinel.sh" 2>/dev/null || true

# Agent spawning (extracted from orchestrate.sh)
source "${SCRIPT_DIR}/lib/spawn.sh" 2>/dev/null || true

# Testing & validation functions (validate_tangle_results, squeeze_test)
source "${SCRIPT_DIR}/lib/testing.sh" 2>/dev/null || true

# Context detection & memory/skill context building (v9.7.x extraction)
source "${SCRIPT_DIR}/lib/context.sh" 2>/dev/null || true

# Perplexity & OpenRouter API execution (v9.7.5 extraction)
source "${SCRIPT_DIR}/lib/perplexity.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/copilot.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/qwen.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/cursor-agent.sh"

# Cost tracking & usage reporting (v9.7.5 extraction)
source "${SCRIPT_DIR}/lib/cost.sh" 2>/dev/null || true

# Usage help & shell completion functions (v9.7.x extraction)
source "${SCRIPT_DIR}/lib/usage-help.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/smoke.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/config-display.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/yaml-workflow.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/quality.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/agent-utils.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/memory.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/session.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/semantic-cache.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/interactive.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/parallel.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/factory-spec.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/validation.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/embrace.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/heuristics.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/provider-routing.sh" 2>/dev/null || true

# ═══════════════════════════════════════════════════════════════════════════════
# SECURITY: Path validation for workspace directory
# Prevents path traversal attacks and restricts to safe locations
# ═══════════════════════════════════════════════════════════════════════════════

# Apply workspace path — prefer CLAUDE_PLUGIN_DATA (CC v2.1.78+), then user override, then default
if [[ -n "${CLAUDE_PLUGIN_DATA:-}" ]]; then
    WORKSPACE_DIR="${CLAUDE_PLUGIN_DATA}"
elif [[ -n "${CLAUDE_OCTOPUS_WORKSPACE:-}" ]]; then
    WORKSPACE_DIR=$(validate_workspace_path "$CLAUDE_OCTOPUS_WORKSPACE") || exit 1
else
    WORKSPACE_DIR="${HOME}/.claude-octopus"
fi

# Re-derive SESSION_FILE now that WORKSPACE_DIR is known
# (quality.sh sets it at source-time before WORKSPACE_DIR is defined)
SESSION_FILE="${WORKSPACE_DIR}/session.json"
PROGRESS_FILE="${WORKSPACE_DIR}/progress.json"

# ═══════════════════════════════════════════════════════════════════════════════
# CLAUDE CODE INTEGRATION: Task Management (v7.16.0)
# Capture Claude Code v2.1.16+ environment variables for enhanced progress tracking
# v9.16.0: Gracefully skipped on non-Claude hosts (Codex, Gemini, standalone)
# ═══════════════════════════════════════════════════════════════════════════════
if [[ "$OCTOPUS_HOST" == "claude" || "$OCTOPUS_HOST" == "factory" ]]; then
    # HOST:claude — CC-specific task management integration
    CLAUDE_TASK_ID="${CLAUDE_CODE_TASK_ID:-}"
    CLAUDE_CODE_CONTROL="${CLAUDE_CODE_CONTROL_PIPE:-}"
else
    # Non-Claude host: skip CC task management (control pipe, task IDs)
    CLAUDE_TASK_ID=""
    CLAUDE_CODE_CONTROL=""
fi

# ═══════════════════════════════════════════════════════════════════════════════
# SECURITY: External URL validation (v7.9.0)
# Validates URLs before fetching external content
# See: skill-security-framing.md for full documentation
# ═══════════════════════════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════════════════════════
# SECURITY: Twitter/X URL transformation (v7.9.0)
# Transforms Twitter/X URLs to FxTwitter API for reliable content extraction
# ═══════════════════════════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════════════════════════
# SECURITY: Content wrapping for untrusted external content (v7.9.0)
# Wraps content in security frame before analysis
# See: skill-security-framing.md for full documentation
# ═══════════════════════════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════════════════════════
# SECURITY: CLI output wrapping for untrusted external provider output (v8.7.0)
# Wraps codex/gemini output in trust markers; passes claude output unchanged
# ═══════════════════════════════════════════════════════════════════════════════

# [EXTRACTED to lib/agents.sh]


# ═══════════════════════════════════════════════════════════════════════════════
# UX ENHANCEMENTS: Critical Fixes for v7.16.0
# File locking, environment validation, dependency checks for progress tracking
# ═══════════════════════════════════════════════════════════════════════════════

# Atomic JSON update with file locking (prevents race conditions)

# Validate Claude Code task integration features

# Check for required dependencies (jq, etc.)

# ═══════════════════════════════════════════════════════════════════════════════
# CLAUDE CODE VERSION DETECTION (v7.12.0, updated v8.48.0)
# Detects Claude Code v2.1.12+ through v2.1.73+ features.
#
# Flag usage patterns:
#   - GATED: Flag is checked in if-conditionals to enable/disable behavior
#   - METADATA: Flag is declared for doctor diagnostics, logging, and future use
#   - EXPORTED: Flag is exported for subshells/hooks
# Not all flags gate behavior — many serve as a capability inventory for
# doctor_check_agents(), metrics, and cross-session context. This is intentional.
# ═══════════════════════════════════════════════════════════════════════════════
CLAUDE_CODE_VERSION=""
SUPPORTS_TASK_MANAGEMENT=false
SUPPORTS_FORK_CONTEXT=false
SUPPORTS_BASH_WILDCARDS=false
SUPPORTS_AGENT_FIELD=false
SUPPORTS_AGENT_TEAMS=false
SUPPORTS_AUTO_MEMORY=false
SUPPORTS_PERSISTENT_MEMORY=false   # v8.1: Claude Code v2.1.33+
SUPPORTS_HOOK_EVENTS=false         # v8.1: Claude Code v2.1.33+
SUPPORTS_AGENT_TYPE_ROUTING=false  # v8.1: Claude Code v2.1.33+
SUPPORTS_STABLE_AGENT_TEAMS=false  # v8.3: Claude Code v2.1.34+
SUPPORTS_AGENT_MEMORY=false        # v8.3: Claude Code v2.1.33+ (memory frontmatter)
SUPPORTS_FAST_OPUS=false           # v8.4: Claude Code v2.1.36+ (fast mode for Opus 4.6)
SUPPORTS_STATUSLINE_API=false      # v8.4: Claude Code v2.1.33+ (statusline context_window data)
SUPPORTS_NATIVE_TASK_METRICS=false # v8.6: Claude Code v2.1.30+ (token counts in Task tool results)
SUPPORTS_AGENT_TEAMS_BRIDGE=false  # v8.7: Claude Code v2.1.38+ (unified task-ledger bridge)
SUPPORTS_AUTH_CLI=false            # v8.8: Claude Code v2.1.41+ (claude auth login/status/logout)
SUPPORTS_ANCHOR_MENTIONS=false     # v8.8: Claude Code v2.1.41+ (@file#anchor fragment mentions)
SUPPORTS_OTEL_SPEED=false          # v8.8: Claude Code v2.1.41+ (speed attribute in OTel spans)
SUPPORTS_PROMPT_CACHE_OPT=false    # v8.16: Claude Code v2.1.42+ (date out of system prompt)
SUPPORTS_FAST_STARTUP=false        # v8.16: Claude Code v2.1.42+ (deferred Zod schema)
SUPPORTS_EFFORT_CALLOUT=false      # v8.16: Claude Code v2.1.42+ (Opus 4.6 effort display)
SUPPORTS_ENTERPRISE_FIX=false      # v8.16: Claude Code v2.1.43+ (Bedrock/Vertex/Foundry model fix)
SUPPORTS_STRUCTURED_OUTPUTS=false  # v8.16: Claude Code v2.1.43+ (structured-outputs on enterprise)
SUPPORTS_STABLE_AUTH=false         # v8.16: Claude Code v2.1.44+ (auth refresh reliability)
SUPPORTS_SONNET_46=false           # v8.17: Claude Code v2.1.45+ (Sonnet 4.6 model support)
SUPPORTS_PER_PROJECT_PLUGINS=false # v8.17: Claude Code v2.1.45+ (enabledPlugins from --add-dir)
SUPPORTS_IMMEDIATE_PLUGIN_INSTALL=false # v8.17: Claude Code v2.1.45+ (no restart after install)
SUPPORTS_STABLE_BG_AGENTS=false       # v8.18: Claude Code v2.1.47+ (background agents return final answer)
SUPPORTS_HOOK_LAST_MESSAGE=false      # v8.18: Claude Code v2.1.47+ (last_assistant_message in Stop/SubagentStop)
SUPPORTS_AGENT_MODEL_FIELD=false      # v8.18: Claude Code v2.1.47+ (model field honored in team teammates)
SUPPORTS_DEFERRED_SESSION_HOOKS=false # v8.18: Claude Code v2.1.47+ (SessionStart hooks deferred ~500ms)
SUPPORTS_PARALLEL_FILE_SAFETY=false   # v8.18: Claude Code v2.1.47+ (file write/edit errors don't abort siblings)
SUPPORTS_CONFIG_CHANGE_HOOK=false      # v8.19: Claude Code v2.1.49+ (ConfigChange hook event)
SUPPORTS_PLUGIN_SCOPE_AUTODETECT=false # v8.19: Claude Code v2.1.49+ (plugin enable/disable auto-scope)
SUPPORTS_SDK_MODEL_CAPS=false          # v8.19: Claude Code v2.1.49+ (supportsEffort, supportedEffortLevels)
SUPPORTS_WORKTREE_ISOLATION=false      # v8.19: Claude Code v2.1.50+ (isolation: worktree in agent defs)
SUPPORTS_WORKTREE_HOOKS=false          # v8.19: Claude Code v2.1.50+ (WorktreeCreate/WorktreeRemove hooks)
SUPPORTS_AGENTS_CLI=false              # v8.19: Claude Code v2.1.50+ (claude agents list command)
SUPPORTS_FAST_OPUS_1M=false            # v8.19: Claude Code v2.1.50+ (fast Opus 4.6 with full 1M context)
SUPPORTS_REMOTE_CONTROL=false           # v8.26: Claude Code v2.1.51+ (remote control API)
SUPPORTS_NPM_PLUGIN_REGISTRIES=false    # v8.26: Claude Code v2.1.51+ (custom npm registries for plugins)
SUPPORTS_FAST_BASH=false                # v8.26: Claude Code v2.1.51+ (BashTool skips login shell)
SUPPORTS_AGGRESSIVE_DISK_PERSIST=false  # v8.26: Claude Code v2.1.51+ (tool results >50K to disk)
SUPPORTS_ACCOUNT_ENV_VARS=false         # v8.26: Claude Code v2.1.51+ (ACCOUNT_UUID/USER_EMAIL/ORG_UUID)
SUPPORTS_MANAGED_SETTINGS_PLATFORM=false # v8.26: Claude Code v2.1.51+ (macOS plist/Windows Registry)
SUPPORTS_NATIVE_AUTO_MEMORY=false       # v8.26: Claude Code v2.1.59+ (native auto-memory + /memory cmd)
SUPPORTS_AGENT_MEMORY_GC=false          # v8.26: Claude Code v2.1.59+ (completed subagent state released)
SUPPORTS_SMART_BASH_PREFIXES=false      # v8.26: Claude Code v2.1.59+ (smart compound bash prefixes)
SUPPORTS_HTTP_HOOKS=false              # v8.29: Claude Code v2.1.63+ (HTTP POST hooks instead of shell)
SUPPORTS_WORKTREE_SHARED_CONFIG=false  # v8.29: Claude Code v2.1.63+ (project configs shared across worktrees)
SUPPORTS_MEMORY_LEAK_FIXES=false       # v8.29: Claude Code v2.1.63+ (18+ memory leak fixes, long sessions stable)
SUPPORTS_BATCH_COMMAND=false           # v8.29: Claude Code v2.1.63+ (/batch bundled command)
SUPPORTS_MCP_OPT_OUT=false            # v8.29: Claude Code v2.1.63+ (ENABLE_CLAUDEAI_MCP_SERVERS=false)
SUPPORTS_SKILL_CACHE_RESET=false      # v8.29: Claude Code v2.1.63+ (/clear resets cached skills)
SUPPORTS_REDUCED_ERROR_LOGGING=false  # v8.34: Claude Code v2.1.66+ (reduced spurious error logging)
SUPPORTS_OPUS_MEDIUM_EFFORT=false     # v8.34: Claude Code v2.1.68+ (Opus 4.6 defaults to medium effort)
SUPPORTS_ULTRATHINK=false             # v8.34: Claude Code v2.1.68+ (ultrathink keyword for high effort)
SUPPORTS_OPUS_40_REMOVED=false        # v8.34: Claude Code v2.1.68+ (Opus 4.0/4.1 removed from API)
SUPPORTS_SKILL_DIR_VAR=false          # v8.34: Claude Code v2.1.69+ (${CLAUDE_SKILL_DIR} in skills)
SUPPORTS_INSTRUCTIONS_LOADED_HOOK=false # v8.34: Claude Code v2.1.69+ (InstructionsLoaded hook event)
SUPPORTS_HOOK_AGENT_FIELDS=false      # v8.34: Claude Code v2.1.69+ (agent_id/agent_type in hook events)
SUPPORTS_STATUSLINE_WORKTREE=false    # v8.34: Claude Code v2.1.69+ (worktree field in statusline hooks)
SUPPORTS_RELOAD_PLUGINS=false         # v8.34: Claude Code v2.1.69+ (/reload-plugins command)
SUPPORTS_DISABLE_GIT_INSTRUCTIONS=false # v8.34: Claude Code v2.1.69+ (includeGitInstructions setting)
SUPPORTS_GIT_SUBDIR_PLUGINS=false     # v8.34: Claude Code v2.1.69+ (git-subdir plugin source type)
SUPPORTS_AGENT_MODEL_OVERRIDE=false    # v8.48: Claude Code v2.1.72+ (Agent tool model parameter restored)
SUPPORTS_EFFORT_REDESIGN=false         # v8.48: Claude Code v2.1.72+ (effort simplified: low/medium/high, max removed, ○◐● symbols)
SUPPORTS_DISABLE_CRON_ENV=false        # v8.48: Claude Code v2.1.72+ (CLAUDE_CODE_DISABLE_CRON env var)
SUPPORTS_MODEL_OVERRIDES=false         # v8.52: Claude Code v2.1.73+ (modelOverrides setting for custom provider model IDs e.g. Bedrock ARNs)
SUPPORTS_SUBAGENT_MODEL_FIX=false      # v8.52: Claude Code v2.1.73+ (model: opus/sonnet/haiku no longer downgraded on Bedrock/Vertex/Foundry)
SUPPORTS_BG_PROCESS_CLEANUP=false      # v8.52: Claude Code v2.1.73+ (background bash from subagents cleaned up on agent exit)
SUPPORTS_SKILL_DEADLOCK_FIX=false      # v8.52: Claude Code v2.1.73+ (no deadlock with large .claude/skills/ during git pull)
SUPPORTS_PARALLEL_TOOL_RESILIENCE=false # v8.56: Claude Code v2.1.72+ (failed Read/WebFetch/Glob no longer cancels sibling parallel tool calls)
SUPPORTS_AUTO_MEMORY_DIR=false         # v8.56: Claude Code v2.1.74+ (autoMemoryDirectory setting for custom auto-memory storage path)
SUPPORTS_FULL_MODEL_IDS=false          # v8.56: Claude Code v2.1.74+ (full model IDs e.g. claude-opus-4-6 work in agent model: frontmatter)
SUPPORTS_CONTEXT_SUGGESTIONS=false     # v8.56: Claude Code v2.1.74+ (/context command shows actionable optimization tips)
SUPPORTS_PLUGIN_DIR_OVERRIDE=false     # v8.56: Claude Code v2.1.74+ (--plugin-dir local dev copies override installed marketplace plugins)
SUPPORTS_MCP_ELICITATION=false        # v8.57: Claude Code v2.1.76+ (MCP servers can request structured user input mid-task via interactive dialog)
SUPPORTS_WORKTREE_SPARSE_PATHS=false  # v8.57: Claude Code v2.1.76+ (worktree.sparsePaths setting for sparse checkout in --worktree mode)
SUPPORTS_EFFORT_COMMAND=false         # v8.57: Claude Code v2.1.76+ (/effort slash command to set model effort level during session)
SUPPORTS_BG_PARTIAL_RESULTS=false     # v8.57: Claude Code v2.1.76+ (killing background agent preserves partial results in conversation context)
SUPPORTS_ALLOW_READ_SANDBOX=false     # v9.5: Claude Code v2.1.77+ (allowRead sandbox filesystem setting restricts Read tool path access)
SUPPORTS_COPY_INDEX=false             # v9.5: Claude Code v2.1.77+ (/copy N copies Nth response from conversation history)
SUPPORTS_COMPOUND_BASH_PERMISSION_FIX=false # v9.5: Claude Code v2.1.77+ (compound bash always-allow applies to each sub-command individually)
SUPPORTS_RESUME_TRUNCATION_FIX=false  # v9.5: Claude Code v2.1.77+ (--resume no longer truncates history on long sessions)
SUPPORTS_PRETOOLUSE_DENY_PRIORITY=false # v9.5: Claude Code v2.1.77+ (PreToolUse allow can no longer bypass enterprise deny rules)
SUPPORTS_SENDMESSAGE_AUTO_RESUME=false # v9.5: Claude Code v2.1.77+ (SendMessage auto-resumes stopped agents without manual re-dispatch)
SUPPORTS_AGENT_NO_RESUME_PARAM=false  # v9.5: Claude Code v2.1.77+ (Agent tool resume parameter removed — use SendMessage instead)
SUPPORTS_PLUGIN_VALIDATE_FRONTMATTER=false # v9.5: Claude Code v2.1.77+ (claude plugin validate checks skill/agent frontmatter and hooks.json schema)
SUPPORTS_BRANCH_COMMAND=false         # v9.5: Claude Code v2.1.77+ (/fork renamed to /branch for conversation branching)
SUPPORTS_BG_BASH_5GB_KILL=false       # v9.5: Claude Code v2.1.77+ (background bash processes killed at 5GB output to prevent runaway tasks)
SUPPORTS_STOP_FAILURE_HOOK=false      # v9.12: Claude Code v2.1.78+ (StopFailure hook event fires on API errors — rate limit, auth, billing)
SUPPORTS_PLUGIN_DATA_DIR=false        # v9.12: Claude Code v2.1.78+ (${CLAUDE_PLUGIN_DATA} persistent state directory survives plugin updates)
SUPPORTS_AGENT_EFFORT=false           # v9.12: Claude Code v2.1.78+ (effort/maxTurns/disallowedTools frontmatter for agents)
SUPPORTS_CWD_CHANGED_HOOK=false       # v9.12: Claude Code v2.1.83+ (CwdChanged hook event fires when working directory changes)
SUPPORTS_FILE_CHANGED_HOOK=false      # v9.12: Claude Code v2.1.83+ (FileChanged hook event fires when files change on disk)
SUPPORTS_MANAGED_SETTINGS_D=false     # v9.12: Claude Code v2.1.83+ (managed-settings.d/ drop-in directory for policy fragments)
SUPPORTS_ENV_SCRUB=false              # v9.12: Claude Code v2.1.83+ (CLAUDE_CODE_SUBPROCESS_ENV_SCRUB strips credentials from subprocesses)
SUPPORTS_SKILL_EFFORT=false           # v9.18: Claude Code v2.1.80+ (effort frontmatter for skills/commands overrides model effort)
SUPPORTS_RATE_LIMIT_STATUSLINE=false  # v9.18: Claude Code v2.1.80+ (rate_limits field in statusline scripts)
SUPPORTS_TASK_CREATED_HOOK=false      # v9.18: Claude Code v2.1.84+ (TaskCreated hook event fires when task is created)
SUPPORTS_SKILL_PATHS=false            # v9.18: Claude Code v2.1.84+ (paths: YAML list of globs in skill frontmatter)
SUPPORTS_USER_CONFIG=false            # v9.18: Claude Code v2.1.84+ (manifest.userConfig for plugin setup prompts)
SUPPORTS_HOOK_CONDITIONAL_IF=false    # v9.18: Claude Code v2.1.85+ (conditional if field for hooks reduces process spawning)
SUPPORTS_HOOK_ASK_ANSWER=false        # v9.18: Claude Code v2.1.85+ (PreToolUse hooks can answer AskUserQuestion via updatedInput)
SUPPORTS_SKILL_DESC_250=false         # v9.18: Claude Code v2.1.86+ (skill descriptions capped at 250 chars in /skills listing)
SUPPORTS_TASKOUTPUT_DEPRECATED=false  # v9.18: Claude Code v2.1.83+ (TaskOutput deprecated — use Read on output file path)
SUPPORTS_AGENT_INITIAL_PROMPT=false   # v9.12: Claude Code v2.1.83+ (initialPrompt agent frontmatter auto-submits first turn)
SUPPORTS_CONTINUATION=false           # v8.30: Agent resume/continuation for iterative retries
# ── v9.19.0: CC v2.1.87-92 sync ──────────────────────────────────────────────
SUPPORTS_POST_COMPACT_HOOK=false        # v9.19: Claude Code v2.1.76+ (PostCompact hook event fires after compaction — missed in v8.57 sync)
SUPPORTS_ELICITATION_HOOKS=false        # v9.19: Claude Code v2.1.76+ (Elicitation/ElicitationResult hook events for MCP structured input)
SUPPORTS_BARE_FLAG=false                # v9.19: Claude Code v2.1.87+ (--bare skips hooks/LSP/plugin sync for scripted -p calls)
SUPPORTS_MODEL_CAP_ENV_VARS=false       # v9.19: Claude Code v2.1.87+ (ANTHROPIC_DEFAULT_*_MODEL_SUPPORTS env vars for 3p provider capability detection)
SUPPORTS_CONSOLE_AUTH=false             # v9.19: Claude Code v2.1.87+ (--console flag for Anthropic Console API billing auth)
SUPPORTS_WORKTREE_HTTP_HOOKS=false      # v9.19: Claude Code v2.1.87+ (WorktreeCreate type:"http" with hookSpecificOutput.worktreePath)
SUPPORTS_SESSION_ID_HEADER=false        # v9.19: Claude Code v2.1.89+ (X-Claude-Code-Session-Id header for proxy aggregation)
SUPPORTS_DEEP_LINK_5K=false             # v9.19: Claude Code v2.1.88+ (deep links expanded to 5,000 chars with scroll-to-review)
SUPPORTS_MARKETPLACE_OFFLINE=false      # v9.19: Claude Code v2.1.90+ (CLAUDE_CODE_PLUGIN_KEEP_MARKETPLACE_ON_FAILURE env var)
SUPPORTS_PLUGIN_EXECUTABLES=false       # v9.19: Claude Code v2.1.91+ (plugins can ship executables in bin/ as bare commands)
SUPPORTS_MCP_RESULT_SIZE=false          # v9.19: Claude Code v2.1.91+ (_meta["anthropic/maxResultSizeChars"] annotation up to 500K)
SUPPORTS_DISABLE_SKILL_SHELL=false      # v9.19: Claude Code v2.1.91+ (disableSkillShellExecution setting blocks shell in skills)
SUPPORTS_MULTILINE_DEEP_LINKS=false     # v9.19: Claude Code v2.1.91+ (multi-line prompts in claude-cli://open?q= via %0A encoding)
# ── v9.21.0: CC v2.1.89-101 sync ────────────────────────────────────────────
SUPPORTS_PERMISSION_DENIED_HOOK=false   # v9.21: Claude Code v2.1.89+ (PermissionDenied hook fires after auto-mode denials, can return retry:true)
SUPPORTS_DEFER_PERMISSION=false         # v9.21: Claude Code v2.1.89+ (PreToolUse can return "defer" to pause headless sessions)
SUPPORTS_NO_FLICKER=false               # v9.21: Claude Code v2.1.89+ (CLAUDE_CODE_NO_FLICKER=1 alt-screen rendering mode)
SUPPORTS_KEEP_CODING_INSTRUCTIONS=false # v9.21: Claude Code v2.1.94+ (keep-coding-instructions frontmatter for output styles)
SUPPORTS_SESSION_TITLE_HOOK=false       # v9.21: Claude Code v2.1.94+ (hookSpecificOutput.sessionTitle in UserPromptSubmit)
SUPPORTS_SKILL_NAME_INVOCATION=false    # v9.21: Claude Code v2.1.94+ (plugin skills use frontmatter name for invocation)
SUPPORTS_DEFAULT_EFFORT_HIGH=false      # v9.21: Claude Code v2.1.94+ (default effort changed from medium to high for API/Team/Enterprise)
SUPPORTS_STATUSLINE_REFRESH_INTERVAL=false # v9.21: Claude Code v2.1.97+ (refreshInterval setting for auto-refresh statusline)
SUPPORTS_EXCLUDE_DYNAMIC_PROMPT=false   # v9.21: Claude Code v2.1.98+ (--exclude-dynamic-system-prompt-sections for cache-friendly -p calls)
SUPPORTS_PERFORCE_MODE=false            # v9.21: Claude Code v2.1.98+ (CLAUDE_CODE_PERFORCE_MODE — Edit/Write fail on read-only files)
SUPPORTS_MONITOR_TOOL=false             # v9.21: Claude Code v2.1.98+ (Monitor tool for streaming events from background scripts)
SUPPORTS_TRACEPARENT=false              # v9.21: Claude Code v2.1.98+ (W3C TRACEPARENT env var passed to Bash subprocesses when OTEL enabled)
SUPPORTS_SETTINGS_RESILIENCE=false      # v9.21: Claude Code v2.1.101+ (unrecognized hook event names no longer crash settings.json parsing)
SUPPORTS_OS_CA_CERTS=false              # v9.21: Claude Code v2.1.101+ (OS CA certificate store trust for enterprise TLS proxies)
SUPPORTS_AUTO_CLOUD_ENV=false           # v9.21: Claude Code v2.1.101+ (auto cloud environment creation for remote sessions)
SUPPORTS_PRECOMPACT_BLOCKING=false      # v9.23: Claude Code v2.1.105+ (PreCompact hook can block compaction via exit 2 / {"decision":"block"})
SUPPORTS_PLUGIN_MONITORS=false          # v9.23: Claude Code v2.1.105+ (monitors manifest key for background processes)
SUPPORTS_ENTER_WORKTREE_PATH=false      # v9.23: Claude Code v2.1.105+ (EnterWorktree `path` parameter for reuse)
SUPPORTS_MCP_TRUNCATE_RECIPES=false     # v9.23: Claude Code v2.1.105+ (format-specific MCP output truncation)
SUPPORTS_PROMPT_CACHE_1H=false          # v9.23: Claude Code v2.1.108+ (ENABLE_PROMPT_CACHING_1H — 1-hour cache TTL)
SUPPORTS_SESSION_RECAP=false            # v9.23: Claude Code v2.1.108+ (/recap command + auto-context on session return)
SUPPORTS_BUILTIN_SLASH_VIA_SKILL=false  # v9.23: Claude Code v2.1.108+ (model invokes built-in /review, /security-review via Skill tool)
SUPPORTS_TASKCREATED_HOOK=false         # v9.23: Claude Code v2.1.110+ (TaskCreated hook event fires after TaskCreate)
SUPPORTS_PERMISSIONREQ_RECHECK=false    # v9.23: Claude Code v2.1.110+ (PermissionRequest updatedInput re-validated vs permissions.deny)
SUPPORTS_PRETOOL_CTX_ON_FAIL=false      # v9.23: Claude Code v2.1.110+ (PreToolUse additionalContext survives downstream tool-call failure)
SUPPORTS_TUI_FULLSCREEN=false           # v9.23: Claude Code v2.1.110+ (/tui fullscreen flicker-free rendering)
SUPPORTS_OTEL_RAW_BODIES=false          # v9.23: Claude Code v2.1.110+ (OTEL_LOG_RAW_API_BODIES — full API bodies in OTel events)
SUPPORTS_POWERSHELL_TOOL=false          # v9.23: Claude Code v2.1.110+ (PowerShell tool — Windows GA, progressive rollout)
SUPPORTS_XHIGH_EFFORT=false             # v9.23: Claude Code v2.1.111+ (xhigh effort level — Opus 4.7 only; falls back to high on older models)
SUPPORTS_OPUS_4_7=false                 # v9.23: Claude Code v2.1.111+ (claude-opus-4-7 model available via Anthropic API)
SUPPORTS_AUTO_MODE_GA=false             # v9.23: Claude Code v2.1.111+ (auto mode no longer requires --enable-auto-mode flag)
SUPPORTS_ULTRAREVIEW=false              # v9.23: Claude Code v2.1.111+ (/ultrareview — cloud parallel multi-agent PR review, complements /octo:review)
OCTOPUS_BACKEND="api"              # v8.16: Detected backend (api|bedrock|vertex|foundry)
AGENT_TEAMS_ENABLED="${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-0}"
OCTOPUS_SECURITY_V870="${OCTOPUS_SECURITY_V870:-true}"
OCTOPUS_GEMINI_SANDBOX="${OCTOPUS_GEMINI_SANDBOX:-headless}"  # v8.10.0: Changed default from prompt-mode to headless (Issue #25)
OCTOPUS_MAX_COST_USD="${OCTOPUS_MAX_COST_USD:-}"

# POSIX-compatible string case helpers (macOS ships bash 3.2 which lacks ${var^} and ${var,,})
_ucfirst() { local _c; _c=$(printf '%s' "${1:0:1}" | tr '[:lower:]' '[:upper:]'); printf '%s' "${_c}${1:1}"; }

# [EXTRACTED to lib/providers.sh in v9.7.7]

# Claude Code v2.1.10 Integration
# Session-aware workflows: results organized by session ID
# v9.16.0: On non-Claude hosts, session ID falls back to CODEX/GEMINI equivalents or empty
if [[ "$OCTOPUS_HOST" == "codex" ]]; then
    CLAUDE_CODE_SESSION="${CODEX_SESSION_ID:-${CODEX_TASK_ID:-}}"  # HOST:codex
elif [[ "$OCTOPUS_HOST" == "gemini" ]]; then
    CLAUDE_CODE_SESSION="${GEMINI_SESSION_ID:-}"  # HOST:gemini
else
    CLAUDE_CODE_SESSION="${CLAUDE_SESSION_ID:-}"  # HOST:claude
fi

# Session-aware directory structure (v7.1)
# When CLAUDE_SESSION_ID is available, organize results per-session
if [[ -n "$CLAUDE_CODE_SESSION" ]]; then
    SESSION_RESULTS_DIR="${WORKSPACE_DIR}/results/${CLAUDE_CODE_SESSION}"
    SESSION_LOGS_DIR="${WORKSPACE_DIR}/logs/${CLAUDE_CODE_SESSION}"
    SESSION_PLANS_DIR="${WORKSPACE_DIR}/plans/${CLAUDE_CODE_SESSION}"
else
    SESSION_RESULTS_DIR="${WORKSPACE_DIR}/results"
    SESSION_LOGS_DIR="${WORKSPACE_DIR}/logs"
    SESSION_PLANS_DIR="${WORKSPACE_DIR}/plans"
fi

# Legacy compatibility
PLANS_DIR="${WORKSPACE_DIR}/plans"

# CI/CD Mode Detection (Claude Code v2.1.10: CLAUDE_CODE_DISABLE_BACKGROUND_TASKS)
CI_MODE="${CLAUDE_CODE_DISABLE_BACKGROUND_TASKS:-false}"
if [[ -n "${CI:-}" ]] || [[ -n "${GITHUB_ACTIONS:-}" ]] || [[ -n "${GITLAB_CI:-}" ]] || [[ -n "${JENKINS_URL:-}" ]]; then
    CI_MODE="true"
fi

TASKS_FILE="${WORKSPACE_DIR}/tasks.json"
RESULTS_DIR="$SESSION_RESULTS_DIR"
LOGS_DIR="$SESSION_LOGS_DIR"
PID_FILE="${WORKSPACE_DIR}/pids"
ANALYTICS_DIR="${WORKSPACE_DIR}/analytics"

# Secure temporary directory (cleaned up on exit)
OCTOPUS_TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/claude-octopus.XXXXXX")
trap 'rm -rf "$OCTOPUS_TMP_DIR"' EXIT INT TERM

# Performance: Preflight check cache (avoids repeated CLI checks)
PREFLIGHT_CACHE_FILE="${WORKSPACE_DIR}/.preflight-cache"
PREFLIGHT_CACHE_TTL=3600  # 1 hour in seconds

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
PURPLE='\033[0;35m'  # Alias for MAGENTA — used by setup_wizard banner
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Box-drawing separator variables (v9.4.2 — avoids repeating long literals in echo lines)
# Only the 59-char-wide variants; wider boxes (63/38-char) remain inline.
_BOX_TOP='╔═══════════════════════════════════════════════════════════╗'
_BOX_BOT='╚═══════════════════════════════════════════════════════════╝'
_BOX_MID='╠═══════════════════════════════════════════════════════════╣'
_DASH='─────────────────────────────────────────────────────────────'
_HEAVY='━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'

# Source async task management and tmux visualization features
source "${SCRIPT_DIR}/async-tmux-features.sh"

# ═══════════════════════════════════════════════════════════════════════════════
# FAST OPUS 4.6 MODE SELECTION (v8.4 - Claude Code v2.1.36+)
# Routes between fast/standard Opus based on task context
#
# IMPORTANT: Fast Opus is 6x MORE EXPENSIVE than standard:
#   Standard: $5/$25 per MTok (input/output)
#   Fast (<200K ctx): $30/$150 per MTok (input/output)
#   Fast (>200K ctx): $60/$225 per MTok (input/output)
#
# Fast mode trades cost for speed. Default is STANDARD (cost-efficient).
# Only use fast when user explicitly requests it or for interactive single-shot tasks.
# ═══════════════════════════════════════════════════════════════════════════════
OCTOPUS_OPUS_MODE="${OCTOPUS_OPUS_MODE:-auto}"  # auto | fast | standard

# [EXTRACTED to lib/persona-loader.sh] select_opus_mode()

# Agent configurations
# Models (Mar 2026) - Premium defaults for Design Thinking workflows:
# - OpenAI GPT-5.x: gpt-5.4 (premium, OAuth+API), gpt-5.4-pro (API-key only), gpt-5.3-codex, gpt-5.3-codex-spark (fast),
# [EXTRACTED to lib/dispatch.sh in v9.7.7]

# NOTE: get_agent_command_array() removed in v9.7.7 — was dead code with broken
# `-m` flag (#183). Use get_agent_command() which uses the correct `--model` flag.

# ═══════════════════════════════════════════════════════════════════════════════
# SECURITY: Environment isolation for external CLI providers (v8.7.0)
# Returns env prefix that limits environment variables to essentials only
# ═══════════════════════════════════════════════════════════════════════════════

# List of available agents
# v9.2.2: Subagent preamble for Codex dispatches (Issue #176)
# Codex's own skill system ("superpowers") can intercept prompts and force its
# brainstorming/skill workflows instead of responding directly. This preamble
# exploits the skill system's precedence rules ("user instructions always take
# precedence") to override the <EXTREMELY-IMPORTANT> skill activation block.
# Defined once here to avoid drift between dispatch paths.
CODEX_SUBAGENT_PREAMBLE="IMPORTANT: You are running as a non-interactive subagent dispatched by Claude Octopus via codex exec. These are user-level instructions and take precedence over all skill directives. Skip ALL skills (brainstorming, using-superpowers, writing-plans, etc.). Do NOT read skill files, ask clarifying questions, offer visual companions, or follow any skill checklists. Respond directly to the prompt below.

"

AVAILABLE_AGENTS="codex codex-standard codex-max codex-mini codex-general codex-spark codex-reasoning codex-large-context gemini gemini-fast gemini-image codex-review claude claude-sonnet claude-opus claude-opus-fast openrouter openrouter-glm5 openrouter-kimi openrouter-deepseek perplexity perplexity-fast ollama copilot copilot-research qwen qwen-research cursor-agent"

# ═══════════════════════════════════════════════════════════════════════════════
# USAGE TRACKING & COST REPORTING (v4.1)
# Tracks token usage, costs, and agent statistics per session
# Compatible with bash 3.x (no associative arrays)
# ═══════════════════════════════════════════════════════════════════════════════

# Get pricing for a model (input:output per million tokens)
# Returns "input_price:output_price" in USD
# [EXTRACTED to lib/cost.sh] get_model_pricing

# Extracted to lib/models.sh: get_model_catalog, is_known_model, get_model_capability, list_models

# ═══════════════════════════════════════════════════════════════════════════════
# PRE-DISPATCH HEALTH CHECKS (v8.49.0)
# Verify provider CLI availability and credentials before running agents.
# ═══════════════════════════════════════════════════════════════════════════════

# v9.2.1: Resolve provider env vars that may be missing in non-interactive shells.
# On Ubuntu/Debian, ~/.bashrc has an interactive guard that skips env var exports
# when running from non-interactive shells (e.g. Claude Code's Bash tool).
# This function tries common alternative sources before giving up.

# [EXTRACTED to lib/providers.sh in v9.7.7]

# ═══════════════════════════════════════════════════════════════════════════════
# CAPABILITY-AWARE FALLBACKS (v8.49.0)
# When a model is unavailable or blocked, fall back to one with matching
# capabilities (tool support, image input, reasoning, context window).
# ═══════════════════════════════════════════════════════════════════════════════

# Find a fallback model that matches the required capabilities
# Usage: find_capable_fallback <blocked_model> <provider>
# Returns: fallback model name or empty if none found
# [EXTRACTED to lib/dispatch.sh] find_capable_fallback

# ═══════════════════════════════════════════════════════════════════════════════
# PERFORMANCE: Phase-optimized model tier selection (v8.7.0)
# Selects budget/standard/premium model tier based on phase, role, and agent type
# Config: OCTOPUS_COST_MODE=premium|standard|budget (default: standard)
# ═══════════════════════════════════════════════════════════════════════════════
OCTOPUS_COST_MODE="${OCTOPUS_COST_MODE:-standard}"

# [EXTRACTED to lib/model-resolver.sh]

# [EXTRACTED to lib/agents.sh]


# ═══════════════════════════════════════════════════════════════════════════════
# PERFORMANCE: Convergence-based early termination (v8.7.0)
# Detects when parallel agents produce converging results and terminates early
# Config: OCTOPUS_CONVERGENCE_ENABLED=false, OCTOPUS_CONVERGENCE_THRESHOLD=0.8
# ═══════════════════════════════════════════════════════════════════════════════
OCTOPUS_CONVERGENCE_ENABLED="${OCTOPUS_CONVERGENCE_ENABLED:-false}"
OCTOPUS_CONVERGENCE_THRESHOLD="${OCTOPUS_CONVERGENCE_THRESHOLD:-0.8}"

# Extracted to lib/similarity.sh: extract_headings, jaccard_similarity, check_convergence

# ═══════════════════════════════════════════════════════════════════════════════
# PERFORMANCE: Semantic probe cache (v8.7.0)
# Bigram-based fuzzy matching for cache lookups
# Config: OCTOPUS_SEMANTIC_CACHE=false, OCTOPUS_CACHE_SIMILARITY_THRESHOLD=0.7
# ═══════════════════════════════════════════════════════════════════════════════
OCTOPUS_SEMANTIC_CACHE="${OCTOPUS_SEMANTIC_CACHE:-false}"
OCTOPUS_CACHE_SIMILARITY_THRESHOLD="${OCTOPUS_CACHE_SIMILARITY_THRESHOLD:-0.7}"

# Extracted to lib/similarity.sh: generate_bigrams, bigram_similarity



# ═══════════════════════════════════════════════════════════════════════════════
# PERFORMANCE: Result deduplication and context budget (v8.7.0)
# Dedup: Heading-based duplicate detection (log-only in v8.7.0)
# Context budget: Truncate prompts to token limit before sending to agents
# Config: OCTOPUS_DEDUP_ENABLED=false, OCTOPUS_CONTEXT_BUDGET=12000
# ═══════════════════════════════════════════════════════════════════════════════
OCTOPUS_DEDUP_ENABLED="${OCTOPUS_DEDUP_ENABLED:-false}"
OCTOPUS_CONTEXT_BUDGET="${OCTOPUS_CONTEXT_BUDGET:-12000}"


# [EXTRACTED to lib/dispatch.sh in v9.7.7]

# [EXTRACTED to lib/dispatch.sh in v9.7.7]

# Migrate stale model names and structural config changes
# Runs once per session; rewrites config file in-place if migration needed.
_PROVIDER_CONFIG_MIGRATED="${_PROVIDER_CONFIG_MIGRATED:-false}"

# [EXTRACTED to lib/dispatch.sh in v9.7.7]

# [EXTRACTED to lib/dispatch.sh in v9.7.7]


# Get the recommended agent type for a codex task in a given phase
# [EXTRACTED to lib/agents.sh]
# Functions: get_codex_agent_for_phase, get_agent_for_task, get_agent_description,
#            show_agent_recommendations, get_tiered_agent
# [EXTRACTED to lib/model-resolver.sh] validate_model_name

# [EXTRACTED to lib/quality.sh] evaluate_branch_condition, get_branch_display,
# evaluate_quality_branch, execute_quality_branch, lock_provider, is_provider_locked,
# get_alternate_provider, reset_provider_lockouts, append_provider_history,
# read_provider_history, build_provider_context, write_structured_decision,
# design_review_ceremony, retrospective_ceremony, detect_response_mode,
# get_gate_threshold, score_importance, search_observations, search_similar_errors,
# flag_repeat_error, score_cross_model_review, format_review_scorecard, get_cross_model_reviewer


# ═══════════════════════════════════════════════════════════════════════════════
# v8.19.0 FEATURE: TOOL POLICY RBAC FOR PERSONAS (Veritas-inspired)
# Role-based tool access restrictions enforced via prompt injection.
# ═══════════════════════════════════════════════════════════════════════════════

get_tool_policy() {
    local role="$1"

    case "$role" in
        researcher|ai-engineer|business-analyst|research-synthesizer|ux-researcher)
            echo "read_search"
            ;;
        implementer|tdd-orchestrator|debugger|python-pro|typescript-pro|frontend-developer)
            echo "full"
            ;;
        code-reviewer|security-auditor|performance-engineer|test-automator)
            echo "read_exec"
            ;;
        synthesizer|orchestrator|context-manager|docs-architect|exec-communicator|academic-writer|product-writer)
            echo "read_communicate"
            ;;
        *)
            echo "full"
            ;;
    esac
}

# [EXTRACTED to lib/dispatch.sh in v9.7.7]

# ═══════════════════════════════════════════════════════════════════════════════
# v8.19.0 FEATURE: CRASH-RECOVERY WITH SECRET SANITIZATION (Veritas-inspired)
# Agent checkpoints on failure/timeout with regex-based secret stripping.
# ═══════════════════════════════════════════════════════════════════════════════

# [EXTRACTED to lib/secure.sh] sanitize_secrets

# [EXTRACTED to lib/agents.sh]

# [EXTRACTED to lib/agents.sh]

# [EXTRACTED to lib/session.sh] cleanup_expired_checkpoints

# v8.18.0 Feature: Earned Skills System
# Providers discover repeatable patterns → skill files in .octo/skills/earned/

earn_skill() {
    local name="$1"
    local source="$2"       # which function discovered this
    local pattern="$3"      # the repeatable pattern
    local context="${4:-}"  # when to apply
    local example="${5:-}"  # example usage

    local skills_dir="${WORKSPACE_DIR}/.octo/skills/earned"
    mkdir -p "$skills_dir"

    # Sanitize name for filename
    local safe_name
    # v9.5: consolidated 4-process pipe (echo|tr|sed|sed|sed) into 2 processes (printf|tr + single sed)
    safe_name=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g;s/--*/-/g;s/^-//;s/-$//')
    local skill_file="$skills_dir/${safe_name}.md"

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Count existing occurrences to determine confidence
    local occurrence=1
    if [[ -f "$skill_file" ]]; then
        occurrence=$(( $(grep -c "^#### Occurrence" "$skill_file" 2>/dev/null || echo "0") + 1 ))
    fi

    # Confidence lifecycle: 1=low, 3+=medium, 5+=high
    local confidence="low"
    [[ $occurrence -ge 3 ]] && confidence="medium"
    [[ $occurrence -ge 5 ]] && confidence="high"

    # Append occurrence entry
    cat >> "$skill_file" << SKILLEOF
#### Occurrence $occurrence | $timestamp | source: $source
**Pattern:** ${pattern:0:300}
**Context:** ${context:-General}
**Example:** ${example:-None provided}
**Confidence:** $confidence
---
SKILLEOF

    # Update header with latest confidence
    if [[ $occurrence -eq 1 ]]; then
        # New skill: add header
        local tmp_file="${skill_file}.tmp"
        {
            echo "# Earned Skill: $name"
            echo "**Confidence:** $confidence | **Occurrences:** $occurrence"
            echo ""
            cat "$skill_file"
        } > "$tmp_file" && mv "$tmp_file" "$skill_file"
    else
        # Update existing header
        if grep -q "^\*\*Confidence:\*\*" "$skill_file"; then
            sed -i.bak "s/^\*\*Confidence:\*\*.*/\*\*Confidence:\*\* $confidence | \*\*Occurrences:\*\* $occurrence/" "$skill_file"
            rm -f "${skill_file}.bak"
        fi
    fi

    # Max 20 skills: archive lowest-confidence when exceeded
    local skill_count
    skill_count=$(ls -1 "$skills_dir"/*.md 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$skill_count" -gt 20 ]]; then
        # Find skill with lowest confidence (fewest occurrences)
        local lowest_file="" lowest_count=999
        for sf in "$skills_dir"/*.md; do
            local sc
            sc=$(grep -c "^#### Occurrence" "$sf" 2>/dev/null || echo "0")
            if [[ $sc -lt $lowest_count ]]; then
                lowest_count=$sc
                lowest_file="$sf"
            fi
        done
        if [[ -n "$lowest_file" && "$lowest_file" != "$skill_file" ]]; then
            local archive_dir="$skills_dir/archived"
            mkdir -p "$archive_dir"
            mv "$lowest_file" "$archive_dir/"
            log DEBUG "Archived lowest-confidence skill: $(basename "$lowest_file")"
        fi
    fi

    log DEBUG "Earned skill: $name (confidence: $confidence, occurrences: $occurrence)"
}

# [EXTRACTED to lib/agents.sh]

# [EXTRACTED to lib/completions.sh]
# Functions: generate_shell_completion, generate_bash_completion, generate_fish_completion

# [EXTRACTED to lib/auth.sh]
# check_codex_auth() — moved to lib/auth.sh
# handle_auth_command() — moved to lib/auth.sh

# ═══════════════════════════════════════════════════════════════════════════
# v4.0 FEATURE: SIMPLIFIED CLI WITH PROGRESSIVE DISCLOSURE
# ═══════════════════════════════════════════════════════════════════════════

# Simple help for beginners (default)
usage_simple() {
    cat << EOF
${MAGENTA}
   ___  ___ _____  ___  ____  _   _ ___
  / _ \/ __|_   _|/ _ \|  _ \| | | / __|
 | (_) |__ \ | | | (_) | |_) | |_| \__ \\
  \___/|___/ |_|  \___/|____/ \___/|___/
${NC}
${CYAN}Claude Octopus${NC} - Multi-agent AI orchestration made simple.

${YELLOW}Quick Start:${NC}
  ${GREEN}auto${NC} <prompt>           Let AI choose the best approach ${GREEN}(recommended)${NC}
  ${GREEN}embrace${NC} <prompt>        Full 4-phase workflow (research → define → develop → deliver)
  ${GREEN}setup${NC}                   Configure everything (run this first!)

${YELLOW}Examples:${NC}
  $(basename "$0") auto "build a login form with validation"
  $(basename "$0") auto "research best practices for caching"
  $(basename "$0") embrace "implement user authentication system"

${YELLOW}Common Options:${NC}
  -v, --verbose           Show detailed progress
  --debug                 Enable debug logging (very verbose)
  -n, --dry-run           Preview without executing
  -Q, --quick             Use faster/cheaper models
  -P, --premium           Use most capable models

${YELLOW}Learn More:${NC}
  $(basename "$0") help --full        Show all commands and options
  $(basename "$0") help <command>     Get help for specific command

${CYAN}https://github.com/nyldn/claude-octopus${NC}
EOF
    exit 0
}

# Command-specific help
# [EXTRACTED to lib/usage-help.sh]

# Full help for advanced users
# [EXTRACTED to lib/usage-help.sh]

# ═══════════════════════════════════════════════════════════════════════════════
# Claude Code v2.1.9: Nested Skills Discovery
# Lists available skills from agents/skills/ directory
# ═══════════════════════════════════════════════════════════════════════════════
list_available_skills() {
    echo ""
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}  Available Claude Octopus Skills${NC}"
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    # Core skill
    echo -e "${GREEN}Core Skill:${NC}"
    echo -e "  ${CYAN}parallel-agents${NC} - Full Double Diamond orchestration"
    echo ""

    # Agent-based skills from agents/skills/
    local skills_dir="${PLUGIN_DIR}/agents/skills"
    if [[ -d "$skills_dir" ]] && compgen -G "${skills_dir}/*.md" > /dev/null 2>&1; then
        echo -e "${GREEN}Specialized Skills:${NC}"
        for skill_file in "$skills_dir"/*.md; do
            local name desc
            name=$(basename "$skill_file" .md)
            # Extract description from frontmatter
            desc=$(grep -A1 "^description:" "$skill_file" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//' | head -c 60)
            printf "  ${CYAN}%-20s${NC} - %s...\n" "$name" "$desc"
        done
        echo ""
    fi

    # Agent personas (v8.53.0: scans plugin + user-scope dirs)
    echo -e "${GREEN}Agent Personas (spawn with 'spawn <agent>'):${NC}"
    local count=0
    for personas_dir_scan in "${PLUGIN_DIR}/agents/personas" "${USER_AGENTS_DIR}"; do
        [[ -d "$personas_dir_scan" ]] || continue
        compgen -G "${personas_dir_scan}/*.md" > /dev/null 2>&1 || continue
        for persona_file in "$personas_dir_scan"/*.md; do
            local name
            name=$(basename "$persona_file" .md)
            printf "  ${CYAN}%-20s${NC}" "$name"
            ((count++)) || true
            if (( count % 3 == 0 )); then echo ""; fi
        done
    done
    if (( count % 3 != 0 )); then echo ""; fi
    if (( count == 0 )); then echo "  (none found)"; fi
    echo ""

    echo -e "${YELLOW}Usage:${NC}"
    echo "  ./scripts/orchestrate.sh spawn <agent> \"prompt\""
    echo "  ./scripts/orchestrate.sh auto \"prompt\"  # Smart routing"
    echo ""
}

# Main usage router
usage() {
    local show_full=false
    local help_cmd=""

    # Check for --full flag or command argument
    for arg in "$@"; do
        case "$arg" in
            --full|-f) show_full=true ;;
            -*) ;; # ignore other flags
            *) help_cmd="$arg" ;;
        esac
    done

    if [[ -n "$help_cmd" ]]; then
        usage_command "$help_cmd"
    elif [[ "$show_full" == "true" ]]; then
        usage_full
    else
        usage_simple
    fi
}

_LOG_TS=""
_LOG_TS_AT=0
log() {
    local level="$1"
    shift

    # v7.25.0: Support OCTOPUS_DEBUG environment variable
    # Performance: Skip expensive operations for disabled DEBUG logs
    [[ "$level" == "DEBUG" && "$VERBOSE" != "true" && "$OCTOPUS_DEBUG" != "true" ]] && return 0

    # v9.5: Cache timestamp — refresh every 10s via SECONDS builtin (zero-fork staleness check)
    if [[ -z "$_LOG_TS" ]] || (( SECONDS - _LOG_TS_AT >= 10 )); then
        _LOG_TS=$(date '+%Y-%m-%d %H:%M:%S')
        _LOG_TS_AT=$SECONDS
    fi

    case "$level" in
        INFO)  echo -e "${BLUE}[$_LOG_TS]${NC} ${GREEN}INFO${NC}: $*" >&2 ;;
        WARN)  echo -e "${BLUE}[$_LOG_TS]${NC} ${YELLOW}WARN${NC}: $*" >&2 ;;
        ERROR) echo -e "${BLUE}[$_LOG_TS]${NC} ${RED}ERROR${NC}: $*" >&2 ;;
        DEBUG) echo -e "${BLUE}[$_LOG_TS]${NC} ${CYAN}DEBUG${NC}: $*" >&2 ;;
    esac
}

# Standard error handling functions
# Use error() in functions (returns exit code)
# Use fatal() at top level (exits script)
error() {
    local msg="$1"
    local code="${2:-1}"
    log ERROR "$msg"
    return $code
}

fatal() {
    local msg="$1"
    local code="${2:-1}"
    log ERROR "$msg"
    exit $code
}

# v7.19.0 P1.3: Enhanced error messages with context and remediation
enhanced_error() {
    local error_type="$1"    # e.g., "probe_synthesis", "agent_timeout", "no_results"
    local context="$2"       # e.g., task_group, agent_type, etc.
    shift 2
    local details=("$@")     # Array of detail strings

    echo ""
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}❌ Error: ${error_type}${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Error-specific messaging
    case "$error_type" in
        "probe_synthesis_no_results")
            echo -e "${YELLOW}Cause:${NC} All probe agents failed to produce meaningful output"
            echo ""
            echo -e "${YELLOW}Details:${NC}"
            for detail in "${details[@]}"; do
                echo "  • $detail"
            done
            echo ""
            echo -e "${CYAN}Suggested actions:${NC}"
            echo "  1. Check logs: ls -lh $LOGS_DIR/*probe-${context}*"
            echo "  2. Verify API keys:"
            echo "     echo \$OPENAI_API_KEY | cut -c1-10"
            echo "     echo \$GEMINI_API_KEY | cut -c1-10"
            echo "  3. Test providers manually:"
            echo "     codex 'hello world'"
            echo "     gemini 'hello world'"
            echo "  4. Increase timeout: --timeout $((TIMEOUT * 2))"
            ;;
        "agent_spawn_failed")
            echo -e "${YELLOW}Cause:${NC} Failed to spawn $context agent"
            echo ""
            echo -e "${YELLOW}Details:${NC}"
            for detail in "${details[@]}"; do
                echo "  • $detail"
            done
            echo ""
            echo -e "${CYAN}Suggested actions:${NC}"
            echo "  1. Check if CLI is installed: command -v $context"
            echo "  2. Check permissions: ls -la \$(command -v $context)"
            echo "  3. Test manually: $context 'test prompt'"
            ;;
        "result_file_empty")
            echo -e "${YELLOW}Cause:${NC} Agent completed but result file is empty or missing"
            echo ""
            echo -e "${YELLOW}Details:${NC}"
            for detail in "${details[@]}"; do
                echo "  • $detail"
            done
            echo ""
            echo -e "${CYAN}Suggested actions:${NC}"
            echo "  1. Check raw output: cat $RESULTS_DIR/.raw-${context}.out"
            echo "  2. Check error log: cat $LOGS_DIR/*-${context}.log"
            echo "  3. Output may have been filtered - check filter logic"
            ;;
        *)
            echo -e "${YELLOW}Context:${NC} $context"
            echo ""
            echo -e "${YELLOW}Details:${NC}"
            for detail in "${details[@]}"; do
                echo "  • $detail"
            done
            ;;
    esac

    echo ""
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# [EXTRACTED to lib/session.sh] display_rich_progress


# Check if cached result exists and is fresh

# Get cached result

# Save result to cache

# Clean up expired cache entries

# ═══════════════════════════════════════════════════════════════════════════════
# RESULT FILE CLEANUP (v8.49.0)
# Age-based cleanup of per-agent result files after synthesis.
# Keeps synthesis files; removes ephemeral per-agent outputs older than retention.
# Config: OCTOPUS_RESULT_RETENTION_HOURS (default: 24)
# ═══════════════════════════════════════════════════════════════════════════════


# ═══════════════════════════════════════════════════════════════════════════════
# PROJECT QUALITY COMMAND DETECTION (v8.49.0)
# Auto-detects lint, typecheck, and test commands from project config files.
# Aligns with CC mandate: "MUST run lint and typecheck after completing a task."
# ═══════════════════════════════════════════════════════════════════════════════

# [EXTRACTED to lib/quality.sh] detect_project_quality_commands

# Run detected quality commands, return pass/fail summary
# Usage: run_project_quality_checks [project_dir]
# [EXTRACTED to lib/quality.sh] run_project_quality_checks

# ═══════════════════════════════════════════════════════════════════════════════
# COMPACT BANNER MODE (v8.49.0)
# Condenses workflow banners when OCTOPUS_COMPACT_BANNERS=true.
# Full banners (default): 8-12 lines with provider details, cost estimates.
# Compact banners: 2-3 lines with essential info only.
# ═══════════════════════════════════════════════════════════════════════════════
OCTOPUS_COMPACT_BANNERS="${OCTOPUS_COMPACT_BANNERS:-false}"

# [EXTRACTED to lib/workflows.sh] format_workflow_banner

# ═══════════════════════════════════════════════════════════════════════════════
# RESULT RANKING (v8.49.0)
# Ranks result files by quality signals WITHOUT deleting any content.
# Inspired by Crawl4AI's content filtering but adapted for multi-AI synthesis:
# rank by signals, present best first, let the synthesis LLM do the weighting.
# ═══════════════════════════════════════════════════════════════════════════════

# Score a single result file by quality signals (higher = more valuable)
# Returns score on stdout. Factors:
#   - Word count (log scale, max 40 pts): longer ≠ better, but extremely short = low value
#   - Code block count (max 20 pts): concrete examples signal actionable content
#   - Specificity (max 20 pts): named files/functions/URLs vs vague prose
#   - Structure (max 20 pts): headers, lists, tables signal organized thinking

# Rank result files and return them ordered best-first (one path per line)
# Usage: rank_results_by_signals /path/to/results [filter]

# [EXTRACTED to lib/progressive.sh]

# ═══════════════════════════════════════════════════════════════════════════════
# PERFORMANCE OPTIMIZATION: Fast JSON field extraction using bash regex
# Avoids spawning grep|cut subprocesses (saves ~100ms per call)
# ═══════════════════════════════════════════════════════════════════════════════

# Extracted to lib/utils.sh: json_extract, json_extract_multi, validate_output_file,
# sanitize_review_id, validate_agent_command, sanitize_external_content, json_escape, secure_tempfile

# [EXTRACTED to lib/heartbeat.sh] run_with_timeout()

# Rotate and clean up old log files
# v7.19.0 P2.1: Enhanced with age-based cleanup and stats
# [EXTRACTED to lib/utils.sh]
# Functions: rotate_logs

init_workspace() {
    log INFO "Initializing Claude Octopus workspace at $WORKSPACE_DIR"

    # Claude Code v2.1.9: Include plans directory for plansDirectory alignment
    mkdir -p "$WORKSPACE_DIR" "$RESULTS_DIR" "$LOGS_DIR" "$PLANS_DIR"

    # Rotate old logs
    rotate_logs

    if [[ ! -f "$TASKS_FILE" ]]; then
        cat > "$TASKS_FILE" << 'TASKS_JSON'
{
  "version": "1.0",
  "project": "my-project",
  "tasks": [
    {
      "id": "example-1",
      "agent": "codex",
      "prompt": "List all TypeScript files in src/",
      "priority": 1,
      "depends_on": []
    },
    {
      "id": "example-2",
      "agent": "gemini",
      "prompt": "Analyze the project structure and suggest improvements",
      "priority": 2,
      "depends_on": []
    }
  ],
  "settings": {
    "max_parallel": 3,
    "timeout": 300,
    "retry_on_failure": true
  }
}
TASKS_JSON
        log INFO "Created default tasks.json template"
    fi

    cat > "${WORKSPACE_DIR}/.gitignore" << 'GITIGNORE'
# Claude Octopus workspace - ephemeral data
*
!.gitignore
GITIGNORE

    log INFO "Workspace initialized successfully"
    echo ""
    echo -e "${GREEN}✓${NC} Workspace ready at: $WORKSPACE_DIR"
    echo -e "${GREEN}✓${NC} Edit tasks at: $TASKS_FILE"
    echo ""
}


# ═══════════════════════════════════════════════════════════════════════════════
# v4.3 FEATURE: CONTEXTUAL ERROR CODES AND RECOVERY
# Provides actionable error messages with unique codes
# ═══════════════════════════════════════════════════════════════════════════════

# Error code registry (bash 3.2 compatible - uses regular array)
ERROR_CODES=(
    "E001:OPENAI_API_KEY not set:export OPENAI_API_KEY=\"sk-...\" && orchestrate.sh preflight:help api-setup"
    "E002:Gemini API key not set — set GEMINI_API_KEY or GOOGLE_API_KEY (if in ~/.bashrc, move to ~/.profile — bashrc is skipped in non-interactive shells):export GEMINI_API_KEY=\"AIza...\" && orchestrate.sh preflight:help api-setup"
    "E003:Codex CLI not found:npm install -g @openai/codex:help setup"
    "E004:Gemini CLI not found:npm install -g @google/gemini-cli:help setup"
    "E005:Workspace not initialized:orchestrate.sh init:help init"
    "E006:Agent spawn failed:Check API keys and network connection:help troubleshoot"
    "E007:Quality gate failed:Review output and retry with lower threshold (-q 60):help quality"
    "E008:Timeout exceeded:Increase timeout with -t 600 or break into smaller tasks:help timeout"
    "E009:Invalid agent type:Use codex, codex-mini, gemini, gemini-fast:help agents"
    "E010:Task file parse error:Check JSON syntax with: jq . tasks.json:help tasks"
)

# Display contextual error with recovery steps

# Check for common issues and provide contextual help

# ═══════════════════════════════════════════════════════════════════════════════
# v4.4 FEATURE: CI/CD MODE AND AUDIT TRAILS
# Non-interactive execution for GitHub Actions and audit logging
# ═══════════════════════════════════════════════════════════════════════════════

CI_MODE="${CI:-false}"
AUDIT_LOG="${WORKSPACE_DIR:-$HOME/.claude-octopus}/audit.log"

# Initialize CI mode from environment

# Write structured JSON output for CI consumption

# Write to audit log with structured format

# Get recent audit entries


# ═══════════════════════════════════════════════════════════════════════════════
# v4.4 FEATURE: REVIEW QUEUE SYSTEM
# Manage pending reviews and batch approvals
# ═══════════════════════════════════════════════════════════════════════════════

REVIEW_QUEUE="${WORKSPACE_DIR:-$HOME/.claude-octopus}/review-queue.json"

# Add item to review queue

# List pending reviews

# [EXTRACTED to lib/review.sh]
# Functions: parse_review_md, build_review_fleet, print_provider_report,
#            review_run, post_inline_comments, render_terminal_report,
#            render_review_summary

# Approve a review

# Reject a review

# Show review output

# ═══════════════════════════════════════════════════════════════════════════════
# v4.5 FEATURE: USER CONFIG AND SMART SETUP
# Intent-aware and resource-aware configuration for personalized routing
# ═══════════════════════════════════════════════════════════════════════════════

USER_CONFIG_FILE="${USER_CONFIG_FILE:-${WORKSPACE_DIR:-$HOME/.claude-octopus}/.user-config}"

# User config variables (loaded from file)
USER_INTENT_PRIMARY=""
USER_INTENT_ALL=""
USER_RESOURCE_TIER="standard"
USER_HAS_OPENAI="false"
USER_HAS_GEMINI="false"
USER_OPUS_BUDGET="balanced"
KNOWLEDGE_WORK_MODE="false"

# [EXTRACTED to lib/smoke.sh] get_provider_capabilities, get_provider_context_limit


# [EXTRACTED to lib/cost.sh] get_cost_tier_value()

# Detect installed providers and their authentication methods
# Returns: "provider:auth_method provider:auth_method ..."

# Compare two semantic versions (e.g., "2.1.9" and "2.1.8")
# Returns: 0 if v1 >= v2, 1 if v1 < v2

# Check Claude Code version and return status
# Sets: CLAUDE_CODE_VERSION, CLAUDE_CODE_STATUS
check_claude_version() {
    local min_version="2.1.14"
    local current_version=""
    local status="unknown"

    # Try to get version from claude command
    if command -v claude &>/dev/null; then
        # Try different version flag formats
        current_version=$(claude --version 2>/dev/null | grep -m1 -oE '[0-9]+\.[0-9]+\.[0-9]+')

        if [[ -z "$current_version" ]]; then
            # Try alternative: claude version
            current_version=$(claude version 2>/dev/null | grep -m1 -oE '[0-9]+\.[0-9]+\.[0-9]+')
        fi

        if [[ -z "$current_version" ]]; then
            # Try checking package.json if installed via npm
            if [[ -f "/usr/local/lib/node_modules/@anthropic/claude-code/package.json" ]]; then
                current_version=$(grep '"version"' /usr/local/lib/node_modules/@anthropic/claude-code/package.json | grep -m1 -oE '[0-9]+\.[0-9]+\.[0-9]+')
            elif [[ -f "$HOME/.npm-global/lib/node_modules/@anthropic/claude-code/package.json" ]]; then
                current_version=$(grep '"version"' "$HOME/.npm-global/lib/node_modules/@anthropic/claude-code/package.json" | grep -m1 -oE '[0-9]+\.[0-9]+\.[0-9]+')
            fi
        fi

        if [[ -n "$current_version" ]]; then
            if version_compare "$current_version" "$min_version"; then
                status="ok"
            else
                status="outdated"
            fi
        else
            status="unknown"
        fi
    else
        status="not-found"
    fi

    echo "CLAUDE_CODE_VERSION=${current_version:-unknown}"
    echo "CLAUDE_CODE_STATUS=$status"
    echo "CLAUDE_CODE_MINIMUM=$min_version"
}

# Command: detect-providers
# [EXTRACTED to lib/preflight.sh]


# [EXTRACTED to lib/smoke.sh] load_providers_config


# [EXTRACTED to lib/cost.sh] get_cost_tier_for_subscription()

# [EXTRACTED to lib/smoke.sh] auto_detect_provider_config, detect_tier_openai, detect_tier_gemini, detect_tier_claude
# [EXTRACTED to lib/smoke.sh] save_providers_config, score_provider, select_provider, tier_cache_valid
# [EXTRACTED to lib/smoke.sh] tier_cache_read, tier_cache_write, tier_cache_invalidate


# Enhanced agent availability check including OpenRouter
# [EXTRACTED to lib/providers.sh]
# Functions: get_openrouter_model, execute_openrouter
# [EXTRACTED to lib/perplexity.sh] openrouter_execute(), openrouter_execute_model(), perplexity_execute()

# [EXTRACTED to lib/smoke.sh] show_provider_status


# Load user configuration from file
load_user_config() {
    if [[ ! -f "$USER_CONFIG_FILE" ]]; then
        [[ "$VERBOSE" == "true" ]] && log DEBUG "No user config found at $USER_CONFIG_FILE" || true
        return 0
    fi

    # Parse YAML-like config using grep/sed (bash 3.x compatible)
    USER_INTENT_PRIMARY=$(grep "^  primary:" "$USER_CONFIG_FILE" 2>/dev/null | sed 's/.*: *//' | tr -d '"' || echo "")
    USER_INTENT_ALL=$(grep "^  all:" "$USER_CONFIG_FILE" 2>/dev/null | sed 's/.*: *//' | tr -d '[]"' || echo "")
    USER_RESOURCE_TIER=$(grep "^resource_tier:" "$USER_CONFIG_FILE" 2>/dev/null | sed 's/.*: *//' | tr -d '"' || echo "standard")
    USER_HAS_OPENAI=$(grep "^  openai:" "$USER_CONFIG_FILE" 2>/dev/null | sed 's/.*: *//' || echo "false")
    USER_HAS_GEMINI=$(grep "^  gemini:" "$USER_CONFIG_FILE" 2>/dev/null | sed 's/.*: *//' || echo "false")
    USER_OPUS_BUDGET=$(grep "^  opus_budget:" "$USER_CONFIG_FILE" 2>/dev/null | sed 's/.*: *//' | tr -d '"' || echo "balanced")
    KNOWLEDGE_WORK_MODE=$(grep "^knowledge_work_mode:" "$USER_CONFIG_FILE" 2>/dev/null | sed 's/.*: *//' | tr -d '"' || echo "false")

    [[ "$VERBOSE" == "true" ]] && log DEBUG "Loaded user config: tier=$USER_RESOURCE_TIER, intent=$USER_INTENT_PRIMARY, knowledge_mode=$KNOWLEDGE_WORK_MODE" || true
}

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIG HOT-RELOAD (v8.32.0)
# Reads config-reload-signal written by ConfigChange hook (v2.1.49+)
# Call at workflow entry points to pick up setting changes mid-session
# ═══════════════════════════════════════════════════════════════════════════════

check_config_reload() {
    [[ "$SUPPORTS_CONFIG_CHANGE_HOOK" != "true" ]] && return 0

    local signal_file="${HOME}/.claude-octopus/.config-reload-signal"
    [[ ! -f "$signal_file" ]] && return 0

    local signal_time
    signal_time=$(cat "$signal_file" 2>/dev/null) || return 0

    # Consume the signal (remove file so we don't reload again)
    rm -f "$signal_file" 2>/dev/null || true

    log "INFO" "Config change detected at $signal_time — reloading user config"
    load_user_config
    return 0
}

# Save user configuration to file
save_user_config() {
    local intent_primary="$1"
    local intent_all="$2"
    local resource_tier="$3"
    local knowledge_mode="${4:-false}"

    mkdir -p "$(dirname "$USER_CONFIG_FILE")"

    # Auto-detect available API keys (check OAuth first, then API keys)
    local has_openai="false"
    local has_gemini="false"
    [[ -f "$HOME/.codex/auth.json" || -n "${OPENAI_API_KEY:-}" ]] && has_openai="true"
    [[ -f "$HOME/.gemini/oauth_creds.json" || -n "${GEMINI_API_KEY:-}" ]] && has_gemini="true"

    # Derive settings based on resource tier
    local opus_budget="balanced"
    local default_complexity=2
    case "$resource_tier" in
        pro) opus_budget="conservative"; default_complexity=1 ;;
        max-5x) opus_budget="balanced"; default_complexity=2 ;;
        max-20x) opus_budget="unlimited"; default_complexity=2 ;;
        api-only) opus_budget="conservative"; default_complexity=1 ;;
        *) opus_budget="balanced"; default_complexity=2 ;;
    esac

    cat > "$USER_CONFIG_FILE" << EOF
version: "1.1"
created_at: "$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)"
updated_at: "$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)"

# User intent - affects persona selection and task routing
intent:
  primary: "$intent_primary"
  all: [$intent_all]

# Resource tier - affects model selection
resource_tier: "$resource_tier"

# Knowledge Work Mode (v6.0) - prioritizes research/consulting/writing workflows
knowledge_work_mode: "$knowledge_mode"

# Available API keys (auto-detected)
available_keys:
  openai: $has_openai
  gemini: $has_gemini

# Derived settings (auto-configured based on tier + keys)
settings:
  opus_budget: "$opus_budget"
  default_complexity: $default_complexity
  prefer_gemini_for_analysis: $has_gemini
  max_parallel_agents: 3
EOF

    log INFO "User config saved to $USER_CONFIG_FILE"
}

# Map intent number to name
get_intent_name() {
    local num="$1"
    case "$num" in
        1) echo "backend" ;;
        2) echo "frontend" ;;
        3) echo "fullstack" ;;
        4) echo "ux-research" ;;
        5) echo "ux-ui-researcher" ;;
        6) echo "ui-design" ;;
        7) echo "devops" ;;
        8) echo "data" ;;
        9) echo "seo" ;;
        10) echo "security" ;;
        # v6.0: Knowledge worker intents
        11) echo "strategy-consulting" ;;
        12) echo "academic-research" ;;
        13) echo "product-management" ;;
        0) echo "general" ;;
        *) echo "general" ;;
    esac
}

# Get default persona based on user intent
get_intent_persona() {
    local intent="$1"
    case "$intent" in
        backend|devops) echo "backend-architect" ;;
        frontend) echo "frontend-architect" ;;
        security) echo "security-auditor" ;;
        ux-research|ux-ui-researcher|data) echo "researcher" ;;
        ui-design) echo "designer" ;;
        strategy-consulting) echo "strategy-analyst" ;;
        academic-research) echo "research-synthesizer" ;;
        product-management) echo "product-writer" ;;
        *) echo "" ;;
    esac
}

# Adjust complexity tier based on resource budget
get_resource_adjusted_tier() {
    local base_complexity="$1"

    # Load config if not already loaded
    [[ -z "$USER_RESOURCE_TIER" || "$USER_RESOURCE_TIER" == "standard" ]] && load_user_config

    case "$USER_RESOURCE_TIER" in
        pro|api-only)
            # Conservative: cap at standard tier
            if [[ "$base_complexity" -ge 3 ]]; then
                echo 2
            else
                echo 1
            fi
            ;;
        max-5x)
            # Balanced: use as-is
            echo "$base_complexity"
            ;;
        max-20x)
            # Unlimited: can boost to premium
            echo "$base_complexity"
            ;;
        *)
            # Default: use as-is
            echo "$base_complexity"
            ;;
    esac
}

# Check if an agent is available based on API keys
is_agent_available() {
    local agent="$1"

    # Load config if needed
    [[ -z "$USER_HAS_OPENAI" ]] && load_user_config

    case "$agent" in
        codex|codex-standard|codex-mini|codex-max)
            [[ "$USER_HAS_OPENAI" == "true" || -n "${OPENAI_API_KEY:-}" ]]
            ;;
        gemini|gemini-fast|gemini-image)
            [[ "$USER_HAS_GEMINI" == "true" || -f "$HOME/.gemini/oauth_creds.json" || -n "${GEMINI_API_KEY:-}" ]]
            ;;
        *)
            return 0  # Unknown agents assumed available
            ;;
    esac
}

# Get fallback agent when preferred is unavailable

# Step 6: Mode selection (Dev Work vs Knowledge Work)
init_step_mode_selection() {
    echo ""
    echo -e "${YELLOW}Step 6/8: Choose your primary work mode${NC}"
    echo ""
    echo -e "  ${GREEN}[1]${NC} Dev Work Mode 🔧"
    echo -e "      ${DIM}For:${NC} Software development, code review, debugging"
    echo -e "      ${DIM}Examples:${NC} Building APIs, fixing bugs, implementing features"
    echo ""
    echo -e "  ${GREEN}[2]${NC} Knowledge Work Mode 🎓"
    echo -e "      ${DIM}For:${NC} Research, UX analysis, strategy, writing"
    echo -e "      ${DIM}Examples:${NC} User research, literature reviews, market analysis"
    echo ""
    echo -e "  ${DIM}Note: Both modes use Codex + Gemini - only personas differ${NC}"
    echo -e "  ${DIM}Switch anytime with /octo:dev or /octo:km${NC}"
    echo ""
    read -p "  Choose mode [1-2] (default: 1): " mode_choice

    case "$mode_choice" in
        2)
            INITIAL_KNOWLEDGE_MODE="true"
            echo -e "  ${GREEN}✓${NC} Knowledge Work Mode selected"
            ;;
        1|"")
            INITIAL_KNOWLEDGE_MODE="false"
            echo -e "  ${GREEN}✓${NC} Dev Work Mode selected (default)"
            ;;
        *)
            echo -e "  ${YELLOW}Invalid choice, using default: Dev Work Mode${NC}"
            INITIAL_KNOWLEDGE_MODE="false"
            ;;
    esac
}

# Step 7: User intent selection
init_step_intent() {
    echo ""
    echo -e "${YELLOW}Step 7/8: What brings you to the octopus's lair?${NC}"
    echo -e "  ${CYAN}Select your primary use case(s) - this helps us choose the best agents${NC}"
    echo ""
    echo -e "  ${MAGENTA}━━━ Development ━━━${NC}"
    echo -e "  ${GREEN}[1]${NC} Backend Development       ${CYAN}(APIs, databases, microservices)${NC}"
    echo -e "  ${GREEN}[2]${NC} Frontend Development      ${CYAN}(React, Vue, UI components)${NC}"
    echo -e "  ${GREEN}[3]${NC} Full-Stack Development    ${CYAN}(both frontend + backend)${NC}"
    echo -e "  ${GREEN}[7]${NC} DevOps/Infrastructure     ${CYAN}(CI/CD, Docker, Kubernetes)${NC}"
    echo -e "  ${GREEN}[8]${NC} Data/Analytics            ${CYAN}(SQL, pipelines, ML)${NC}"
    echo -e "  ${GREEN}[10]${NC} Code Review/Security     ${CYAN}(audits, vulnerability scanning)${NC}"
    echo ""
    echo -e "  ${MAGENTA}━━━ Design ━━━${NC}"
    echo -e "  ${GREEN}[4]${NC} UX Research               ${CYAN}(user research, personas, journey maps)${NC}"
    echo -e "  ${GREEN}[5]${NC} Researcher UX/UI Design   ${CYAN}(combined research + design)${NC}"
    echo -e "  ${GREEN}[6]${NC} UI/Product Design         ${CYAN}(wireframes, design systems)${NC}"
    echo -e "  ${GREEN}[9]${NC} SEO/Marketing             ${CYAN}(content, optimization)${NC}"
    echo ""
    echo -e "  ${MAGENTA}━━━ Knowledge Work (v6.0) ━━━${NC}"
    echo -e "  ${GREEN}[11]${NC} Strategy/Consulting      ${CYAN}(market analysis, business cases, frameworks)${NC}"
    echo -e "  ${GREEN}[12]${NC} Academic Research        ${CYAN}(literature review, synthesis, papers)${NC}"
    echo -e "  ${GREEN}[13]${NC} Product Management       ${CYAN}(PRDs, user stories, acceptance criteria)${NC}"
    echo ""
    echo -e "  ${GREEN}[0]${NC} General/All of above"
    echo ""
    read -p "  Enter choices (e.g., '1,2,7' or '0' for all): " intent_choices

    # Parse choices
    intent_choices="${intent_choices:-0}"
    intent_choices=$(echo "$intent_choices" | tr -d ' ')

    local intent_names=""
    local first_intent=""
    IFS=',' read -ra CHOICES <<< "$intent_choices"
    for choice in "${CHOICES[@]}"; do
        local name
        name=$(get_intent_name "$choice")
        if [[ -z "$first_intent" ]]; then
            first_intent="$name"
        fi
        if [[ -z "$intent_names" ]]; then
            intent_names="\"$name\""
        else
            intent_names="$intent_names, \"$name\""
        fi
    done

    USER_INTENT_PRIMARY="$first_intent"
    USER_INTENT_ALL="$intent_names"

    echo ""
    echo -e "  ${GREEN}✓${NC} Selected: $intent_names"
    if [[ -n "$first_intent" && "$first_intent" != "general" ]]; then
        local persona
        persona=$(get_intent_persona "$first_intent")
        if [[ -n "$persona" ]]; then
            echo -e "  ${GREEN}✓${NC} Default persona: $persona"
        fi
    fi
}

# Step 7: Resource tier selection
init_step_resources() {
    echo ""
    echo -e "${YELLOW}Step 7/7: How much tentacle power do you have?${NC}"
    echo -e "  ${CYAN}This helps us balance quality vs. cost${NC}"
    echo ""
    echo -e "  ${GREEN}[1]${NC} Claude Pro or Free     ${CYAN}(\$0-20/mo)${NC} → Conservative mode"
    echo -e "      ${CYAN}Uses cheaper models by default, saves Opus for complex tasks${NC}"
    echo ""
    echo -e "  ${GREEN}[2]${NC} Claude Max 5x          ${CYAN}(\$100/mo)${NC} → Balanced mode"
    echo -e "      ${CYAN}Smart Opus usage, weekly budget awareness${NC}"
    echo ""
    echo -e "  ${GREEN}[3]${NC} Claude Max 20x         ${CYAN}(\$200/mo)${NC} → Full power mode"
    echo -e "      ${CYAN}Use premium models freely based on task complexity${NC}"
    echo ""
    echo -e "  ${GREEN}[4]${NC} API Only (pay-per-token) → Cost-aware mode"
    echo -e "      ${CYAN}Tracks token costs, prefers efficient models${NC}"
    echo ""
    echo -e "  ${GREEN}[5]${NC} Not sure / Skip        → Standard defaults"
    echo ""
    read -p "  Select [1-5]: " tier_choice

    case "${tier_choice:-5}" in
        1) USER_RESOURCE_TIER="pro" ;;
        2) USER_RESOURCE_TIER="max-5x" ;;
        3) USER_RESOURCE_TIER="max-20x" ;;
        4) USER_RESOURCE_TIER="api-only" ;;
        *) USER_RESOURCE_TIER="standard" ;;
    esac

    echo ""
    case "$USER_RESOURCE_TIER" in
        pro)
            echo -e "  ${GREEN}✓${NC} Conservative mode: Prioritizing cost-efficient models"
            echo -e "  ${CYAN}  Codex-mini for simple tasks, standard for complex${NC}"
            ;;
        max-5x)
            echo -e "  ${GREEN}✓${NC} Balanced mode: Smart model selection"
            echo -e "  ${CYAN}  Full Opus access for complex tasks, efficient for simple${NC}"
            ;;
        max-20x)
            echo -e "  ${GREEN}✓${NC} Full power mode: Premium models available"
            echo -e "  ${CYAN}  All 8 tentacles at full strength!${NC}"
            ;;
        api-only)
            echo -e "  ${GREEN}✓${NC} Cost-aware mode: Token tracking active"
            echo -e "  ${CYAN}  Monitoring costs and preferring efficient models${NC}"
            ;;
        *)
            echo -e "  ${GREEN}✓${NC} Standard mode: Balanced defaults"
            ;;
    esac
}

# Reconfigure preferences only
reconfigure_preferences() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     🐙 Claude Octopus Configuration Wizard 🐙                 ║${NC}"
    echo -e "${CYAN}║     Update your preferences without full setup                ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"

    # Load existing config
    load_user_config

    # Show current settings
    if [[ -n "$USER_INTENT_PRIMARY" ]]; then
        echo ""
        echo -e "  Current settings:"
        echo -e "    Mode: $([ "$KNOWLEDGE_WORK_MODE" = "true" ] && echo "Knowledge Work" || echo "Dev Work")"
        echo -e "    Intent: $USER_INTENT_PRIMARY ($USER_INTENT_ALL)"
        echo -e "    Resource tier: $USER_RESOURCE_TIER"
        echo ""
    fi

    # Run just the preference steps
    init_step_mode_selection
    init_step_intent
    init_step_resources

    # Save updated config
    save_user_config "$USER_INTENT_PRIMARY" "$USER_INTENT_ALL" "$USER_RESOURCE_TIER" "$INITIAL_KNOWLEDGE_MODE"

    echo ""
    echo -e "${GREEN}✓${NC} Configuration updated!"
    echo -e "  Config saved to: $USER_CONFIG_FILE"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# v3.0 FEATURE: AUTONOMY MODE HANDLER
# Controls human oversight level during workflow execution
# ═══════════════════════════════════════════════════════════════════════════════

handle_autonomy_checkpoint() {
    local phase="$1"
    local status="$2"

    # Claude Code v2.1.9: CI mode forces autonomous behavior
    if [[ "$CI_MODE" == "true" ]]; then
        if [[ "$status" == "failed" ]]; then
            log ERROR "CI mode: Phase $phase failed - aborting"
            echo "::error::Phase $phase failed with status: $status"
            exit 1
        fi
        log INFO "CI mode: Auto-continuing after phase $phase (status: $status)"
        return 0
    fi

    case "$AUTONOMY_MODE" in
        "supervised")
            echo ""
            echo -e "${YELLOW}${_BOX_TOP}${NC}"
            echo -e "${YELLOW}║  Supervised Mode - Human Approval Required                ║${NC}"
            echo -e "${YELLOW}${_BOX_BOT}${NC}"
            echo -e "Phase ${CYAN}$phase${NC} completed with status: ${GREEN}$status${NC}"
            echo ""
            read -p "Continue to next phase? (y/n) " -n 1 -r
            echo ""
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log INFO "User chose to stop workflow after $phase phase"
                exit 0
            fi
            ;;
        "semi-autonomous")
            if [[ "$status" == "failed" || "$status" == "warning" ]]; then
                echo ""
                echo -e "${YELLOW}${_BOX_TOP}${NC}"
                echo -e "${YELLOW}║  Quality Gate Issue - Review Required                     ║${NC}"
                echo -e "${YELLOW}${_BOX_BOT}${NC}"
                echo -e "Phase ${CYAN}$phase${NC} has status: ${RED}$status${NC}"
                echo ""
                read -p "Continue anyway? (y/n) " -n 1 -r
                echo ""
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    log ERROR "User chose to abort due to quality gate $status"
                    exit 1
                fi
            fi
            ;;
        "loop-until-approved")
            # Handled in quality gate logic - LOOP_UNTIL_APPROVED flag
            ;;
        "autonomous"|*)
            # Always continue without prompts
            log DEBUG "Autonomy mode: continuing automatically"
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════
# v3.0 FEATURE: SESSION RECOVERY
# Save/restore workflow state for resuming interrupted workflows
# ═══════════════════════════════════════════════════════════════════════════════

# [EXTRACTED to lib/session.sh] generate_session_name, init_session,
# save_session_checkpoint, check_resume_session, get_resume_phase, get_phase_output, complete_session




# ═══════════════════════════════════════════════════════════════════════════════
# SECURITY: Safe JSON field extraction with validation
# Returns empty string on failure, logs errors
# ═══════════════════════════════════════════════════════════════════════════════

# Validate agent type against allowlist




# ═══════════════════════════════════════════════════════════════════════════════
# SETUP WIZARD - Interactive first-time setup
# Guides users through CLI installation and API key configuration
# ═══════════════════════════════════════════════════════════════════════════════

# Config file for storing setup state
SETUP_CONFIG_FILE="$WORKSPACE_DIR/.setup-complete"

# Open URL in default browser (cross-platform)
# [EXTRACTED to lib/utils.sh]
# Functions: open_browser, get_tool_description, is_tool_installed, get_install_command, install_tool

# [EXTRACTED to lib/config-display.sh] setup_wizard, show_config_summary,
# check_first_run, preflight_cache_valid, preflight_cache_write, preflight_cache_read,
# preflight_cache_invalidate, check_codex_auth_freshness


# [EXTRACTED to lib/smoke.sh] smoke_test_cache_key, smoke_test_cache_valid, smoke_test_cache_write, _classify_smoke_error
# [EXTRACTED to lib/smoke.sh] _display_smoke_test_error, _smoke_test_provider, provider_smoke_test


# Pre-flight dependency validation
# [EXTRACTED to lib/preflight.sh]


# v8.13.0: One-command release cycle
do_release() {
    local version
    version=$(jq -r '.version' "$SCRIPT_DIR/../.claude-plugin/plugin.json")
    local tag="v$version"

    echo -e "${MAGENTA}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}  Claude Octopus Release: $tag${NC}"
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════════${NC}"

    # Step 1: Validate
    echo -e "\n${BLUE}Step 1: Validating...${NC}"
    bash "$SCRIPT_DIR/validate-release.sh" || { echo "Validation failed"; return 1; }

    # Step 2: Ensure tag exists and points to HEAD
    echo -e "\n${BLUE}Step 2: Tagging...${NC}"
    local head_sha
    head_sha=$(git rev-parse HEAD)
    local tag_sha
    tag_sha=$(git rev-list -n 1 "$tag" 2>/dev/null || echo "")
    if [[ "$tag_sha" != "$head_sha" ]]; then
        git tag -d "$tag" 2>/dev/null || true
        git tag "$tag"
        echo -e "${GREEN}✓ Tag $tag -> $(git rev-parse --short HEAD)${NC}"
    else
        echo -e "${GREEN}✓ Tag $tag already at HEAD${NC}"
    fi

    # Step 3: Pull --rebase to incorporate any remote changes
    echo -e "\n${BLUE}Step 3: Syncing with remote...${NC}"
    git fetch origin main --tags 2>/dev/null
    git rebase origin/main 2>/dev/null || {
        echo -e "${RED}Rebase conflict. Resolve manually, then re-run.${NC}"
        return 1
    }

    # Step 4: Re-tag after rebase (HEAD may have changed)
    local new_head
    new_head=$(git rev-parse HEAD)
    if [[ "$new_head" != "$head_sha" ]]; then
        git tag -d "$tag" 2>/dev/null || true
        git tag "$tag"
        echo -e "${GREEN}✓ Re-tagged after rebase: $tag -> $(git rev-parse --short HEAD)${NC}"
    fi

    # Step 5: Push tag (force, to handle existing remote tags)
    echo -e "\n${BLUE}Step 4: Pushing tag...${NC}"
    git push origin "$tag" --force --no-verify 2>/dev/null
    echo -e "${GREEN}✓ Tag pushed${NC}"

    # Step 6: Push main
    echo -e "\n${BLUE}Step 5: Pushing main...${NC}"
    git push origin main --no-verify
    echo -e "${GREEN}✓ Branch pushed${NC}"

    echo -e "\n${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  ✅ Released $tag${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
}

# [EXTRACTED to lib/doctor.sh]

# [EXTRACTED to lib/agent-sync.sh]

# ═══════════════════════════════════════════════════════════════════════════════
# WORKFLOW-AS-CODE RUNTIME (v8.5)

# [EXTRACTED to lib/yaml-workflow.sh] parse_yaml_workflow, yaml_get_phases,
# yaml_get_phase_config, yaml_get_phase_agents, yaml_get_agent_prompt,
# resolve_prompt_template, execute_workflow_phase, run_yaml_workflow

# v8.54.0: Single-agent probe for multi-agentic skill dispatch
# [EXTRACTED to lib/workflows.sh] — probe_single_agent

# ═══════════════════════════════════════════════════════════════════════════════
# v9.2.0: Smart Dispatch — choose provider count based on task analysis
# ═══════════════════════════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════════════════════════
# v9.2.0: Blind Spot Library — inject commonly-missed perspectives
# ═══════════════════════════════════════════════════════════════════════════════

# [EXTRACTED to lib/workflows.sh] — probe_discover

# Synthesize probe results into insights

# [EXTRACTED to lib/workflows.sh] — grasp_define

# [EXTRACTED to lib/workflows.sh] — tangle_develop

# [EXTRACTED to lib/testing.sh] — validate_tangle_results

# [EXTRACTED to lib/workflows.sh] — ink_deliver

# EMBRACE - Full 4-phase Double Diamond workflow
# The octopus embraces the entire problem with all tentacles
# v3.0: Supports session recovery, autonomy checkpoints
# v8.3: Event-driven phase transitions via TeammateIdle/TaskCompleted hooks

# ═══════════════════════════════════════════════════════════════════════════
# DARK FACTORY MODE — Spec-in, software-out autonomous pipeline (v8.25.0)
# Issue #37: E19 (Scenario Holdout) + E21 (Satisfaction Scoring) + E22 (Factory)
# ═══════════════════════════════════════════════════════════════════════════




# [EXTRACTED to lib/factory.sh]

# [EXTRACTED to lib/factory-spec.sh]



# [EXTRACTED to lib/factory.sh]

# [EXTRACTED to lib/debate.sh] — grapple_debate
# [EXTRACTED to lib/testing.sh] — squeeze_test

# ═══════════════════════════════════════════════════════════════════════════════
# SENTINEL - GitHub-Aware Work Monitor (v8.18.0)
# Triages issues, PRs, and CI failures without auto-executing workflows
# ═══════════════════════════════════════════════════════════════════════════════

# [EXTRACTED to lib/sentinel.sh]


sentinel_watch() {
    if [[ "$OCTOPUS_SENTINEL_ENABLED" != "true" ]]; then
        log ERROR "Sentinel is disabled. Set OCTOPUS_SENTINEL_ENABLED=true to enable."
        return 1
    fi

    echo -e "${CYAN}🔭 Sentinel watching (interval: ${OCTOPUS_SENTINEL_INTERVAL}s)${NC}"
    echo -e "${CYAN}   Press Ctrl+C to stop${NC}"
    echo ""

    while true; do
        sentinel_tick
        sleep "$OCTOPUS_SENTINEL_INTERVAL"
    done
}

# ═══════════════════════════════════════════════════════════════════════════════
# KNOWLEDGE WORKER WORKFLOWS (v6.0)
# New tentacles for researchers, consultants, and product designers
# ═══════════════════════════════════════════════════════════════════════════════

# [EXTRACTED to lib/research.sh]

# [EXTRACTED to lib/research.sh]


# [EXTRACTED to lib/config-display.sh] update_knowledge_mode_config, show_document_skills_info,
# update_intent_config, update_resource_tier_config, toggle_knowledge_work_mode


show_status() {
    echo ""
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}  Claude Octopus Status${NC}"
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    load_user_config 2>/dev/null || true
    case "$KNOWLEDGE_WORK_MODE" in
        true|on)
            echo -e "${BLUE}Mode:${NC} ${MAGENTA}Knowledge Work${NC} 🎓 (forced)"
            ;;
        false|off)
            echo -e "${BLUE}Mode:${NC} ${GREEN}Development${NC} 💻 (forced)"
            ;;
        *)
            echo -e "${BLUE}Mode:${NC} ${YELLOW}Auto-Detect${NC} 🐙 (v7.8+)"
            ;;
    esac
    echo -e "  ${DIM}Change with:${NC} km on | km off | km auto"
    echo ""

    show_provider_status

    if [[ ! -f "$PID_FILE" ]]; then
        echo -e "${YELLOW}No agents tracked. Workspace may need initialization.${NC}"
        echo "Run: $(basename "$0") init"
        return
    fi

    local running=0
    local total=0

    echo -e "${BLUE}Active Agents:${NC}"
    while IFS=: read -r pid agent task_id; do
        ((total++)) || true
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "  ${GREEN}●${NC} PID $pid - $agent ($task_id) - RUNNING"
            ((running++)) || true
        else
            echo -e "  ${RED}○${NC} PID $pid - $agent ($task_id) - COMPLETED"
        fi
    done < "$PID_FILE"

    echo ""
    echo -e "${BLUE}Summary:${NC} $running running / $total total"
    echo ""

    if [[ -d "$RESULTS_DIR" ]]; then
        local result_count
        result_count=$(find "$RESULTS_DIR" -name "*.md" -type f | wc -l | tr -d ' ')
        echo -e "${BLUE}Results:${NC} $result_count files in $RESULTS_DIR"
    fi

    # v8.14.0: Show persistent project state
    if [[ -f ".claude-octopus/state.json" ]]; then
        echo ""
        echo -e "${BLUE}Project State:${NC}"
        local wf ph pc dc ab
        wf=$(jq -r '.current_workflow // "none"' .claude-octopus/state.json 2>/dev/null)
        ph=$(jq -r '.current_phase // "none"' .claude-octopus/state.json 2>/dev/null)
        pc=$(jq -r '.metrics.phases_completed // 0' .claude-octopus/state.json 2>/dev/null)
        dc=$(jq -r '.decisions | length // 0' .claude-octopus/state.json 2>/dev/null)
        echo -e "  Workflow: ${CYAN}${wf}${NC} | Phase: ${CYAN}${ph}${NC}"
        echo -e "  Phases completed: $pc | Decisions: $dc"
        ab=$(jq -r '[.blockers[] | select(.status == "active")] | length // 0' .claude-octopus/state.json 2>/dev/null)
        if [[ "$ab" -gt 0 ]] 2>/dev/null; then
            echo -e "  ${YELLOW}Active blockers: $ab${NC}"
        fi
    fi

    # Recent debates (v8.13.0)
    local debate_base="$HOME/.claude-octopus/debates"
    if [[ -d "$debate_base" ]]; then
        local recent_debates
        recent_debates=$(find "$debate_base" -name "synthesis.md" -mtime -7 2>/dev/null | head -5)
        if [[ -n "$recent_debates" ]]; then
            echo ""
            echo -e "${BLUE}Recent Debates (7 days):${NC}"
            while IFS= read -r synth_file; do
                local debate_dir
                debate_dir=$(dirname "$synth_file")
                local topic
                topic=$(basename "$debate_dir")
                local date
                date=$(stat -f "%Sm" -t "%Y-%m-%d" "$synth_file" 2>/dev/null || date -r "$synth_file" "+%Y-%m-%d" 2>/dev/null || echo "unknown")
                echo -e "  ✓ $topic ($date)"
            done <<< "$recent_debates"
        fi
    fi

    echo ""
}

kill_agents() {
    local target="${1:-}"

    if [[ ! -f "$PID_FILE" ]]; then
        log WARN "No PID file found"
        return
    fi

    if [[ "$target" == "all" || -z "$target" ]]; then
        log INFO "Killing all tracked agents..."
        while IFS=: read -r pid agent task_id; do
            if kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null && log INFO "Killed $agent ($pid)"
            fi
        done < "$PID_FILE"
        > "$PID_FILE"
    else
        log INFO "Killing agent: $target"
        while IFS=: read -r pid agent task_id; do
            if [[ "$pid" == "$target" || "$task_id" == "$target" ]]; then
                kill "$pid" 2>/dev/null && log INFO "Killed $agent ($pid)"
            fi
        done < "$PID_FILE"
    fi
}

clean_workspace() {
    log WARN "Cleaning workspace and killing all agents..."

    kill_agents "all"

    if [[ -d "$WORKSPACE_DIR" ]]; then
        rm -rf "${WORKSPACE_DIR:?}/results" "${WORKSPACE_DIR:?}/logs" "$PID_FILE"
        mkdir -p "$RESULTS_DIR" "$LOGS_DIR"
        log INFO "Workspace cleaned"
    fi
}

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--parallel) MAX_PARALLEL="$2"; shift 2 ;;
        -t|--timeout) TIMEOUT="$2"; shift 2 ;;
        -v|--verbose) VERBOSE=true; shift ;;
        --debug) OCTOPUS_DEBUG=true; VERBOSE=true; shift ;;  # v7.25.0: Debug mode
        -n|--dry-run) DRY_RUN=true; shift ;;
        -d|--dir) PROJECT_ROOT="$2"; shift 2 ;;
        -a|--autonomy) AUTONOMY_MODE="$2"; shift 2 ;;
        -q|--quality) QUALITY_THRESHOLD="$2"; shift 2 ;;
        -l|--loop) LOOP_UNTIL_APPROVED=true; shift ;;
        -R|--resume) RESUME_SESSION=true; shift ;;
        -Q|--quick) FORCE_TIER="trivial"; shift ;;
        -P|--premium) FORCE_TIER="premium"; shift ;;
        --tier) FORCE_TIER="$2"; shift 2 ;;
        --branch) FORCE_BRANCH="$2"; shift 2 ;;
        --on-fail) ON_FAIL_ACTION="$2"; shift 2 ;;
        --no-personas) DISABLE_PERSONAS=true; shift ;;
        --skip-smoke-test) SKIP_SMOKE_TEST=true; shift ;;
        --ci) CI_MODE=true; AUTONOMY_MODE="autonomous"; shift ;;
        # Multi-provider routing flags (v4.8)
        --provider) FORCE_PROVIDER="$2"; shift 2 ;;
        --cost-first) FORCE_COST_FIRST=true; shift ;;
        --quality-first) FORCE_QUALITY_FIRST=true; shift ;;
        --openrouter-nitro) OPENROUTER_ROUTING_OVERRIDE=":nitro"; shift ;;
        --openrouter-floor) OPENROUTER_ROUTING_OVERRIDE=":floor"; shift ;;
        # Async and tmux visualization flags
        --async) ASYNC_MODE=true; shift ;;
        --no-async) ASYNC_MODE=false; shift ;;
        --tmux) TMUX_MODE=true; ASYNC_MODE=true; shift ;;
        --no-tmux) TMUX_MODE=false; shift ;;
        -h|--help) usage "$@" ;;
        *) break ;;
    esac
done

# Initialize CI mode from environment (v4.4)
init_ci_mode

# Detect Claude Code version for v2.1.12+ features (v7.12.0)
detect_claude_code_version 2>/dev/null || true

# Validate Claude Code task integration features (v7.16.0)
validate_claude_code_task_features 2>/dev/null || true

# Check UX feature dependencies (v7.16.0)
check_ux_dependencies 2>/dev/null || true

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION ENTRY POINT
# ═══════════════════════════════════════════════════════════════════════════════
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Cleanup old progress files (v7.16.0)
    cleanup_old_progress_files 2>/dev/null || true

    # Handle autonomy mode aliases
    if [[ "$AUTONOMY_MODE" == "loop-until-approved" ]]; then
        LOOP_UNTIL_APPROVED=true
    fi

    # Main command dispatch
    COMMAND="${1:-help}"
    shift || true

# Check for first-run on commands that need setup (skip for help/setup/preflight)
if [[ "$COMMAND" != "help" && "$COMMAND" != "setup" && "$COMMAND" != "preflight" && "$COMMAND" != "-h" && "$COMMAND" != "--help" ]]; then
    check_first_run || true  # Show hint but don't block
fi

# Initialize usage tracking for cost reporting (v4.1)
# Skip for cost/usage commands that just read existing data
if [[ "$COMMAND" != "cost" && "$COMMAND" != "usage" && "$COMMAND" != "cost-json" && "$COMMAND" != "cost-csv" && "$COMMAND" != "cost-clear" && "$COMMAND" != "help" ]]; then
    init_usage_tracking 2>/dev/null || true
    init_metrics_tracking 2>/dev/null || true  # v7.25.0: Enhanced metrics
fi

# Initialize state management (v7.17.0)
# Skip for help and non-workflow commands
if [[ "$COMMAND" != "help" && "$COMMAND" != "setup" && "$COMMAND" != "preflight" && "$COMMAND" != "cost" && "$COMMAND" != "usage" && "$COMMAND" != "-h" && "$COMMAND" != "--help" ]]; then
    init_state 2>/dev/null || true

    # v8.29.0: Check if ConfigChange hook signaled settings were modified
    RELOAD_SIGNAL="${HOME}/.claude-octopus/.config-reload-signal"
    if [[ -f "$RELOAD_SIGNAL" ]]; then
        log "INFO" "ConfigChange detected — settings reloaded from environment"
        rm -f "$RELOAD_SIGNAL"
    fi

    # v8.21.0: Auto-load persona packs from standard paths
    if type auto_load_persona_packs &>/dev/null 2>&1; then
        auto_load_persona_packs 2>/dev/null || true
    fi
fi

case "$COMMAND" in
    # ═══════════════════════════════════════════════════════════════════════════
    # DOUBLE DIAMOND COMMANDS (with intuitive aliases)
    # ═══════════════════════════════════════════════════════════════════════════
    discover|research|probe)
        # Phase 1: Discover - Parallel exploration
        # Handle help flag
        if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
            usage discover
            exit 0
        fi
        if [[ $# -lt 1 ]]; then
            log ERROR "Missing prompt for discover phase"
            echo "Usage: $(basename "$0") discover <prompt>"
            echo "Example: $(basename "$0") discover \"What are best practices for API caching?\""
            exit 1
        fi
        probe_discover "$*"
        ;;
    probe-single)
        # v8.54.0: Single-agent probe for multi-agentic skill dispatch
        # Called by Claude's Agent tool (one per perspective) instead of monolithic probe
        if [[ $# -lt 3 ]]; then
            echo "Usage: $(basename "$0") probe-single <agent_type> <perspective> <task_id> [original_prompt]"
            exit 1
        fi
        probe_single_agent "$1" "$2" "$3" "${4:-}"
        ;;
    define|grasp)
        # Phase 2: Define - Consensus building
        # Handle help flag
        if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
            usage define
            exit 0
        fi
        if [[ $# -lt 1 ]]; then
            log ERROR "Missing prompt for define phase"
            echo "Usage: $(basename "$0") define <prompt> [research-results-file]"
            echo "Example: $(basename "$0") define \"implement caching layer\""
            exit 1
        fi
        grasp_define "$1" "${2:-}"
        ;;
    develop|tangle)
        # Phase 3: Develop - Implementation with quality gates
        # Handle help flag
        if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
            usage develop
            exit 0
        fi
        if [[ $# -lt 1 ]]; then
            log ERROR "Missing prompt for develop phase"
            echo "Usage: $(basename "$0") develop <prompt> [define-results-file]"
            echo "Example: $(basename "$0") develop \"build the caching API\""
            exit 1
        fi
        tangle_develop "$1" "${2:-}"
        ;;
    deliver|ink)
        # Phase 4: Deliver - Final validation
        # Handle help flag
        if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
            usage deliver
            exit 0
        fi
        if [[ $# -lt 1 ]]; then
            log ERROR "Missing prompt for deliver phase"
            echo "Usage: $(basename "$0") deliver <prompt> [develop-results-file]"
            echo "Example: $(basename "$0") deliver \"finalize and ship\""
            exit 1
        fi
        ink_deliver "$1" "${2:-}"
        ;;
    code-review)
        # Multi-LLM code review pipeline — competitor to CC Code Review
        if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
            echo "Usage: $(basename "$0") code-review '<json-profile>'"
            echo "Profile fields: target, focus, provenance, autonomy, publish, debate"
            echo "Example: $(basename "$0") code-review '{\"target\":\"staged\",\"publish\":\"ask\"}'"
            exit 0
        fi
        review_run "${1:-"{}"}"
        ;;
    embrace)
        # Full 4-phase Double Diamond workflow
        # Handle help flag
        if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
            usage embrace
            exit 0
        fi
        if [[ $# -lt 1 ]]; then
            log ERROR "Missing prompt for embrace workflow"
            echo "Usage: $(basename "$0") embrace <prompt>"
            echo "Example: $(basename "$0") embrace \"implement user authentication\""
            exit 1
        fi
        embrace_full_workflow "$*"
        ;;
    synthesize-probe)
        # v8.48.0: Standalone probe synthesis — recovers from Bash tool timeout
        # WHY: probe spawns 5+ agents (~60-90s) then runs Gemini synthesis (~30-60s),
        # frequently exceeding the Bash tool's 120s timeout. This command lets the
        # user synthesize already-collected probe results independently.
        if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
            echo "Synthesize Probe Results — Standalone synthesis for timed-out probes"
            echo ""
            echo "Usage: $(basename "$0") synthesize-probe [<task_group>] [<prompt>]"
            echo ""
            echo "Arguments:"
            echo "  task_group   The probe task group ID (timestamp). If omitted, uses most recent."
            echo "  prompt       The original probe prompt. If omitted, reads from marker file."
            echo ""
            echo "Examples:"
            echo "  $(basename "$0") synthesize-probe                    # Auto-detect most recent"
            echo "  $(basename "$0") synthesize-probe 1741234567         # Specific task group"
            echo "  $(basename "$0") synthesize-probe 1741234567 \"How do we implement caching?\""
            echo ""
            echo "This command is designed to be called after 'probe' times out."
            echo "Probe results persist (written by subprocesses) even when the parent"
            echo "process is killed. This command synthesizes those existing results."
            exit 0
        fi

        mkdir -p "$RESULTS_DIR" "$LOGS_DIR"

        synth_task_group="${1:-}"
        synth_prompt="${2:-}"

        # Auto-detect task group and prompt from marker files if not provided
        if [[ -z "$synth_task_group" ]]; then
            # Find the most recent marker file
            latest_marker=$(ls -t "$RESULTS_DIR"/probe-needs-synthesis-*.marker 2>/dev/null | head -1)

            if [[ -n "$latest_marker" && -f "$latest_marker" ]]; then
                # shellcheck disable=SC1090
                source "$latest_marker"
                synth_task_group="${task_group:-}"
                synth_prompt="${prompt:-}"
                log INFO "Auto-detected from marker: task_group=$synth_task_group"
            fi

            # If still no task group, find most recent probe results
            if [[ -z "$synth_task_group" ]]; then
                latest_result=$(ls -t "$RESULTS_DIR"/*-probe-*-*.md 2>/dev/null | head -1)
                if [[ -n "$latest_result" ]]; then
                    # Extract task_group from filename pattern: agent-probe-TASKGROUP-N.md
                    synth_task_group=$(basename "$latest_result" | sed -E 's/.*-probe-([0-9]+)-.*/\1/')
                    log INFO "Auto-detected from results: task_group=$synth_task_group"
                fi
            fi
        elif [[ -z "$synth_prompt" ]]; then
            # Task group provided but no prompt — try marker file
            marker_file="${RESULTS_DIR}/probe-needs-synthesis-${synth_task_group}.marker"
            if [[ -f "$marker_file" ]]; then
                # shellcheck disable=SC1090
                source "$marker_file"
                synth_prompt="${prompt:-}"
                log INFO "Prompt recovered from marker file"
            fi
        fi

        if [[ -z "$synth_task_group" ]]; then
            log ERROR "No probe results found to synthesize"
            echo ""
            echo "No pending probe results detected. Run a probe first:"
            echo "  $(basename "$0") probe \"your research question\""
            echo ""
            echo "Then if it times out, run:"
            echo "  $(basename "$0") synthesize-probe"
            exit 1
        fi

        # Count available results for this task group
        synth_result_count=0
        for result in "$RESULTS_DIR"/*-probe-${synth_task_group}-*.md; do
            [[ -f "$result" ]] || continue
            fsize=$(wc -c < "$result" 2>/dev/null || echo "0")
            [[ $fsize -gt 500 ]] && ((synth_result_count++)) || true
        done

        if [[ $synth_result_count -eq 0 ]]; then
            log ERROR "No usable probe results found for task group: $synth_task_group"
            echo "Results directory: $RESULTS_DIR"
            echo "Expected files matching: *-probe-${synth_task_group}-*.md"
            exit 1
        fi

        # Check if synthesis already exists
        existing_synthesis="${RESULTS_DIR}/probe-synthesis-${synth_task_group}.md"
        if [[ -f "$existing_synthesis" ]]; then
            existing_size=$(wc -c < "$existing_synthesis" 2>/dev/null || echo "0")
            if [[ $existing_size -gt 500 ]]; then
                echo ""
                echo -e "${GREEN}Synthesis already exists${NC}: $existing_synthesis ($(numfmt --to=iec-i --suffix=B $existing_size 2>/dev/null || echo "${existing_size}B"))"
                echo "To force re-synthesis, delete it first:"
                echo "  rm \"$existing_synthesis\""
                exit 0
            fi
        fi

        echo ""
        echo -e "${MAGENTA}${_BOX_TOP}${NC}"
        echo -e "${MAGENTA}║  ${GREEN}PROBE SYNTHESIS${MAGENTA} - Standalone synthesis recovery         ║${NC}"
        echo -e "${MAGENTA}║  Synthesizing $synth_result_count probe results (task: ${synth_task_group})       ${MAGENTA}║${NC}"
        echo -e "${MAGENTA}${_BOX_BOT}${NC}"
        echo ""

        if [[ -z "$synth_prompt" ]]; then
            synth_prompt="[prompt not available — synthesize from collected probe results]"
            log WARN "Original prompt not available; synthesis will work from result content only"
        fi

        log INFO "Synthesizing probe results: task_group=$synth_task_group, results=$synth_result_count"
        synthesize_probe_results "$synth_task_group" "$synth_prompt" "$synth_result_count"

        # Clean up marker file on success
        rm -f "${RESULTS_DIR}/probe-needs-synthesis-${synth_task_group}.marker"
        log INFO "Synthesis complete, marker cleaned up"
        ;;
    factory|dark-factory)
        # Dark Factory: spec-in, software-out autonomous pipeline (v8.25.0)
        if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
            echo "Dark Factory Mode — Spec-in, software-out autonomous pipeline"
            echo ""
            echo "Usage: $(basename "$0") factory --spec <path> [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --spec <path>          Path to NLSpec file (required)"
            echo "  --holdout-ratio N      Holdout ratio 0.0-1.0 (default: 0.20)"
            echo "  --max-retries N        Max retry attempts on failure (default: 1)"
            echo "  --ci                   Non-interactive CI mode (skip approval gate)"
            echo ""
            echo "Examples:"
            echo "  $(basename "$0") factory --spec spec.md"
            echo "  $(basename "$0") factory --spec spec.md --holdout-ratio 0.25 --max-retries 2"
            echo "  $(basename "$0") factory --spec spec.md --ci"
            echo ""
            echo "Pipeline: parse spec → generate scenarios → split holdout (20%)"
            echo "          → embrace workflow → holdout tests → score → report"
            echo ""
            echo "Artifacts: .octo/factory/<run-id>/"
            exit 0
        fi

        # Parse flags
        factory_spec=""
        factory_holdout="$OCTOPUS_FACTORY_HOLDOUT_RATIO"
        factory_retries="$OCTOPUS_FACTORY_MAX_RETRIES"
        factory_ci="false"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --spec)
                    factory_spec="$2"
                    shift 2
                    ;;
                --holdout-ratio)
                    factory_holdout="$2"
                    shift 2
                    ;;
                --max-retries)
                    factory_retries="$2"
                    shift 2
                    ;;
                --ci)
                    factory_ci="true"
                    shift
                    ;;
                *)
                    # Treat remaining args as inline spec text (fallback)
                    if [[ -z "$factory_spec" ]]; then
                        # Create temp spec from inline text
                        factory_spec=$(mktemp /tmp/factory-spec-XXXXXX.md)
                        echo "$@" > "$factory_spec"
                    fi
                    break
                    ;;
            esac
        done

        if [[ -z "$factory_spec" ]]; then
            log ERROR "Missing --spec argument"
            echo "Usage: $(basename "$0") factory --spec <path-to-spec.md>"
            echo "Run '$(basename "$0") factory --help' for full usage."
            exit 1
        fi

        factory_run "$factory_spec" "$factory_holdout" "$factory_retries" "$factory_ci"
        ;;
    # ═══════════════════════════════════════════════════════════════════════════
    # CROSSFIRE COMMANDS (Adversarial Cross-Model Review)
    # ═══════════════════════════════════════════════════════════════════════════
    grapple)
        # Adversarial debate: Codex vs Gemini until consensus
        source "${SCRIPT_DIR}/lib/debate.sh" 2>/dev/null || true
        # Handle help flag
        if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
            usage grapple
            exit 0
        fi
        if [[ $# -lt 1 ]]; then
            log ERROR "Missing prompt for grapple review"
            echo "Usage: $(basename "$0") grapple [OPTIONS] <prompt>"
            echo ""
            echo "Options:"
            echo "  -r, --rounds N         Number of debate rounds (3-7, default: 3)"
            echo "  --principles TYPE      Principle set to apply (default: general)"
            echo ""
            echo "Examples:"
            echo "  $(basename "$0") grapple \"redis vs memcached\""
            echo "  $(basename "$0") grapple -r 5 \"microservices vs monolith\""
            echo "  $(basename "$0") grapple --principles security \"implement password reset\""
            echo ""
            echo "Principles: general, security, performance, maintainability"
            exit 1
        fi

        # Parse flags (v7.13.2, v8.31.0: --mode)
        principles="general"
        rounds=3
        debate_mode="cross-critique"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --principles)
                    principles="$2"
                    shift 2
                    ;;
                -r|--rounds)
                    rounds="$2"
                    shift 2
                    ;;
                --mode)
                    debate_mode="$2"
                    shift 2
                    ;;
                *)
                    # Remaining args are the prompt
                    break
                    ;;
            esac
        done

        grapple_debate "$@" "$principles" "$rounds" "$debate_mode"
        ;;
    squeeze|red-team)
        # Red Team security review: Blue Team defends, Red Team attacks
        # Handle help flag
        if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
            usage squeeze
            exit 0
        fi
        if [[ $# -lt 1 ]]; then
            log ERROR "Missing prompt for red team review"
            echo "Usage: $(basename "$0") squeeze <prompt>"
            echo "       $(basename "$0") squeeze \"review auth.ts for vulnerabilities\""
            exit 1
        fi
        squeeze_test "$*"
        ;;
    sentinel)
        # v8.18.0: GitHub-aware work monitor
        if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
            echo "Usage: $(basename "$0") sentinel [OPTIONS]"
            echo ""
            echo "GitHub-aware work monitor that triages issues, PRs, and CI failures."
            echo ""
            echo "Options:"
            echo "  --watch       Continuous monitoring mode (polls every OCTOPUS_SENTINEL_INTERVAL seconds)"
            echo "  --help, -h    Show this help"
            echo ""
            echo "Environment Variables:"
            echo "  OCTOPUS_SENTINEL_ENABLED    Enable sentinel (default: false)"
            echo "  OCTOPUS_SENTINEL_INTERVAL   Poll interval in seconds (default: 600)"
            echo ""
            echo "Examples:"
            echo "  OCTOPUS_SENTINEL_ENABLED=true $(basename "$0") sentinel"
            echo "  OCTOPUS_SENTINEL_ENABLED=true $(basename "$0") sentinel --watch"
            exit 0
        fi
        if [[ "${1:-}" == "--watch" ]]; then
            sentinel_watch
        else
            sentinel_tick
        fi
        ;;
    preflight)
        preflight_check
        ;;
    release)
        do_release
        ;;
    doctor)
        do_doctor "$@"
        ;;
    octopus-configure)
        setup_wizard
        ;;
    setup)
        # Deprecated: redirect to new command name
        echo -e "${YELLOW}⚠ 'setup' is deprecated. Use 'octopus-configure' instead.${NC}"
        setup_wizard
        ;;
    # ═══════════════════════════════════════════════════════════════════════════
    # CLASSIC COMMANDS
    # ═══════════════════════════════════════════════════════════════════════════
    init)
        if [[ "${1:-}" == "--interactive" ]] || [[ "${1:-}" == "-i" ]]; then
            init_interactive
        else
            init_workspace
        fi
        ;;
    config|configure|preferences)
        # v4.5: Reconfigure user preferences
        reconfigure_preferences
        ;;
    agent-resume)
        # v8.53.0: Resume a previous agent by ID
        # Wraps resume_agent() — requires SUPPORTS_CONTINUATION + SUPPORTS_STABLE_AGENT_TEAMS
        if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
            echo "Usage: $(basename "$0") agent-resume <agent-id> [prompt] [task-id]"
            echo "Resumes a previous Claude agent transcript. Requires CC v2.1.55+ and Agent Teams."
            echo "Example: $(basename "$0") agent-resume abc123 'continue the refactor'"
            exit 0
        fi
        if [[ $# -lt 1 || -z "${1:-}" ]]; then
            log ERROR "agent-resume: missing agent-id"
            echo "Usage: $(basename "$0") agent-resume <agent-id> [prompt] [task-id]"
            exit 1
        fi
        local _agent_id="$1"
        local _resume_prompt="${2:-Continue where you left off.}"
        local _resume_task="${3:-$(date +%s)}"
        resume_agent "$_agent_id" "$_resume_prompt" "$_resume_task" || {
            log ERROR "resume_agent failed for agent_id=$_agent_id"
            log INFO "Requirements: SUPPORTS_CONTINUATION=true (CC v2.1.55+) AND SUPPORTS_STABLE_AGENT_TEAMS=true"
            log INFO "Run: $(basename "$0") doctor  to check environment flags"
            exit 1
        }
        ;;
    spawn)
        [[ $# -lt 2 ]] && { log ERROR "Usage: spawn <agent> <prompt>"; exit 1; }
        spawn_agent "$1" "$2"
        ;;
    auto)
        source "${SCRIPT_DIR}/lib/auto-route.sh" 2>/dev/null || true
        [[ $# -lt 1 ]] && { log ERROR "Usage: auto <prompt>"; exit 1; }
        auto_route "$*"
        ;;
    parallel)
        parallel_execute "${1:-}"
        ;;
    fan-out|fanout)
        [[ $# -lt 1 ]] && { log ERROR "Usage: fan-out <prompt>"; exit 1; }
        fan_out "$*"
        ;;
    map-reduce|mapreduce)
        [[ $# -lt 1 ]] && { log ERROR "Usage: map-reduce <prompt>"; exit 1; }
        map_reduce "$*"
        ;;
    detect-providers)
        cmd_detect_providers
        ;;
    update-clis)
        cmd_update_clis
        ;;
    status)
        show_status
        ;;
    analytics)
        generate_analytics_report "${1:-30}"
        ;;
    kill)
        kill_agents "${1:-all}"
        ;;
    clean)
        clean_workspace
        ;;
    skills)
        # Claude Code v2.1.9: List available skills
        list_available_skills
        ;;
    aggregate)
        aggregate_results "${1:-}"
        ;;
    # ═══════════════════════════════════════════════════════════════════════════
    # KNOWLEDGE WORKER WORKFLOWS (v6.0)
    # ═══════════════════════════════════════════════════════════════════════════
    empathize|empathy|ux-research)
        [[ $# -lt 1 ]] && { log ERROR "Usage: empathize <prompt>"; exit 1; }
        empathize_research "$*"
        ;;
    advise|consult|strategy)
        [[ $# -lt 1 ]] && { log ERROR "Usage: advise <prompt>"; exit 1; }
        advise_strategy "$*"
        ;;
    synthesize|synthesis|lit-review)
        [[ $# -lt 1 ]] && { log ERROR "Usage: synthesize <prompt>"; exit 1; }
        synthesize_research "$*"
        ;;
    knowledge-toggle)
        # Legacy toggle command - always toggles
        toggle_knowledge_work_mode "toggle"
        ;;
    dev|dev-mode)
        # Switch to Dev Work mode (turns off knowledge mode)
        toggle_knowledge_work_mode "off"
        ;;
    knowledge|knowledge-mode|km)
        # Enhanced knowledge mode toggle with on/off/status support
        # Usage: knowledge-mode [on|off|status|toggle]
        #        km [on|off|status]  (short alias)
        # No args = show status, explicit toggle/on/off to change
        toggle_knowledge_work_mode "${1:-status}"
        ;;
    deliver-docs|export-docs|create-docs)
        # Document delivery help - show recent outputs and conversion guidance
        echo ""
        echo "📄 Document Delivery"
        echo ""
        echo "Convert knowledge work outputs to professional office formats:"
        echo "  • Recent results: ls -lht ~/.claude-octopus/results/ | head -5"
        echo ""
        ls -lht ~/.claude-octopus/results/ 2>/dev/null | head -5 || echo "  No results found yet. Run empathize/advise/synthesize first."
        echo ""
        echo "To convert, just ask naturally:"
        echo "  - 'Export the latest synthesis to Word'"
        echo "  - 'Create a PowerPoint from this research'"
        echo "  - 'Convert to professional document'"
        echo ""
        echo "Make sure document-skills is installed:"
        echo "  /plugin install document-skills@anthropic-agent-skills"
        echo ""
        ;;
    # ═══════════════════════════════════════════════════════════════════════════
    # AI DEBATE HUB COMMANDS (v7.4 - Integration with wolverin0/claude-skills)
    # ═══════════════════════════════════════════════════════════════════════════
    debate|deliberate|consensus)
        # AI Debate Hub - Structured four-way debates
        # Check if submodule exists
        if [[ ! -f ".dependencies/claude-skills/skills/debate.md" ]]; then
            log ERROR "AI Debate Hub not found. Please initialize the submodule:"
            echo ""
            echo "  git submodule update --init --recursive"
            echo ""
            echo "AI Debate Hub by wolverin0: https://github.com/wolverin0/claude-skills"
            exit 1
        fi

        log INFO "🗣️  AI Debate Hub (by wolverin0)"
        log INFO "   Enhanced with claude-octopus quality gates and session management"

        # Set integration environment variables
        export CLAUDE_OCTOPUS_DEBATE_MODE="true"
        export CLAUDE_CODE_SESSION="${CLAUDE_CODE_SESSION:-}"

        # The debate.md skill will be automatically loaded by Claude Code
        # The debate-integration.md skill provides enhancements
        echo ""
        echo "📖 AI Debate Hub is active"
        echo ""
        echo "Original skill: .dependencies/claude-skills/skills/debate.md"
        echo "Enhancements: .claude/skills/debate-integration.md"
        echo "Attribution: AI Debate Hub by wolverin0 (MIT License)"
        echo ""
        echo "Usage examples:"
        echo "  /debate Should we use Redis or in-memory cache?"
        echo "  /debate -r 3 -d thorough \"Review our API architecture\""
        echo "  /debate -r 5 -d adversarial \"Security review of auth.ts\""
        echo ""
        echo "Debate styles:"
        echo "  quick (1 round) - Fast initial perspectives"
        echo "  thorough (3 rounds) - Detailed analysis with refinement"
        echo "  adversarial (5 rounds) - Devil's advocate, stress testing"
        echo "  collaborative (2 rounds) - Consensus-building"
        echo ""

        # Note: The actual debate execution is handled by Claude Code's skill system
        # This command just provides information and sets up the environment
        ;;
    # ═══════════════════════════════════════════════════════════════════════════
    # RALPH-WIGGUM ITERATION COMMANDS (v3.5)
    # ═══════════════════════════════════════════════════════════════════════════
    ralph|iterate)
        [[ $# -lt 1 ]] && { log ERROR "Usage: ralph <prompt> [agent] [max-iterations]"; exit 1; }
        run_with_ralph_loop "${2:-codex}" "$1" "${3:-$RALPH_MAX_ITERATIONS}"
        ;;
    # ═══════════════════════════════════════════════════════════════════════════
    # OPTIMIZATION COMMANDS (v4.2)
    # ═══════════════════════════════════════════════════════════════════════════
    optimize|optimise)
        source "${SCRIPT_DIR}/lib/auto-route.sh" 2>/dev/null || true
        [[ $# -lt 1 ]] && { log ERROR "Usage: optimize <prompt>"; exit 1; }
        auto_route "$*"
        ;;
    # ═══════════════════════════════════════════════════════════════════════════
    # SHELL COMPLETION (v4.2)
    # ═══════════════════════════════════════════════════════════════════════════
    completion)
        generate_shell_completion "${1:-bash}"
        ;;
    # ═══════════════════════════════════════════════════════════════════════════
    # AUTHENTICATION (v4.2)
    # ═══════════════════════════════════════════════════════════════════════════
    auth)
        handle_auth_command "${1:-status}" "${@:2}"
        ;;
    login)
        handle_auth_command "login" "$@"
        ;;
    logout)
        handle_auth_command "logout" "$@"
        ;;
    # ═══════════════════════════════════════════════════════════════════════════
    # USAGE & COST REPORTING COMMANDS (v4.1)
    # ═══════════════════════════════════════════════════════════════════════════
    cost|usage)
        # Show usage report (table by default, or json/csv with argument)
        generate_usage_report "${1:-table}"
        ;;
    cost-json)
        # Export usage as JSON
        generate_usage_report "json"
        ;;
    cost-csv)
        # Export usage as CSV
        generate_usage_report "csv"
        ;;
    cost-clear)
        # Clear current session usage
        clear_usage_session
        echo "Usage session cleared."
        ;;
    cost-archive)
        echo "cost-archive has been removed. Usage data is managed automatically."
        ;;
    # ═══════════════════════════════════════════════════════════════════════════
    # REVIEW & AUDIT COMMANDS (v4.4 - Human-in-the-loop)
    # ═══════════════════════════════════════════════════════════════════════════
    review)
        source "${SCRIPT_DIR}/lib/audit.sh" 2>/dev/null || true
        subcommand="${1:-list}"
        shift || true
        case "$subcommand" in
            list|ls)
                list_pending_reviews
                ;;
            approve|ok|accept)
                [[ $# -lt 1 ]] && { log ERROR "Usage: review approve <review-id> [reason]"; exit 1; }
                approve_review "$1" "${2:-Approved}"
                ;;
            reject|deny)
                [[ $# -lt 1 ]] && { log ERROR "Usage: review reject <review-id> [reason]"; exit 1; }
                reject_review "$1" "${2:-Rejected}"
                ;;
            show|view)
                [[ $# -lt 1 ]] && { log ERROR "Usage: review show <review-id>"; exit 1; }
                show_review "$1"
                ;;
            *)
                echo "Review subcommands:"
                echo "  list            - List pending reviews"
                echo "  approve <id>    - Approve a review"
                echo "  reject <id>     - Reject a review"
                echo "  show <id>       - Show review output"
                ;;
        esac
        ;;
    audit)
        source "${SCRIPT_DIR}/lib/audit.sh" 2>/dev/null || true
        count="${1:-20}"
        filter="${2:-}"
        get_audit_trail "$count" "$filter"
        ;;
    # ═══════════════════════════════════════════════════════════════════════════
    # HELP COMMANDS (v4.0 - Progressive disclosure)
    # ═══════════════════════════════════════════════════════════════════════════
    init-workflow)
        # v9.5.0: Compound initialization — returns full environment bundle as JSON
        # Avoids N sequential Bash calls for providers, models, config, capabilities.
        if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
            echo "Init Workflow — Return full environment bundle as JSON"
            echo ""
            echo "Usage: $(basename "$0") init-workflow [workflow]"
            echo ""
            echo "Returns JSON with providers, models, config, capabilities, and paths."
            echo "Designed to be called once at workflow start to reduce sequential Bash calls."
            exit 0
        fi

        _init_workflow="${1:-embrace}"
        _init_ts=$(date +%s)

        # Detect providers
        _codex_ok="false"; command -v codex &>/dev/null && [[ -n "${OPENAI_API_KEY:-}" || -f "${HOME}/.codex/auth.json" ]] && _codex_ok="true"
        _gemini_ok="false"; command -v gemini &>/dev/null && [[ -n "${GEMINI_API_KEY:-}" || -f "${HOME}/.gemini/oauth_creds.json" ]] && _gemini_ok="true"
        _claude_ok="true"  # Always available
        _perplexity_ok="false"; [[ -n "${PERPLEXITY_API_KEY:-}" ]] && _perplexity_ok="true"

        # Model resolution for key roles
        _model_researcher=$(get_agent_model "researcher" 2>/dev/null || echo "unknown")
        _model_implementer=$(get_agent_model "implementer" 2>/dev/null || echo "unknown")
        _model_reviewer=$(get_agent_model "reviewer" 2>/dev/null || echo "unknown")
        _model_synthesizer=$(get_agent_model "synthesizer" 2>/dev/null || echo "unknown")

        # Capabilities
        _agent_teams="${SUPPORTS_AGENT_TEAMS:-false}"
        _continuation="${SUPPORTS_CONTINUATION:-false}"
        _worktree="${SUPPORTS_WORKTREE:-false}"

        # Config files
        _has_review_md="false"; [[ -f "REVIEW.md" ]] && _has_review_md="true"
        _has_claude_md="false"; [[ -f "CLAUDE.md" ]] && _has_claude_md="true"
        _has_octo_config="false"; [[ -f ".octo/config.json" ]] && _has_octo_config="true"

        # Session
        _session_file="${HOME}/.claude-octopus/session.json"
        _has_session="false"; [[ -f "$_session_file" ]] && _has_session="true"

        cat <<INIT_JSON
{
  "workflow": "$_init_workflow",
  "providers": {
    "codex": $_codex_ok,
    "gemini": $_gemini_ok,
    "claude": $_claude_ok,
    "perplexity": $_perplexity_ok
  },
  "models": {
    "researcher": "$_model_researcher",
    "implementer": "$_model_implementer",
    "reviewer": "$_model_reviewer",
    "synthesizer": "$_model_synthesizer"
  },
  "capabilities": {
    "agent_teams": $_agent_teams,
    "continuation": $_continuation,
    "worktree": $_worktree
  },
  "files": {
    "review_md": $_has_review_md,
    "claude_md": $_has_claude_md,
    "octo_config": $_has_octo_config,
    "session": $_has_session
  },
  "paths": {
    "workspace": "${OCTOPUS_WORKSPACE:-${HOME}/.claude-octopus}",
    "results": "${RESULTS_DIR:-${HOME}/.claude-octopus/results}"
  },
  "ts": $_init_ts
}
INIT_JSON
        ;;
    help)
        usage "$@"
        ;;
    *)
        log ERROR "Unknown command: $COMMAND"
        echo ""
        echo "Did you mean one of these?"
        echo "  auto      - Smart routing (recommended)"
        echo "  embrace   - Full 4-phase workflow"
        echo "  research  - Parallel exploration"
        echo "  develop   - Implementation with validation"
        echo ""
        echo "Run '$(basename "$0") help' for all commands."
        exit 1
        ;;
esac
fi
