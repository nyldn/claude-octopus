#!/usr/bin/env bash
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

get_agent_command() {
    local agent_type="$1"
    local phase="${2:-}"
    local role="${3:-}"
    local model=""
    # Allow swapping the claude binary (e.g. clarp = subscription-billed drop-in
    # for `claude -p`, instead of metered API). Default unchanged. May include
    # args (word-split downstream by read -ra), e.g. "clarp --strict-mcp-config".
    local _claude_bin="${OCTOPUS_CLAUDE_BIN:-claude}"

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
    local codex_bin="${OCTOPUS_CODEX_BIN:-codex}"

    # Allow advanced users to point Octopus at a codex-compatible wrapper
    # without replacing codex on PATH. Keep this restricted because the value
    # is interpolated into the shell command string returned below.
    if [[ ! "$codex_bin" =~ ^[A-Za-z0-9_./-]+$ ]]; then
        log "ERROR" "Invalid OCTOPUS_CODEX_BIN value: '${codex_bin}'. Allowed characters: A-Z a-z 0-9 _ . / -"
        log "ERROR" "Falling back to codex for safety."
        codex_bin="codex"
    fi

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
        codex|codex-standard|codex-max|codex-mini|codex-general)
            if ! model=$(get_agent_model "$agent_type" "$phase" "$role"); then
                return 1
            fi
            echo "${codex_bin} exec --skip-git-repo-check --model ${model} ${sandbox_flag} -"
            ;;
        codex-spark)  # v8.9.0: Ultra-fast Spark model (1000+ tok/s)
            if ! model=$(get_agent_model "$agent_type" "$phase" "$role"); then
                return 1
            fi
            echo "${codex_bin} exec --skip-git-repo-check --model ${model} ${sandbox_flag} -"
            ;;
        codex-reasoning)  # v8.9.0: Reasoning models (o3, o3)
            if ! model=$(get_agent_model "$agent_type" "$phase" "$role"); then
                return 1
            fi
            echo "${codex_bin} exec --skip-git-repo-check --model ${model} ${sandbox_flag} -"
            ;;
        codex-large-context)  # v8.9.0: 1M context models (gpt-4.1)
            if ! model=$(get_agent_model "$agent_type" "$phase" "$role"); then
                return 1
            fi
            echo "${codex_bin} exec --skip-git-repo-check --model ${model} ${sandbox_flag} -"
            ;;
        gemini|gemini-fast|gemini-image)
            local gemini_flags="-o text --approval-mode yolo"
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
        codex-review) echo "${codex_bin} exec --skip-git-repo-check review" ;; # Code review mode (no sandbox support)
        claude) echo "${_claude_bin}${_BARE_OPT} --print ${claude_perm}" ;;                         # Claude Sonnet 4.6
        claude-sonnet) echo "${_claude_bin}${_BARE_OPT} --print --model sonnet ${claude_perm}" ;;        # Claude Sonnet explicit
        claude-opus)
            # v9.42: Opus alias — resolves to 4.8 on Claude Code v2.1.154+,
            # then 4.7/4.6 on older hosts or enterprise backends.
            # Use `env VAR=val` prefix so the assignment survives read -ra word-splitting
            # in spawn.sh — a bare VAR=val prefix only works in shell eval context.
            local opus_effort="high"
            if declare -f get_effort_level >/dev/null 2>&1; then
                local opus_complexity="2"
                case "${phase:-}" in
                    tangle|develop|ink|deliver) opus_complexity="3" ;;
                esac
                opus_effort="$(get_effort_level "${phase:-unknown}" "$opus_complexity")"
                opus_effort="${opus_effort:-high}"
            elif [[ -n "${OCTOPUS_EFFORT_OVERRIDE:-}" ]]; then
                opus_effort="$OCTOPUS_EFFORT_OVERRIDE"
            fi
            if [[ "${SUPPORTS_EFFORT_COMMAND:-false}" == "true" || "${SUPPORTS_XHIGH_EFFORT:-false}" == "true" ]]; then
                echo "env CLAUDE_CODE_EFFORT_LEVEL=${opus_effort} ${_claude_bin}${_BARE_OPT} --print --model opus ${claude_perm}"
            else
                echo "${_claude_bin}${_BARE_OPT} --print --model opus ${claude_perm}"
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
        openrouter-kimi) echo "openrouter_execute_model moonshotai/kimi-k2.5" ;; # v8.11.0: Kimi K2.5 via OpenRouter
        openrouter-deepseek) echo "openrouter_execute_model deepseek/deepseek-r1-0528" ;; # v8.11.0: DeepSeek R1 via OpenRouter
        openai-compatible-agent)  # Generic OpenAI-compatible tool-loop agent
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
            echo "${PLUGIN_DIR}/scripts/helpers/openai-compatible-agent.py --provider generic --model ${model} --cwd ${PWD}"
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
            echo "ollama run $model"
            ;;
        qwen|qwen-research)  # v9.10.0: Qwen CLI — fork of Gemini CLI
            # oco-dar: NO_BROWSER=1 stops a stale token from hijacking the user's
            # browser into the OAuth device-flow. Pre-flight (qwen_is_usable) should
            # already gate this out; this is defense-in-depth if dispatch is reached.
            echo "env NODE_NO_WARNINGS=1 NO_BROWSER=1 qwen -o text --approval-mode yolo"
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
            echo "opencode run ${oc_model_flag}"
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
        claude-opus*|claude-sonnet|claude) echo "${OCTOPUS_CLAUDE_CONTEXT_BUDGET:-${default_budget}}" ; return 0 ;;
    esac

    case "$provider" in
        codex)      echo "${OCTOPUS_CODEX_CONTEXT_BUDGET:-${default_budget}}" ;;
        gemini)     echo "${OCTOPUS_GEMINI_CONTEXT_BUDGET:-${default_budget}}" ;;
        agy|antigravity) echo "${OCTOPUS_AGY_CONTEXT_BUDGET:-${default_budget}}" ;;
        claude)     echo "${OCTOPUS_CLAUDE_CONTEXT_BUDGET:-${default_budget}}" ;;
        perplexity) echo "${OCTOPUS_PERPLEXITY_CONTEXT_BUDGET:-${default_budget}}" ;;
        openrouter) echo "${OCTOPUS_OPENROUTER_CONTEXT_BUDGET:-${default_budget}}" ;;
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
        claude*)     provider="claude" ;;
        openrouter*) provider="openrouter" ;;
        openai-compatible-agent*) provider="openai-compatible-agent" ;;
        perplexity*) provider="perplexity" ;;
        qwen*)       provider="qwen" ;;
        cursor-agent*) provider="cursor-agent" ;;
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
        claude)     allowlist_var="OCTOPUS_CLAUDE_ALLOWED_MODELS" ;;
        openrouter) allowlist_var="OCTOPUS_OPENROUTER_ALLOWED_MODELS" ;;
        openai-compatible-agent) allowlist_var="OPENAI_COMPAT_ALLOWED_MODELS" ;;
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
            candidates=(gpt-5.4-mini gpt-5.2-codex gpt-5.3-codex gpt-5.4 gpt-5.4-pro o3) ;;
        gemini)
            candidates=(gemini-3-flash-preview gemini-3.1-pro-preview) ;;
        agy)
            candidates=(default) ;;
        claude)
            candidates=(claude-sonnet-4.6 claude-opus-4.6) ;;
        openrouter)
            candidates=(z-ai/glm-5 moonshotai/kimi-k2.5 deepseek/deepseek-r1-0528) ;;
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
