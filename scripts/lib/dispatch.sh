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
# - Google Gemini 3.0: gemini-3.1-pro-preview, gemini-3-flash-preview, gemini-3-pro-image-preview
# Note: "API-key only" models require OPENAI_API_KEY; they are NOT available via ChatGPT subscription/OAuth.
get_agent_command() {
    local agent_type="$1"
    local phase="${2:-}"
    local role="${3:-}"
    local model=""

    # Configurable sandbox mode (v7.13.1 - Issue #9)
    # Priority: OCTOPUS_CODEX_SANDBOX env var > default (workspace-write)
    # Valid values: workspace-write (default), write, read-only
    local codex_sandbox="${OCTOPUS_CODEX_SANDBOX:-workspace-write}"

    # Security: reject values not in allowlist
    case "$codex_sandbox" in
        workspace-write|write|read-only)
            ;;
        *)
            log "ERROR" "Invalid OCTOPUS_CODEX_SANDBOX value: '${codex_sandbox}'. Allowed: workspace-write, write, read-only"
            log "ERROR" "Falling back to workspace-write for safety."
            codex_sandbox="workspace-write"
            ;;
    esac

    local sandbox_flag="--sandbox ${codex_sandbox}"

    case "$agent_type" in
        codex|codex-standard|codex-max|codex-mini|codex-general)
            model=$(get_agent_model "$agent_type" "$phase" "$role")
            echo "codex exec --skip-git-repo-check --model ${model} ${sandbox_flag} -"
            ;;
        codex-spark)  # v8.9.0: Ultra-fast Spark model (1000+ tok/s)
            model=$(get_agent_model "$agent_type" "$phase" "$role")
            echo "codex exec --skip-git-repo-check --model ${model} ${sandbox_flag} -"
            ;;
        codex-reasoning)  # v8.9.0: Reasoning models (o3, o3)
            model=$(get_agent_model "$agent_type" "$phase" "$role")
            echo "codex exec --skip-git-repo-check --model ${model} ${sandbox_flag} -"
            ;;
        codex-large-context)  # v8.9.0: 1M context models (gpt-4.1)
            model=$(get_agent_model "$agent_type" "$phase" "$role")
            echo "codex exec --skip-git-repo-check --model ${model} ${sandbox_flag} -"
            ;;
        gemini|gemini-fast|gemini-image)
            model=$(get_agent_model "$agent_type" "$phase" "$role")
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
            local gemini_flags="-o text --approval-mode yolo"
            case "${OCTOPUS_GEMINI_SANDBOX:-headless}" in
                interactive|prompt-mode) gemini_flags="" ;;
            esac
            echo "${gemini_env} ${gemini_exec} ${model} ${gemini_flags}"
            ;;
        codex-review) echo "codex exec --skip-git-repo-check review" ;; # Code review mode (no sandbox support)
        claude) echo "claude${_BARE_OPT} --print" ;;                         # Claude Sonnet 4.6
        claude-sonnet) echo "claude${_BARE_OPT} --print --model sonnet" ;;        # Claude Sonnet explicit
        claude-opus)
            # v9.23: Opus alias — resolves to 4.7 on Anthropic API (v2.1.111+), 4.6 on Bedrock/Vertex.
            # Use `env VAR=val` prefix so the assignment survives read -ra word-splitting
            # in spawn.sh — a bare VAR=val prefix only works in shell eval context.
            if [[ "${SUPPORTS_XHIGH_EFFORT:-false}" == "true" ]]; then
                echo "env CLAUDE_CODE_EFFORT_LEVEL=xhigh claude${_BARE_OPT} --print --model opus"
            else
                echo "claude${_BARE_OPT} --print --model opus"
            fi
            ;;
        claude-opus-fast) echo "claude${_BARE_OPT} --print --model claude-opus-4-6 --fast" ;; # Claude Opus 4.6 Fast (v8.4: v2.1.36+) — pinned to 4.6 (no 4.7 fast variant)
        claude-opus-legacy) echo "claude${_BARE_OPT} --print --model claude-opus-4-6" ;; # v9.23: explicit 4.6 opt-in
        openrouter) echo "openrouter_execute" ;;                 # OpenRouter API (v4.8)
        openrouter-glm5) echo "openrouter_execute_model z-ai/glm-5" ;;           # v8.11.0: GLM-5 via OpenRouter
        openrouter-kimi) echo "openrouter_execute_model moonshotai/kimi-k2.5" ;; # v8.11.0: Kimi K2.5 via OpenRouter
        openrouter-deepseek) echo "openrouter_execute_model deepseek/deepseek-r1-0528" ;; # v8.11.0: DeepSeek R1 via OpenRouter
        perplexity|perplexity-fast)  # v8.24.0: Perplexity Sonar — web-grounded research (Issue #22)
            model=$(get_agent_model "$agent_type" "$phase" "$role")
            echo "perplexity_execute $model"
            ;;
        copilot|copilot-research)  # v9.9.0: GitHub Copilot CLI — copilot -p (Issue #198)
            # -s: silent (no footer noise), --disable-builtin-mcps: skip MCP startup latency
            echo "copilot --no-ask-user -s --disable-builtin-mcps"
            ;;
        ollama|ollama-*)  # v9.9.0: Ollama local LLM — ollama run
            model=$(get_agent_model "$agent_type" "$phase" "$role")
            echo "ollama run $model"
            ;;
        qwen|qwen-research)  # v9.10.0: Qwen CLI — fork of Gemini CLI (free tier)
            echo "env NODE_NO_WARNINGS=1 qwen -o text --approval-mode yolo"
            ;;
        cursor-agent)  # v9.23.0: Cursor Agent CLI — Grok 4.20 via Cursor subscription
            model=$(get_agent_model "$agent_type" "$phase" "$role")
            # NOTE: bare ${model} (no quotes) — downstream uses `read -ra` which
            # does NOT interpret quotes; literal " would be passed to --model.
            echo "agent --trust --output-format text --model ${model}"
            ;;
        opencode|opencode-fast|opencode-research)  # v9.11.0: OpenCode CLI — multi-provider router
            model=$(get_agent_model "$agent_type" "$phase" "$role")
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

enforce_context_budget() {
    local prompt="$1"
    local role="${2:-}"
    local budget="${OCTOPUS_CONTEXT_BUDGET:-12000}"

    # v9.3.0: Scale budget by role proportion
    if [[ -n "$role" ]]; then
        local proportion
        proportion=$(get_role_budget_proportion "$role")
        budget=$((budget * proportion / 100))
    fi

    # Rough token estimate: ~4 chars per token
    local char_budget=$((budget * 4))

    if [[ ${#prompt} -gt $char_budget ]]; then
        log "DEBUG" "Context budget: truncating prompt from ${#prompt} to $char_budget chars (~$budget tokens)"
        echo "${prompt:0:$char_budget}

[... truncated to fit context budget of ~$budget tokens ...]"
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
        claude*)     provider="claude" ;;
        openrouter*) provider="openrouter" ;;
        perplexity*) provider="perplexity" ;;
        qwen*)       provider="qwen" ;;
        cursor-agent*) provider="cursor-agent" ;;
        opencode*)   provider="opencode" ;;
    esac

    local resolved_model
    resolved_model=$(resolve_octopus_model "$provider" "$agent_type" "$phase" "$role")

    # v8.31.0: Apply model restriction service if configured
    if [[ -n "$provider" ]]; then
        local fallback
        fallback=$(validate_model_allowed "$provider" "$resolved_model")
        if [[ $? -ne 0 && -n "$fallback" ]]; then
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
        claude)     allowlist_var="OCTOPUS_CLAUDE_ALLOWED_MODELS" ;;
        openrouter) allowlist_var="OCTOPUS_OPENROUTER_ALLOWED_MODELS" ;;
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
