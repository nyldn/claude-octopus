#!/usr/bin/env bash
# Agent spec helpers. A spec may be a legacy executor alias (e.g. codex-review)
# or a model-qualified seat (e.g. commandcode:minimaxai/minimax-m3).
# Source-safe: defines functions only.

# Provider routing ceilings are byte-based. Bash's ${#value} counts characters
# in UTF-8 locales, so measure under the C locale before evaluating a provider.
octo_prompt_byte_length() {
    local prompt="${1:-}" bytes
    bytes="$(LC_ALL=C printf '%s' "$prompt" | wc -c | tr -d '[:space:]')" || return 1
    [[ "$bytes" =~ ^[0-9]+$ ]] || return 1
    printf '%s\n' "$bytes"
}

octo_agent_spec_executor() {
    local spec="${1:-}"
    printf '%s\n' "${spec%%:*}"
}

octo_agent_spec_provider() {
    local executor
    executor="$(octo_agent_spec_executor "${1:-}")"
    if declare -f octo_provider_canonical >/dev/null 2>&1; then
        octo_provider_canonical "$executor" 2>/dev/null && return 0
    fi
    case "$executor" in
        codex|codex-*) echo codex ;;
        commandcode|commandcode-*) echo commandcode ;;
        claude-sdk|claude-sdk-*) echo claude-sdk ;;
        claude|claude-*) echo claude ;;
        gemini|gemini-*) echo gemini ;;
        agy|agy-*|antigravity) echo agy ;;
        perplexity|perplexity-*) echo perplexity ;;
        openrouter|openrouter-*) echo openrouter ;;
        opencode|opencode-*) echo opencode ;;
        openai-compatible|openai-compatible-*) echo openai-compatible ;;
        atlascloud|atlascloud-*) echo atlascloud ;;
        qwen|qwen-*) echo qwen ;;
        grok|grok-*) echo grok ;;
        cursor-agent|cursor-agent-*) echo cursor-agent ;;
        copilot|copilot-*) echo copilot ;;
        vibe|vibe-*) echo vibe ;;
        kimi|kimi-*) echo kimi ;;
        ollama|ollama-*) echo ollama ;;
        *) echo "$executor" ;;
    esac
}

octo_agent_spec_explicit_model() {
    local spec="${1:-}"
    [[ "$spec" == *:* ]] || return 1
    local model="${spec#*:}"
    [[ -n "$model" ]] || return 1
    printf '%s\n' "$model"
}

# Parse one provider-status record without applying caller-specific provider
# normalization. Versioned records are v2|provider|model|status|detail; legacy
# records are provider|status|detail. Detail may itself contain pipe characters.
octo_parse_provider_status_record() {
    local record="${1-}" field1 field2 field3 field4 remainder
    OCTO_PROVIDER_STATUS_PROVIDER=""
    OCTO_PROVIDER_STATUS_MODEL=""
    OCTO_PROVIDER_STATUS_VALUE=""
    OCTO_PROVIDER_STATUS_DETAIL=""

    IFS='|' read -r field1 field2 field3 field4 remainder <<< "$record"
    [[ -n "$field1" ]] || return 1

    if [[ "$field1" == "v2" ]]; then
        OCTO_PROVIDER_STATUS_PROVIDER="$field2"
        OCTO_PROVIDER_STATUS_MODEL="$field3"
        OCTO_PROVIDER_STATUS_VALUE="$field4"
        OCTO_PROVIDER_STATUS_DETAIL="$remainder"
    else
        OCTO_PROVIDER_STATUS_PROVIDER="$field1"
        OCTO_PROVIDER_STATUS_VALUE="$field2"
        OCTO_PROVIDER_STATUS_DETAIL="${field3}${field4:+|${field4}}${remainder:+|${remainder}}"
    fi
}

# Run-contract identity keeps legacy executor aliases unchanged, but exact
# provider:model seats must use separate canonical provider and model fields.
octo_agent_spec_contract_provider() {
    local spec="${1:-unknown}" provider
    if [[ "$spec" != *:* ]]; then
        printf '%s\n' "$spec"
        return 0
    fi
    provider="$(octo_agent_spec_provider "$spec")" || return 1
    [[ -n "$provider" ]] || return 1
    printf '%s\n' "$provider"
}

octo_agent_spec_contract_model() {
    local spec="${1:-}" fallback="${2:-}"
    if [[ "$spec" == *:* ]]; then
        octo_agent_spec_explicit_model "$spec"
    else
        printf '%s\n' "$fallback"
    fi
}

# Normalize a model-qualified seat to the executable name consumed by
# dispatch.sh. Provider aliases belong at the configuration boundary; runtime
# agent specs must use dispatchable executors.
octo_agent_spec_canonicalize_exact() {
    local spec="${1-}" executor model provider canonical_executor
    [[ -n "$spec" && "$spec" == *:* ]] || return 1
    [[ "$spec" != *[[:space:]]* && "$spec" != *\\* ]] || return 1

    executor="${spec%%:*}"
    model="${spec#*:}"
    [[ -n "$executor" && -n "$model" ]] || return 1
    provider="$(octo_provider_canonical "$executor" 2>/dev/null)" || return 1

    case "$provider" in
        atlascloud) canonical_executor="atlascloud-agent" ;;
        *) canonical_executor="$provider" ;;
    esac

    octo_provider_has_capability "$provider" dispatch || return 1

    # Exact contextual seats are serialized into a shell command string and
    # later split into argv. Keep the accepted model grammar to one safe token.
    case "$model" in
        /*|*[[:space:]]*|*\\*|*\**|*";"*|*"|"*|*"&"*|*'$'*|*'`'*|*"'"*|*'"'*|*"("*|*")"*|*"<"*|*">"*|*"!"*|*"?"*|*"["*|*"]"*|*"{"*|*"}"*) return 1 ;;
    esac

    printf '%s:%s\n' "$canonical_executor" "$model"
}

# Return the environment variable that constrains models for a canonical
# provider. Dispatch and review-seat previews share this map so a preview can
# never advertise an exact model that runtime dispatch will reject.
octo_provider_model_allowlist_var() {
    local provider="${1:-}"
    provider="$(octo_agent_spec_provider "$provider")"
    case "$provider" in
        gemini) provider="agy" ;;
    esac

    case "$provider" in
        codex) echo "OCTOPUS_CODEX_ALLOWED_MODELS" ;;
        agy) echo "OCTOPUS_AGY_ALLOWED_MODELS" ;;
        claude-sdk) echo "OCTOPUS_CLAUDE_SDK_ALLOWED_MODELS" ;;
        claude) echo "OCTOPUS_CLAUDE_ALLOWED_MODELS" ;;
        openrouter) echo "OCTOPUS_OPENROUTER_ALLOWED_MODELS" ;;
        orcarouter) echo "OCTOPUS_ORCAROUTER_ALLOWED_MODELS" ;;
        atlascloud|atlascloud-agent) echo "ATLASCLOUD_ALLOWED_MODELS" ;;
        openai-compatible|openai-tools|openai-compatible-agent) echo "OPENAI_COMPAT_ALLOWED_MODELS" ;;
        perplexity) echo "OCTOPUS_PERPLEXITY_ALLOWED_MODELS" ;;
        qwen) echo "OCTOPUS_QWEN_ALLOWED_MODELS" ;;
        cursor-agent) echo "OCTOPUS_CURSOR_AGENT_ALLOWED_MODELS" ;;
        commandcode) echo "OCTOPUS_COMMANDCODE_ALLOWED_MODELS" ;;
        opencode) echo "OCTOPUS_OPENCODE_ALLOWED_MODELS" ;;
        ollama) echo "OCTOPUS_OLLAMA_ALLOWED_MODELS" ;;
        copilot) echo "OCTOPUS_COPILOT_ALLOWED_MODELS" ;;
        vibe) echo "OCTOPUS_VIBE_ALLOWED_MODELS" ;;
        *) return 1 ;;
    esac
}

octo_agent_spec_exact_model_allowed() {
    local spec="${1:-}" model allowlist_var allowlist
    model="$(octo_agent_spec_explicit_model "$spec")" || return 1
    allowlist_var="$(octo_provider_model_allowlist_var "$spec" 2>/dev/null || true)"
    [[ -n "$allowlist_var" ]] || return 0
    allowlist="${!allowlist_var:-}"
    [[ -z "$allowlist" || ",$allowlist," == *",$model,"* ]]
}

octo_agent_spec_is_security_dispatch() {
    local combined="${1:-} ${2:-} ${3:-}"
    case "$combined" in
        *security*|*squeeze*|*red-team*|*redteam*) return 0 ;;
        *) return 1 ;;
    esac
}

octo_agent_spec_exact_role_allowed() {
    local spec="${1:-}" role="${2:-}" phase="${3:-}" provider model
    provider="$(octo_agent_spec_provider "$spec")"
    model="$(octo_agent_spec_explicit_model "$spec")" || return 1
    case "$provider" in
        claude|claude-sdk)
            case "$model" in
                claude-fable-5|claude-fable-5-1)
                    octo_agent_spec_is_security_dispatch "$role" "$spec" "$phase" && return 1
                    ;;
            esac
            ;;
    esac
    return 0
}

octo_agent_spec_slug() {
    local spec="${1:-unknown}"
    # Keep the full seat identity while making it safe for filenames and
    # colon-delimited ledgers. Repeated separators collapse deterministically.
    printf '%s' "$spec" | sed -E 's/[^A-Za-z0-9._-]+/_/g; s/^_+//; s/_+$//'
}

octo_model_family() {
    local spec="${1:-}" effective_model="${2:-}"
    local executor model prefix
    executor="$(octo_agent_spec_executor "$spec")"
    model="$effective_model"
    if [[ -z "$model" ]]; then
        model="$(octo_agent_spec_explicit_model "$spec" 2>/dev/null || true)"
    fi

    case "$model" in
        anthropic/*|*claude*) echo anthropic; return ;;
        minimaxai/*|minimax/*|*minimax*) echo minimax; return ;;
        deepseek/*|*deepseek*) echo deepseek; return ;;
        openai/*|gpt-*|o[0-9]*|*chatgpt*) echo openai; return ;;
        google/*|*gemini*) echo google; return ;;
        qwen/*|alibaba/*|*qwen*) echo alibaba; return ;;
        composer*) echo cursor; return ;;
        x-ai/*|xai/*|*grok*) echo xai; return ;;
        mistralai/*|*mistral*) echo mistral; return ;;
        stealth/*) echo stealth; return ;;
        */*)
            prefix="${model%%/*}"
            [[ -n "$prefix" ]] && { printf '%s\n' "$prefix"; return; }
            ;;
    esac

    case "$executor" in
        codex|codex-*) echo openai ;;
        claude|claude-*) echo anthropic ;;
        gemini|gemini-*|agy|agy-*|antigravity) echo google ;;
        qwen|qwen-*) echo alibaba ;;
        grok|grok-*|cursor-grok-*) echo xai ;;
        cursor-agent|cursor-agent-*|composer|composer-*) echo cursor ;;
        vibe|vibe-*) echo mistral ;;
        kimi|kimi-*) echo moonshot ;;
        perplexity|perplexity-*) echo perplexity ;;
        copilot|copilot-*) echo microsoft ;;
        commandcode|commandcode-*|openrouter|openrouter-*|opencode|opencode-*|openai-compatible|openai-compatible-*|atlascloud|atlascloud-*) echo multi ;;
        ollama|ollama-*) echo local ;;
        *) echo unknown ;;
    esac
}
