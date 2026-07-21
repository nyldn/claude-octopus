#!/usr/bin/env bash
_profile_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! declare -f octopus_resolve_reasoning_level >/dev/null 2>&1; then
    source "${_profile_lib_dir}/execution-profile.sh" 2>/dev/null || true
fi
# Claude Octopus — Agent Dispatch & Model Resolution
# ═══════════════════════════════════════════════════════════════════════════════
# Extracted from orchestrate.sh in v9.7.7 monolith decomposition.
# Contains: get_agent_command, get_agent_model, validate_model_allowed,
#           apply_tool_policy, apply_persona, get_agent_readonly,
#           get_role_budget_proportion, enforce_context_budget
# Source-safe: no main execution block.
# ═══════════════════════════════════════════════════════════════════════════════

#                    gpt-5.2-codex, gpt-5.4-mini (budget), gpt-5 (standard), gpt-5.2, gpt-5.1
# - OpenAI Reasoning: o3, o3-pro (API-key only), o3 (API-key only), o3-mini (API-key only)
# - OpenAI Large Context: gpt-4.1 (1M ctx, API-key only), gpt-5.4 (1M ctx, API-key only)
# - Google Gemini 3.0: gemini-3.1-pro-preview, gemini-3-flash-preview, gemini-3-pro-image (GA; gemini-3-pro-image-preview deprecated 2026-06-25)
# - Google Antigravity CLI: agy --print stdin dispatch, optional OCTOPUS_AGY_MODEL
# Note: "API-key only" models require OPENAI_API_KEY; they are NOT available via ChatGPT subscription/OAuth.

_octopus_is_safe_openai_compatible_dispatch_value() {
    local value="$1"
    [[ -z "$value" ]] && return 1
    [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]] && return 1
    [[ "$value" == *"\\"* ]] && return 1
    case "$value" in
        *[[:space:]]*|*\*|*";"*|*"|"*|*"&"*|*'$'*|*'`'*|*"'"*|*'"'*|*"("*|*")"*|*"<"*|*">"*|*"!"*|*"*"*|*"?"*|*"["*|*"]"*|*"{"*|*"}"*)
            return 1
            ;;
    esac
    return 0
}

_octopus_is_safe_env_var_name() {
    [[ "${1:-}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

_octopus_openai_compatible_runtime_config() {
    local provider="$1"
    local config_provider="$provider" base_url api_key_env credential_value
    case "$provider" in
        openai-compatible|openai-tools|openai-compatible-agent) config_provider="openai-compatible-agent" ;;
    esac

    base_url="$(octopus_provider_definition_field "$config_provider" base_url)"
    [[ -n "$base_url" ]] || base_url="${OPENAI_COMPAT_BASE_URL:-}"

    api_key_env="$(octopus_provider_definition_field "$config_provider" api_key_env)"
    [[ -n "$api_key_env" ]] || api_key_env="${OPENAI_COMPAT_API_KEY_ENV:-OPENAI_API_KEY}"

    if [[ -z "$base_url" ]]; then
        log ERROR "OpenAI-compatible provider '$config_provider' has no base_url in providers.json and OPENAI_COMPAT_BASE_URL is unset"
        return 1
    fi
    case "$base_url" in
        http://*|https://*) ;;
        *)
            log ERROR "OpenAI-compatible provider '$config_provider' requires an http(s) base_url"
            return 1
            ;;
    esac
    if ! _octopus_is_safe_openai_compatible_dispatch_value "$base_url"; then
        log ERROR "Invalid OpenAI-compatible base_url for provider '$provider'"
        return 1
    fi
    if ! _octopus_is_safe_env_var_name "$api_key_env"; then
        log ERROR "Invalid api_key_env for OpenAI-compatible provider '$provider': '$api_key_env'"
        return 1
    fi
    credential_value="$(printenv "$api_key_env" 2>/dev/null || true)"
    if [[ -z "$credential_value" ]]; then
        log ERROR "OpenAI-compatible provider '$config_provider' requires credential env '$api_key_env', but it is unset"
        return 1
    fi

    printf '%s\t%s\n' "$base_url" "$api_key_env"
}

# ── Does a resolved codex model name indicate an OSS/local model that codex
#    serves through ollama (and would silently auto-pull)? codex's built-in OSS
#    family is gpt-oss*; ollama-served models also carry a size tag like ':120b'.
#    Cloud codex models (gpt-5.x, o3, gpt-4.1, gpt-5.2-codex) never use that tag
#    form, so this stays conservative and leaves normal codex dispatch untouched.
#    NOTE: keep in sync with _codex_model_is_oss() in helpers/codex-run.sh. ──
_codex_dispatch_is_oss_model() {
    local m="$1"
    [[ -z "$m" ]] && return 1
    # Preserve the caller's nocasematch setting instead of forcing it off.
    local _restore_nocasematch
    _restore_nocasematch=$(shopt -p nocasematch || true)
    shopt -s nocasematch
    local rc=1
    if [[ "$m" == gpt-oss* ]] || [[ "$m" =~ :[0-9]+(\.[0-9]+)?b$ ]]; then
        rc=0
    elif [[ -n "${OCTOPUS_CODEX_OSS_PATTERNS:-}" && "$m" =~ ${OCTOPUS_CODEX_OSS_PATTERNS} ]]; then
        rc=0
    fi
    eval "${_restore_nocasematch:-shopt -u nocasematch}"
    return $rc
}

# ── Build the `codex exec` dispatch string. For OSS/local models, wrap it in the
#    pull-guard shim (helpers/codex-run.sh) so codex cannot fire an unbounded
#    `ollama pull` for an absent multi-GB model unless OCTOPUS_OLLAMA_ALLOW_PULL
#    is set — closing the codex-side vector that ollama-run.sh does not cover.
#    Cloud models are emitted unchanged (zero behavior change for the common path). ──
_build_codex_exec_command() {
    local model="$1" sandbox_flag="$2" reasoning_fragment="${3:-}"
    local base="codex exec --skip-git-repo-check --model ${model}"
    [[ -n "$reasoning_fragment" ]] && base+=" ${reasoning_fragment}"
    base+=" ${sandbox_flag} -"
    if _codex_dispatch_is_oss_model "$model"; then
        echo "${PLUGIN_DIR}/scripts/helpers/codex-run.sh ${base}"
    else
        echo "$base"
    fi
}

get_agent_command() {
    local agent_type="$1"
    local phase="${2:-}"
    local role="${3:-}"
    local model=""
    # Allow swapping the claude binary (e.g. clarp = subscription-billed drop-in
    # for `claude -p`, instead of metered API). Default unchanged. May include
    # args (word-split downstream by read -ra), e.g. "clarp --strict-mcp-config".
    local _claude_bin="${OCTOPUS_CLAUDE_BIN:-claude}"
    # A Claude provider nested under a non-Claude host must not recursively load
    # user-scoped plugins/hooks. Unlike --bare, limiting setting sources keeps
    # OAuth/keychain authentication available.
    if [[ "${OCTOPUS_HOST:-standalone}" == "codex" || "${OCTOPUS_HOST:-standalone}" == "gemini" ]]; then
        if [[ " $_claude_bin " != *" --setting-sources "* ]]; then
            _claude_bin="${_claude_bin} --setting-sources project,local"
        fi
    fi

    # Configurable sandbox mode (v7.13.1 - Issue #9)
    # Priority: OCTOPUS_CODEX_SANDBOX env var > default (workspace-write)
    # Valid values: workspace-write (default), danger-full-access, read-only
    local codex_sandbox="${OCTOPUS_CODEX_SANDBOX:-workspace-write}"

    # Security: reject values not in allowlist
    case "$codex_sandbox" in
        workspace-write|danger-full-access|read-only)
            ;;
        *)
            log "ERROR" "Invalid OCTOPUS_CODEX_SANDBOX value: '${codex_sandbox}'. Allowed: workspace-write, danger-full-access, read-only"
            log "ERROR" "Falling back to workspace-write for safety."
            codex_sandbox="workspace-write"
            ;;
    esac

    local sandbox_flag="--sandbox ${codex_sandbox}"

    # Spawned `claude --print` subprocesses have no interactive approver, so any
    # tool that would prompt is silently denied ("Read is blocked in the current
    # permission mode"). Pre-approve read tools for every role; write-capable
    # roles additionally accept edits (bug 260609). Comma-joined, no spaces —
    # downstream `read -ra` word-splits the command string.
    local claude_perm="--allowed-tools Read,Glob,Grep"
    case "$role" in
        implementer|developer)
            claude_perm="--permission-mode acceptEdits --allowed-tools Read,Glob,Grep,Edit,Write"
            ;;
    esac

    case "$agent_type" in
        # v8.9.0: Spark, reasoning, and large-context variants share the
        # same command shape; only model resolution differs by agent type.
        codex|codex-standard|codex-max|codex-mini|codex-general|codex-spark|codex-reasoning|codex-large-context)
            if ! model=$(get_agent_model "$agent_type" "$phase" "$role"); then
                return 1
            fi
            local reasoning_level reasoning_policy reasoning_fragment
            reasoning_level="$(octopus_resolve_reasoning_level codex "$phase" "$role")" || return 1
            reasoning_policy="$(octopus_resolve_reasoning_policy codex "$phase" "$role")" || return 1
            reasoning_fragment="$(octopus_reasoning_cli_fragment codex "$reasoning_level" "$reasoning_policy")" || return 1
            _build_codex_exec_command "$model" "$sandbox_flag" "$reasoning_fragment"
            ;;
        gemini|gemini-fast|gemini-image)
            local gemini_flags="-o text --approval-mode yolo"
            # OCTOPUS_GEMINI_VIA_AGY=1 serves gemini seats through the
            # Antigravity CLI instead of gemini-cli. Google sunset Gemini Code
            # Assist free-tier OAuth for gemini-cli (IneligibleTierError — every
            # call fails in seconds), while Antigravity subscriptions still
            # work. agy-exec.sh shares the stdin prompt contract, so callers
            # are unaffected. Model pins follow OCTOPUS_AGY_MODEL (labels from
            # `agy models`), not gemini model ids. Gemini reasoning policy does
            # not apply — the agy seat has its own model/reasoning controls.
            if [[ "${OCTOPUS_GEMINI_VIA_AGY:-0}" =~ ^(1|on|true|yes)$ ]]; then
                echo "${PLUGIN_DIR}/scripts/helpers/agy-exec.sh"
                return 0
            fi
            local reasoning_level reasoning_policy
            reasoning_level="$(octopus_resolve_reasoning_level gemini "$phase" "$role")" || return 1
            reasoning_policy="$(octopus_resolve_reasoning_policy gemini "$phase" "$role")" || return 1
            octopus_reasoning_cli_fragment gemini "$reasoning_level" "$reasoning_policy" >/dev/null || {
                log ERROR "Reasoning level '$reasoning_level' is unsupported for gemini under strict policy"
                return 1
            }
            if ! model=$(get_agent_model "$agent_type" "$phase" "$role"); then
                return 1
            fi
            # v8.10.0: Fixed headless mode (Issue #25)
            # Prompt delivered via stdin by callers (avoids OS arg limits)
            # Callers add -p "" for headless mode trigger
            # -o text: clean output, --approval-mode yolo: auto-accept (replaces deprecated -y)
            # v8.32.0: GEMINI_FORCE_FILE_STORAGE=true on macOS avoids Keychain prompts
            # when calling Gemini CLI from bash subprocesses (OAuth still works)
            # NOTE: .toml custom commands exist in .gemini/commands/octo/ for human use,
            # but stdin+slash-command don't compose in headless mode (Codex source analysis)
            # Routed through helpers/gemini-exec.sh for 404/ModelNotFound fallback.
            local gemini_env="env NODE_NO_WARNINGS=1"
            if [[ "$OCTOPUS_PLATFORM" == "Darwin" && -z "${GEMINI_API_KEY:-}" ]]; then
                gemini_env="env NODE_NO_WARNINGS=1 GEMINI_FORCE_FILE_STORAGE=true"
            fi
            local gemini_exec="${PLUGIN_DIR}/scripts/helpers/gemini-exec.sh"
            case "${OCTOPUS_GEMINI_SANDBOX:-headless}" in
                interactive|prompt-mode) gemini_flags="" ;;
            esac
            # Gemini confines reads to its cwd workspace; prompts that reference
            # files outside PROJECT_ROOT (e.g. /tmp staging dirs) need those dirs
            # whitelisted. Comma-separated, no spaces (read -ra word-splitting).
            if [[ -n "${OCTOPUS_GEMINI_INCLUDE_DIRS:-}" ]]; then
                gemini_flags="${gemini_flags} --include-directories ${OCTOPUS_GEMINI_INCLUDE_DIRS}"
            fi
            echo "${gemini_env} ${gemini_exec} ${model} ${gemini_flags}"
            ;;
        agy|agy-research|antigravity)
            echo "${PLUGIN_DIR}/scripts/helpers/agy-exec.sh"
            ;;
        codex-review) echo "codex exec --skip-git-repo-check review" ;; # Code review mode (no sandbox support)
        claude)
            local reasoning_level reasoning_policy reasoning_fragment
            reasoning_level="$(octopus_resolve_reasoning_level claude "$phase" "$role")" || return 1
            reasoning_policy="$(octopus_resolve_reasoning_policy claude "$phase" "$role")" || return 1
            reasoning_fragment="$(octopus_reasoning_cli_fragment claude "$reasoning_level" "$reasoning_policy")" || return 1
            echo "${_claude_bin}${_BARE_OPT} --print ${reasoning_fragment} ${claude_perm}" ;;                         # Claude Sonnet 4.6
        claude-sonnet)
            local reasoning_level reasoning_policy reasoning_fragment
            reasoning_level="$(octopus_resolve_reasoning_level claude "$phase" "$role")" || return 1
            reasoning_policy="$(octopus_resolve_reasoning_policy claude "$phase" "$role")" || return 1
            reasoning_fragment="$(octopus_reasoning_cli_fragment claude "$reasoning_level" "$reasoning_policy")" || return 1
            echo "${_claude_bin}${_BARE_OPT} --print --model sonnet ${reasoning_fragment} ${claude_perm}" ;;        # Claude Sonnet explicit
        claude-opus)
            # v9.42: Opus alias — resolves to 4.8 on Claude Code v2.1.154+,
            # then 4.7/4.6 on older hosts or enterprise backends.
            # Use `env VAR=val` prefix so the assignment survives read -ra word-splitting
            # in spawn.sh — a bare VAR=val prefix only works in shell eval context.
            local opus_effort="high" configured_claude_effort=""
            if declare -f octopus_resolve_reasoning_level >/dev/null 2>&1; then
                configured_claude_effort="$(octopus_resolve_reasoning_level claude "$phase" "$role" 2>/dev/null || true)"
            fi
            if [[ -n "$configured_claude_effort" ]]; then
                opus_effort="$configured_claude_effort"
            elif declare -f get_effort_level >/dev/null 2>&1; then
                local opus_complexity="2"
                case "${phase:-}" in
                    tangle|develop|ink|deliver) opus_complexity="3" ;;
                esac
                opus_effort="$(get_effort_level "${phase:-unknown}" "$opus_complexity")"
                opus_effort="${opus_effort:-high}"
            elif [[ -n "${OCTOPUS_EFFORT_OVERRIDE:-}" ]]; then
                opus_effort="$OCTOPUS_EFFORT_OVERRIDE"
            fi
            if declare -f fable5_clamp_effort >/dev/null 2>&1; then
                opus_effort="$(fable5_clamp_effort "$opus_effort")"
            fi
            # v9.51: Honor a Fable 5 pin in the dispatched model flag. The bare
            # `opus` alias always resolves to the host's default Opus, so
            # without this the pin changed cost labels but never the model.
            # Security dispatches reroute to Opus 4.8 (lib/fable5.sh).
            local configured_opus_model="${OCTOPUS_OPUS_MODEL:-opus}"
            if declare -f get_agent_model >/dev/null 2>&1; then
                configured_opus_model="$(get_agent_model "$agent_type" "$phase" "$role")" || return 1
            fi
            local opus_model_flag="$configured_opus_model"
            case "$configured_opus_model" in
                claude-opus-4.8) opus_model_flag="claude-opus-4-8" ;;
                claude-opus-4.6) opus_model_flag="claude-opus-4-6" ;;
            esac
            if [[ "${SUPPORTS_EFFORT_COMMAND:-false}" == "true" || "${SUPPORTS_XHIGH_EFFORT:-false}" == "true" ]]; then
                echo "env OCTOPUS_OPUS_MODEL=${configured_opus_model} CLAUDE_CODE_EFFORT_LEVEL=${opus_effort} ${_claude_bin}${_BARE_OPT:-} --print --model ${opus_model_flag} --effort ${opus_effort} ${claude_perm}"
            elif [[ "$configured_opus_model" == "claude-fable-5" ]]; then
                echo "env OCTOPUS_OPUS_MODEL=${configured_opus_model} ${_claude_bin}${_BARE_OPT:-} --print --model ${opus_model_flag} ${claude_perm}"
            else
                echo "${_claude_bin}${_BARE_OPT:-} --print --model ${opus_model_flag} ${claude_perm}"
            fi
            ;;
        claude-opus-fast)
            if [[ "${SUPPORTS_OPUS_4_8:-false}" == "true" && "${OCTOPUS_OPUS_MODEL:-}" != "claude-opus-4.6" ]]; then
                echo "${_claude_bin}${_BARE_OPT} --print --model claude-opus-4-8 --fast ${claude_perm}"
            else
                echo "${_claude_bin}${_BARE_OPT} --print --model claude-opus-4-6 --fast ${claude_perm}"
            fi
            ;;
        claude-opus-legacy) echo "${_claude_bin}${_BARE_OPT} --print --model claude-opus-4-6 ${claude_perm}" ;; # v9.23: explicit 4.6 opt-in
        openrouter) echo "openrouter_execute" ;;                 # OpenRouter API (v4.8)
        openrouter-glm5) echo "openrouter_execute_model z-ai/glm-5" ;;           # v8.11.0: GLM-5 via OpenRouter
        openrouter-glm52) echo "openrouter_execute_model z-ai/glm-5.2" ;;        # GLM 5.2 via OpenRouter
        openrouter-kimi) echo "openrouter_execute_model moonshotai/kimi-k2.5" ;; # v8.11.0: Kimi K2.5 via OpenRouter
        openrouter-kimi-k3) echo "openrouter_execute_model moonshotai/kimi-k3" ;; # Kimi K3 via OpenRouter
        openrouter-deepseek) echo "openrouter_execute_model deepseek/deepseek-r1-0528" ;; # v8.11.0: DeepSeek R1 via OpenRouter
        openai-compatible|openai-tools|openai-compatible-agent)  # Generic OpenAI-compatible tool-loop agent
            if ! model=$(get_agent_model "$agent_type" "$phase" "$role"); then
                return 1
            fi
            if ! validate_model_name "$model"; then
                log ERROR "Invalid OpenAI-compatible model name: ${model}"
                return 1
            fi
            if ! _octopus_is_safe_openai_compatible_dispatch_value "${PWD}"; then
                log ERROR "Invalid OpenAI-compatible cwd: ${PWD}"
                return 1
            fi
            local reasoning_level reasoning_policy reasoning_fragment runtime_config base_url api_key_env
            reasoning_level="$(octopus_resolve_reasoning_level openai-compatible-agent "$phase" "$role")" || return 1
            reasoning_policy="$(octopus_resolve_reasoning_policy openai-compatible-agent "$phase" "$role")" || return 1
            reasoning_fragment="$(octopus_reasoning_cli_fragment openai-compatible-agent "$reasoning_level" "$reasoning_policy")" || return 1
            runtime_config="$(_octopus_openai_compatible_runtime_config "$agent_type")" || return 1
            IFS=$'\t' read -r base_url api_key_env <<<"$runtime_config"
            echo "${PLUGIN_DIR}/scripts/helpers/openai-compatible-agent.py --provider generic --base-url ${base_url} --api-key-env ${api_key_env} --model ${model} ${reasoning_fragment} --cwd ${PWD}"
            ;;
        atlascloud-agent)  # Atlas Cloud via the OpenAI-compatible tool-loop agent
            model="${ATLASCLOUD_MODEL:-${OCTOPUS_ATLASCLOUD_MODEL:-${OPENAI_COMPAT_MODEL:-}}}"
            if [[ -z "$model" && -f "${HOME}/.claude-octopus/config/providers.json" ]] && command -v jq &>/dev/null; then
                model="$(jq -r '.providers.atlascloud.default // empty' "${HOME}/.claude-octopus/config/providers.json" 2>/dev/null || true)"
            fi
            if [[ -z "$model" ]]; then
                log ERROR "ATLASCLOUD_MODEL, OCTOPUS_ATLASCLOUD_MODEL, OPENAI_COMPAT_MODEL, or providers.json atlascloud.default is required"
                return 1
            fi
            if ! validate_model_name "$model"; then
                log ERROR "Invalid Atlas Cloud model name: ${model}"
                return 1
            fi
            local fallback
            fallback=$(validate_model_allowed "atlascloud" "$model")
            if [[ $? -ne 0 ]]; then
                if [[ -n "$fallback" ]]; then
                    if ! validate_model_name "$fallback"; then
                        log ERROR "Invalid Atlas Cloud fallback model name"
                        return 1
                    fi
                    model="$fallback"
                else
                    return 1
                fi
            fi
            if ! _octopus_is_safe_openai_compatible_dispatch_value "${PWD}"; then
                log ERROR "Invalid Atlas Cloud cwd: ${PWD}"
                return 1
            fi
            echo "${PLUGIN_DIR}/scripts/helpers/openai-compatible-agent.py --provider atlascloud --model ${model} --cwd ${PWD}"
            ;;
        perplexity|perplexity-fast)  # v8.24.0: Perplexity Sonar — web-grounded research (Issue #22)
            if ! model=$(get_agent_model "$agent_type" "$phase" "$role"); then
                return 1
            fi
            echo "perplexity_execute $model"
            ;;
        copilot|copilot-research)  # v9.9.0: GitHub Copilot CLI via helpers/copilot-exec.sh (Issue #198)
            # copilot's only non-interactive mode is `-p <text>` (argv), but the spawn
            # contract feeds the prompt via stdin. The shim bridges stdin -> -p so the
            # advisor does not open an interactive session and hang (silent drop).
            # -s: silent (no footer noise); --disable-builtin-mcps: skip MCP startup latency.
            echo "${PLUGIN_DIR}/scripts/helpers/copilot-exec.sh"
            ;;
        ollama|ollama-*)  # v9.9.0: Ollama local LLM — ollama run
            if ! model=$(get_agent_model "$agent_type" "$phase" "$role"); then
                return 1
            fi
            # Route through the guard shim instead of a bare `ollama run`: that
            # auto-pulls a missing model, so a provider-failure cascade could
            # silently kick off an unbounded multi-GB download. The shim refuses
            # to pull an absent model unless OCTOPUS_OLLAMA_ALLOW_PULL=true.
            echo "${PLUGIN_DIR}/scripts/helpers/ollama-run.sh $model"
            ;;
        qwen|qwen-research)  # v9.10.0: Qwen CLI — fork of Gemini CLI
            # oco-dar: NO_BROWSER=1 stops a stale token from hijacking the user's
            # browser into the OAuth device-flow. Pre-flight (qwen_is_usable) should
            # already gate this out; this is defense-in-depth if dispatch is reached.
            if ! model=$(get_agent_model "$agent_type" "$phase" "$role"); then
                return 1
            fi
            # OPENAI_COMPAT auth (OPENAI_API_KEY + OPENAI_BASE_URL) needs an explicit
            # --auth-type: the qwen CLI does not auto-detect it from env vars alone
            # in non-interactive mode (Issue #566).
            local qwen_auth_flag=""
            if declare -f qwen_auth_method >/dev/null 2>&1 && [[ "$(qwen_auth_method)" == "env:OPENAI_COMPAT" ]]; then
                qwen_auth_flag="--auth-type openai"
            fi
            echo "env NODE_NO_WARNINGS=1 NO_BROWSER=1 qwen -o text --approval-mode yolo -m ${model} ${qwen_auth_flag}"
            ;;
        grok|grok-research)  # xAI Grok CLI — headless single-turn via helpers/grok-exec.sh
            # Wire config/env model selection through to the shim (parity with codex/
            # gemini/qwen). get_agent_model reads providers.json + OCTOPUS_GROK_MODEL;
            # pass it via an env prefix so grok-exec.sh emits --model. Grok model ids are
            # single tokens (grok-4-fast, ...) so the prefix survives argv word-splitting.
            # Without this, providers.json model picks were silently ignored (the shim
            # only saw a shell-exported OCTOPUS_GROK_MODEL).
            if ! model=$(get_agent_model "$agent_type" "$phase" "$role"); then return 1; fi
            if [[ -n "$model" && "$model" != "default" ]]; then
                echo "env OCTOPUS_GROK_MODEL=${model} ${PLUGIN_DIR}/scripts/helpers/grok-exec.sh"
            else
                echo "${PLUGIN_DIR}/scripts/helpers/grok-exec.sh"
            fi
            ;;
        claude-sdk|claude-sdk-agent|claude-sdk-research)  # v9.50.0: Claude Agent SDK seat
            # Routes to helpers/claude-sdk-exec.sh when CLAUDE_SDK_API_KEY is set —
            # unlocks Opus 4.8 + 1M context independent of the host session. Model
            # wiring mirrors grok: env prefix so providers.json picks reach the shim.
            if ! model=$(get_agent_model "$agent_type" "$phase" "$role"); then return 1; fi
            if [[ -n "$model" && "$model" != "default" ]]; then
                echo "env OCTOPUS_CLAUDE_SDK_MODEL=${model} ${PLUGIN_DIR}/scripts/helpers/claude-sdk-exec.sh"
            else
                echo "${PLUGIN_DIR}/scripts/helpers/claude-sdk-exec.sh"
            fi
            ;;
        cursor-agent)  # v9.23.0: Cursor Agent CLI — Grok 4.20 via Cursor subscription
            if ! model=$(get_agent_model "$agent_type" "$phase" "$role"); then
                return 1
            fi
            # NOTE: bare ${model} (no quotes) — downstream uses `read -ra` which
            # does NOT interpret quotes; literal " would be passed to --model.
            echo "agent --trust --output-format text --model ${model}"
            ;;
        vibe|vibe-research)  # Mistral Vibe — interactive CLI (model in ~/.vibe/config.toml)
            # Routed through helpers/vibe-exec.sh: vibe's -p only accepts the
            # prompt as argv (stdin yields "No prompt provided"), so the shim
            # reads stdin and re-passes it as `-p "<prompt>"`. Keeps spawn.sh's
            # uniform stdin contract intact (Issue #173).
            echo "${PLUGIN_DIR}/scripts/helpers/vibe-exec.sh --output text"
            ;;
        opencode|opencode-fast|opencode-research)  # v9.11.0: OpenCode CLI — multi-provider router
            if ! model=$(get_agent_model "$agent_type" "$phase" "$role"); then
                return 1
            fi
            # Uses default text output (ANSI stripped by caller) — consistent with other providers
            # --model flag uses provider/model format; we store bare name and map here
            local oc_model_flag=""
            if [[ -n "$model" && "$model" != "default" ]]; then
                oc_model_flag="-m ${model}"
            fi
            # --pure skips opencode's external-plugin auto-title path, which
            # otherwise resolves an SDK handle for a hardcoded small model
            # before the prompt is even sent — an unresolvable catalog/model
            # there hangs `opencode run` indefinitely with no timeout or error
            # (Issue #566). It's a global flag, so it must precede the `run`
            # subcommand or risk being ignored/rejected.
            echo "opencode --pure run ${oc_model_flag}"
            ;;
        *) return 1 ;;
    esac
}

# v9.3.0: Per-role context budget proportions
# WHY: Prevents chatty agents from consuming all context while verifiers get starved
get_role_budget_proportion() {
    local role="$1"
    case "$role" in
        implementer|researcher|developer) echo "60" ;;
        planner|reviewer|architect)       echo "40" ;;
        verifier|synthesizer|release)     echo "25" ;;
        *)                                echo "100" ;; # no reduction for unknown roles
    esac
}

# Provider-aware context ceiling. OCTOPUS_CONTEXT_BUDGET remains the global
# fallback for compatibility; provider-specific env vars let higher-context CLIs
# opt in without inflating smaller providers.
get_provider_context_limit() {
    local agent_type="${1:-}"
    local provider="${agent_type%%-*}"
    local default_budget="${OCTOPUS_CONTEXT_BUDGET:-12000}"

    case "$agent_type" in
        codex-large-context) echo "${OCTOPUS_CODEX_LARGE_CONTEXT_BUDGET:-${default_budget}}" ; return 0 ;;
        claude-sdk*) echo "${OCTOPUS_CLAUDE_SDK_CONTEXT_BUDGET:-1000000}" ; return 0 ;;  # v9.50.0: Agent SDK 1M window
        claude-opus*|claude-sonnet|claude) echo "${OCTOPUS_CLAUDE_CONTEXT_BUDGET:-${default_budget}}" ; return 0 ;;
    esac

    case "$provider" in
        codex)      echo "${OCTOPUS_CODEX_CONTEXT_BUDGET:-${default_budget}}" ;;
        gemini)     echo "${OCTOPUS_GEMINI_CONTEXT_BUDGET:-${default_budget}}" ;;
        agy|antigravity) echo "${OCTOPUS_AGY_CONTEXT_BUDGET:-${default_budget}}" ;;
        claude)     echo "${OCTOPUS_CLAUDE_CONTEXT_BUDGET:-${default_budget}}" ;;
        perplexity) echo "${OCTOPUS_PERPLEXITY_CONTEXT_BUDGET:-${default_budget}}" ;;
        openrouter) echo "${OCTOPUS_OPENROUTER_CONTEXT_BUDGET:-${default_budget}}" ;;
        atlascloud) echo "${OCTOPUS_ATLASCLOUD_CONTEXT_BUDGET:-${default_budget}}" ;;
        copilot)    echo "${OCTOPUS_COPILOT_CONTEXT_BUDGET:-${default_budget}}" ;;
        qwen)       echo "${OCTOPUS_QWEN_CONTEXT_BUDGET:-${default_budget}}" ;;
        opencode)   echo "${OCTOPUS_OPENCODE_CONTEXT_BUDGET:-${default_budget}}" ;;
        ollama)     echo "${OCTOPUS_OLLAMA_CONTEXT_BUDGET:-${default_budget}}" ;;
        *)          echo "$default_budget" ;;
    esac
}

summarize_then_dispatch() {
    local prompt="$1"
    local role="${2:-}"
    local target_agent="${3:-unknown}"
    local budget="${4:-12000}"
    local char_budget=$((budget * 4))

    # Keep the summarizer request itself bounded; preserve both task framing and
    # tail-loaded instructions/diffs because provider CLIs often fail near ARG_MAX.
    local summary_input="$prompt"
    local max_summary_input="${OCTOPUS_OVERSIZE_SUMMARY_INPUT_CHARS:-120000}"
    if [[ ${#summary_input} -gt $max_summary_input ]]; then
        local head_chars=$((max_summary_input / 2))
        local tail_chars=$((max_summary_input - head_chars))
        local tail_start=$((${#summary_input} - tail_chars))
        summary_input="${summary_input:0:$head_chars}

[... middle omitted before preflight summarization; original prompt was ${#prompt} chars ...]

${summary_input:$tail_start:$tail_chars}"
    fi

    local summary_prompt="Condense this oversized agent prompt before provider dispatch.

Target provider: ${target_agent}
Role: ${role:-none}
Target budget: about ${budget} tokens (${char_budget} chars)

Preserve:
- the user's exact objective and constraints
- file paths, commands, URLs, IDs, and quoted requirements
- acceptance criteria and verification instructions
- any explicit safety or permission limits

Remove repetition, logs, duplicate context, and low-value boilerplate. Return only the condensed prompt.

Oversized prompt:
${summary_input}"

    local candidates=()
    if [[ -n "${OCTOPUS_OVERSIZE_SUMMARIZER:-}" ]]; then
        candidates+=("$OCTOPUS_OVERSIZE_SUMMARIZER")
    fi
    candidates+=("gemini-fast" "codex-mini" "claude-sonnet" "codex")

    local candidate summary previous_strategy previous_debug
    previous_strategy="${OCTOPUS_OVERSIZE_STRATEGY-}"
    previous_debug="${OCTOPUS_DEBUG-}"
    export OCTOPUS_OVERSIZE_STRATEGY=truncate
    export OCTOPUS_DEBUG="${OCTOPUS_DEBUG:-false}"

    for candidate in "${candidates[@]}"; do
        [[ "$candidate" == "$target_agent" ]] && continue
        if type validate_agent_type >/dev/null 2>&1 && ! validate_agent_type "$candidate" >/dev/null 2>&1; then
            continue
        fi
        if ! type run_agent_sync >/dev/null 2>&1; then
            break
        fi
        summary=$(run_agent_sync "$candidate" "$summary_prompt" 120 "synthesizer" "preflight" 2>/dev/null) || summary=""
        if [[ -n "$summary" && "$summary" != "Provider available" ]]; then
            if [[ -n "$previous_strategy" ]]; then
                export OCTOPUS_OVERSIZE_STRATEGY="$previous_strategy"
            else
                unset OCTOPUS_OVERSIZE_STRATEGY
            fi
            if [[ -n "$previous_debug" ]]; then
                export OCTOPUS_DEBUG="$previous_debug"
            else
                unset OCTOPUS_DEBUG
            fi
            printf '%s\n' "$summary"
            return 0
        fi
    done

    if [[ -n "$previous_strategy" ]]; then
        export OCTOPUS_OVERSIZE_STRATEGY="$previous_strategy"
    else
        unset OCTOPUS_OVERSIZE_STRATEGY
    fi
    if [[ -n "$previous_debug" ]]; then
        export OCTOPUS_DEBUG="$previous_debug"
    else
        unset OCTOPUS_DEBUG
    fi
    return 1
}

enforce_context_budget() {
    local prompt="$1"
    local role="${2:-}"
    local agent_type="${3:-}"
    local budget
    budget=$(get_provider_context_limit "$agent_type")
    [[ "$budget" =~ ^[0-9]+$ ]] || budget="${OCTOPUS_CONTEXT_BUDGET:-12000}"

    # v9.3.0: Scale budget by role proportion
    if [[ -n "$role" ]]; then
        local proportion
        proportion=$(get_role_budget_proportion "$role")
        budget=$((budget * proportion / 100))
    fi

    # Rough token estimate: ~4 chars per token
    local char_budget=$((budget * 4))

    if [[ ${#prompt} -gt $char_budget ]]; then
        local strategy="${OCTOPUS_OVERSIZE_STRATEGY:-summarize}"
        local original_chars=${#prompt}
        local target="${agent_type:-unknown}"

        case "$strategy" in
            fail)
                log "ERROR" "Context budget: prompt for $target is ${original_chars} chars; limit is $char_budget chars (~$budget tokens)"
                type record_oversize_event >/dev/null 2>&1 && record_oversize_event "$target" "$original_chars" "$original_chars" "failed" || true
                type write_agent_status >/dev/null 2>&1 && write_agent_status "$target" "failed" "$((original_chars / 4))" 0 "Prompt exceeded context budget" 0 "" "$role" || true
                return 78
                ;;
            summarize)
                log "WARN" "Context budget: summarizing prompt for $target from ${original_chars} to <=$char_budget chars (~$budget tokens)"
                local summarized
                if summarized=$(summarize_then_dispatch "$prompt" "$role" "$target" "$budget") && [[ -n "$summarized" ]]; then
                    if [[ ${#summarized} -gt $char_budget ]]; then
                        summarized="${summarized:0:$char_budget}

[... summarized preflight output truncated to fit context budget of ~$budget tokens ...]"
                    fi
                    type record_oversize_event >/dev/null 2>&1 && record_oversize_event "$target" "$original_chars" "${#summarized}" "summarized" || true
                    printf '%s\n' "$summarized"
                    return 0
                fi
                log "WARN" "Context budget: summarizer unavailable; falling back to truncation for $target"
                log "DEBUG" "Context budget: truncating prompt for $target from ${#prompt} to $char_budget chars (~$budget tokens)"
                type record_oversize_event >/dev/null 2>&1 && record_oversize_event "$target" "$original_chars" "$char_budget" "truncated" || true
                echo "${prompt:0:$char_budget}

[... truncated to fit context budget of ~$budget tokens ...]"
                ;;
            truncate|*)
                log "DEBUG" "Context budget: truncating prompt for $target from ${#prompt} to $char_budget chars (~$budget tokens)"
                type record_oversize_event >/dev/null 2>&1 && record_oversize_event "$target" "$original_chars" "$char_budget" "truncated" || true
                echo "${prompt:0:$char_budget}

[... truncated to fit context budget of ~$budget tokens ...]"
                ;;
        esac
    else
        echo "$prompt"
    fi
}

# Get model for agent type with v3.0 unified precedence
get_agent_model() {
    local agent_type="$1"
    local phase="${2:-}"
    local role="${3:-}"
    
    # Auto-migrate stale model names on first call
    migrate_provider_config

    # Determine base provider type
    local provider=""
    case "$agent_type" in
        codex*)      provider="codex" ;;
        gemini*)     provider="gemini" ;;
        agy*|antigravity) provider="agy" ;;
        claude-sdk*) provider="claude-sdk" ;;  # v9.50.0: must precede claude* glob
        claude*)     provider="claude" ;;
        openrouter*) provider="openrouter" ;;
        atlascloud*) provider="atlascloud" ;;
        openai-compatible|openai-tools|openai-compatible-agent*) provider="openai-compatible-agent" ;;
        perplexity*) provider="perplexity" ;;
        qwen*)       provider="qwen" ;;
        cursor-agent*) provider="cursor-agent" ;;
        grok*)       provider="grok" ;;
        opencode*)   provider="opencode" ;;
    esac

    local resolved_model
    if ! resolved_model=$(resolve_octopus_model "$provider" "$agent_type" "$phase" "$role"); then
        return 1
    fi

    # v8.31.0: Apply model restriction service if configured
    if [[ -n "$provider" ]]; then
        local fallback
        fallback=$(validate_model_allowed "$provider" "$resolved_model")
        if [[ $? -ne 0 && -n "$fallback" ]]; then
            if ! validate_model_name "$fallback"; then
                log ERROR "Invalid fallback model name for $provider"
                return 1
            fi
            echo "$fallback"
            return 0
        fi
    fi
    echo "$resolved_model"
}

# v8.31.0: Model restriction service — per-provider allowlists for cost/compliance control
# Set OCTOPUS_CODEX_ALLOWED_MODELS, OCTOPUS_GEMINI_ALLOWED_MODELS, etc. (comma-separated)
# Empty or unset = no restriction (all models allowed)
validate_model_allowed() {
    local provider="$1"
    local model="$2"

    local allowlist_var=""
    case "$provider" in
        codex)      allowlist_var="OCTOPUS_CODEX_ALLOWED_MODELS" ;;
        gemini)     allowlist_var="OCTOPUS_GEMINI_ALLOWED_MODELS" ;;
        agy)        allowlist_var="OCTOPUS_AGY_ALLOWED_MODELS" ;;
        claude-sdk) allowlist_var="OCTOPUS_CLAUDE_SDK_ALLOWED_MODELS" ;;
        claude)     allowlist_var="OCTOPUS_CLAUDE_ALLOWED_MODELS" ;;
        openrouter) allowlist_var="OCTOPUS_OPENROUTER_ALLOWED_MODELS" ;;
        atlascloud) allowlist_var="ATLASCLOUD_ALLOWED_MODELS" ;;
        openai-compatible|openai-tools|openai-compatible-agent) allowlist_var="OPENAI_COMPAT_ALLOWED_MODELS" ;;
        perplexity) allowlist_var="OCTOPUS_PERPLEXITY_ALLOWED_MODELS" ;;
        qwen)       allowlist_var="OCTOPUS_QWEN_ALLOWED_MODELS" ;;
        cursor-agent) allowlist_var="OCTOPUS_CURSOR_AGENT_ALLOWED_MODELS" ;;
        opencode)   allowlist_var="OCTOPUS_OPENCODE_ALLOWED_MODELS" ;;
        *)          return 0 ;;  # Unknown provider — allow
    esac

    local allowlist="${!allowlist_var:-}"
    [[ -z "$allowlist" ]] && return 0  # No allowlist = all allowed

    # Check if model is in comma-separated allowlist
    # v9.5: bash builtin substring check (zero subshells, was echo|grep)
    if [[ ",$allowlist," == *",$model,"* ]]; then
        return 0
    fi

    log WARN "Model '$model' blocked by $allowlist_var (allowed: $allowlist)"
    # v8.49.0: Use capability-aware fallback instead of naive first-in-list
    local fallback=""
    if command -v find_capable_fallback &>/dev/null 2>&1; then
        # Try to find a model with matching capabilities that IS in the allowlist
        local capable
        capable=$(find_capable_fallback "$model" "$provider" 2>/dev/null) || true
        if [[ -n "$capable" ]] && [[ ",$allowlist," == *",$capable,"* ]]; then
            fallback="$capable"
            log WARN "Capability-aware fallback: $fallback (matches blocked model's capabilities)"
        fi
    fi
    # Final fallback: first allowed model if capability match not found
    if [[ -z "$fallback" ]]; then
        fallback=$(echo "$allowlist" | cut -d',' -f1)
        log WARN "Falling back to first allowed: $fallback"
    fi
    echo "$fallback"
    return 1
}

apply_tool_policy() {
    local role="$1"
    local prompt="$2"
    local agent_name="${3:-}"   # v8.53.0: optional agent name for readonly check

    # Disabled by env var
    if [[ "${OCTOPUS_TOOL_POLICIES}" != "true" ]]; then
        echo "$prompt"
        return
    fi

    # v8.53.0: readonly: true in frontmatter takes precedence over role-based policy
    if [[ -n "$agent_name" ]]; then
        local is_readonly
        is_readonly=$(get_agent_readonly "$agent_name")
        if [[ "$is_readonly" == "true" ]]; then
            echo "TOOL POLICY (readonly: true): You MUST NOT use Write, Edit, or Bash for modifications. Only Read, Glob, Grep, WebSearch, and WebFetch are permitted.

${prompt}"
            return
        fi
    fi

    local policy
    policy=$(get_tool_policy "$role")

    local restriction=""
    case "$policy" in
        read_search)
            restriction="TOOL POLICY: You MUST NOT use Write, Edit, or Bash for modifications. Only Read, Glob, Grep, WebSearch, and WebFetch are permitted for this role."
            ;;
        read_exec)
            restriction="TOOL POLICY: You MUST NOT use Write or Edit. You may use Bash for read-only commands like running tests. Read, Glob, Grep are permitted."
            ;;
        read_communicate)
            restriction="TOOL POLICY: You MUST NOT use Write, Edit, or Bash. Only Read, Glob, and Grep are permitted for this role."
            ;;
        full)
            # No restrictions
            echo "$prompt"
            return
            ;;
    esac

    if [[ -n "$restriction" ]]; then
        echo "${restriction}

${prompt}"
    else
        echo "$prompt"
    fi
}

# Apply persona instruction to a prompt
# Usage: apply_persona <role> <prompt>
# Returns: Enhanced prompt with persona prefix
apply_persona() {
    local role="$1"
    local prompt="$2"
    local skip_persona="${3:-false}"
    local agent_name="${4:-}"   # v8.53.0: optional agent name for readonly policy

    # Allow opt-out for backward compatibility
    if [[ "$skip_persona" == "true" || "$DISABLE_PERSONAS" == "true" ]]; then
        echo "$prompt"
        return
    fi

    local persona
    persona=$(get_persona_instruction "$role")

    if [[ -z "$persona" ]]; then
        echo "$prompt"
        return
    fi

    # Combine persona with original prompt
    local combined
    combined=$(cat << EOF
$persona

---

**Task:**
$prompt
EOF
)

    # v8.19.0: Apply tool policy RBAC (v8.53.0: pass agent_name for readonly check)
    combined=$(apply_tool_policy "$role" "$combined" "$agent_name")

    echo "$combined"
}

# v8.53.0: Get readonly flag from agent persona frontmatter
# Returns "true" if the persona file has "readonly: true" in its YAML frontmatter.
# Falls back to user-scope agents dir (USER_AGENTS_DIR) if not in plugin personas.
# Parses only within --- frontmatter delimiters to avoid false positives in body content.
get_agent_readonly() {
    local agent_name="$1"
    local persona_file="${PLUGIN_DIR}/agents/personas/${agent_name}.md"

    if [[ ! -f "$persona_file" ]]; then
        persona_file="${USER_AGENTS_DIR:-${HOME}/.claude/agents}/${agent_name}.md"
    fi

    [[ ! -f "$persona_file" ]] && echo "false" && return

    # Extract only YAML frontmatter (between --- delimiters), then grep for readonly
    local val
    val=$(awk '
        BEGIN { in_fm=0; past_fm=0 }
        /^---$/ && !past_fm { in_fm=!in_fm; if (!in_fm) past_fm=1; next }
        in_fm && /^readonly:/ { print; exit }
    ' "$persona_file" | sed 's/readonly:[[:space:]]*//' | tr -d '"' | tr '[:upper:]' '[:lower:]')
    echo "${val:-false}"
}


# ── Extracted from orchestrate.sh ──
find_capable_fallback() {
    local blocked_model="$1"
    local provider="$2"

    # Get capabilities of the blocked model
    local catalog
    catalog=$(get_model_catalog "$blocked_model")
    local req_ctx req_tools req_images req_reasoning _prov _tier _status
    IFS='|' read -r req_ctx req_tools req_images req_reasoning _prov _tier _status <<< "$catalog"

    # Get all models for this provider, sorted by cost (cheapest first)
    local -a candidates=()
    case "$provider" in
        codex)
            # The Codex seat is subscription-pinned. Never substitute a fast,
            # mini, API-priced, or otherwise different model.
            candidates=(gpt-5.6-sol) ;;
        gemini)
            candidates=(gemini-3-flash-preview gemini-3.1-pro-preview) ;;
        agy)
            candidates=(default) ;;
        claude)
            candidates=(claude-sonnet-4.6 claude-opus-4.6) ;;
        openrouter)
            candidates=(z-ai/glm-5.2 moonshotai/kimi-k3 z-ai/glm-5 moonshotai/kimi-k2.5 deepseek/deepseek-r1-0528) ;;
        perplexity)
            candidates=(sonar sonar-pro) ;;
        cursor-agent)
            candidates=(composer-2-fast composer-2 grok-4-20 grok-4-20-thinking) ;;
    esac

    for candidate in "${candidates[@]}"; do
        [[ "$candidate" == "$blocked_model" ]] && continue

        local c_catalog
        c_catalog=$(get_model_catalog "$candidate")
        local c_ctx c_tools c_images c_reasoning
        IFS='|' read -r c_ctx c_tools c_images c_reasoning _ _ _ <<< "$c_catalog"

        # Check capability match
        [[ "$req_tools" == "yes" && "$c_tools" != "yes" ]] && continue
        [[ "$req_images" == "yes" && "$c_images" != "yes" ]] && continue
        [[ "$req_reasoning" == "yes" && "$c_reasoning" != "yes" ]] && continue

        echo "$candidate"
        return 0
    done

    # No capable fallback found
    return 1
}
