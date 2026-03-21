#!/usr/bin/env bash
# Perplexity & OpenRouter API execution
# Extracted from orchestrate.sh — v9.7.5

# OpenRouter agent wrapper for spawn_agent compatibility
openrouter_execute() {
    local prompt="$1"
    local task_type="${2:-general}"
    local complexity="${3:-2}"
    local output_file="${4:-}"

    if [[ -n "$output_file" ]]; then
        execute_openrouter "$prompt" "$task_type" "$complexity" > "$output_file" 2>&1
    else
        execute_openrouter "$prompt" "$task_type" "$complexity"
    fi
}

# OpenRouter model-specific agent wrapper (v8.11.0)
# Used by openrouter-glm5, openrouter-kimi, openrouter-deepseek
# First arg is the fixed model ID, remaining args are prompt/task/complexity/output
openrouter_execute_model() {
    local model="$1"
    local prompt="$2"
    local task_type="${3:-general}"
    local complexity="${4:-2}"
    local output_file="${5:-}"

    if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
        log ERROR "OPENROUTER_API_KEY not set"
        return 1
    fi

    [[ "$VERBOSE" == "true" ]] && log DEBUG "OpenRouter model-specific request: model=$model" || true

    # Build JSON payload
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

    # Extract content from response
    local content=""
    if json_extract "$response" "content"; then
        content="$REPLY"
    fi

    if [[ -z "$content" ]]; then
        if [[ "$response" =~ \"error\":\{([^\}]*)\} ]]; then
            log ERROR "OpenRouter error: ${BASH_REMATCH[1]}"
            return 1
        fi
        log WARN "Empty response from OpenRouter ($model)"
        echo "$response"
    else
        local result
        result=$(echo "$content" | sed 's/\\n/\n/g; s/\\t/\t/g; s/\\"/"/g')
        if [[ -n "$output_file" ]]; then
            echo "$result" > "$output_file"
        else
            echo "$result"
        fi
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# PERPLEXITY SONAR API (v8.24.0 - Issue #22)
# Web-grounded research provider — live internet search with citations
# Env: PERPLEXITY_API_KEY required
# Models: sonar-pro (deep research), sonar (fast search)
# ═══════════════════════════════════════════════════════════════════════════════

perplexity_execute() {
    local model="$1"
    local prompt="$2"
    local output_file="${3:-}"

    if [[ -z "${PERPLEXITY_API_KEY:-}" ]]; then
        log ERROR "PERPLEXITY_API_KEY not set — get one at https://www.perplexity.ai/settings/api"
        return 1
    fi

    [[ "$VERBOSE" == "true" ]] && log DEBUG "Perplexity Sonar request: model=$model" || true

    # Build JSON payload — Perplexity uses OpenAI-compatible chat completions API
    local escaped_prompt
    escaped_prompt=$(json_escape "$prompt")

    local payload
    payload=$(cat << EOF
{
  "model": "$model",
  "messages": [
    {"role": "system", "content": "You are a research assistant with live web access. Provide detailed, factual answers with citations. Always include source URLs when referencing specific information."},
    {"role": "user", "content": "$escaped_prompt"}
  ]
}
EOF
)

    local response
    response=$(curl -s -X POST "https://api.perplexity.ai/chat/completions" \
        -H "Authorization: Bearer ${PERPLEXITY_API_KEY}" \
        -H "Content-Type: application/json" \
        -H "Connection: keep-alive" \
        -d "$payload")

    # Extract content from response (same format as OpenAI-compatible API)
    local content=""
    if json_extract "$response" "content"; then
        content="$REPLY"
    fi

    # Extract citations if available (Perplexity-specific field)
    local citations=""
    if command -v jq &>/dev/null; then
        citations=$(echo "$response" | jq -r '.citations // [] | to_entries[] | "[\(.key + 1)] \(.value)"' 2>/dev/null) || true
    fi

    if [[ -z "$content" ]]; then
        if [[ "$response" =~ \"error\":\{([^\}]*)\} ]]; then
            log ERROR "Perplexity error: ${BASH_REMATCH[1]}"
            return 1
        fi
        log WARN "Empty response from Perplexity ($model)"
        echo "$response"
    else
        local result
        result=$(echo "$content" | sed 's/\\n/\n/g; s/\\t/\t/g; s/\\"/"/g')

        # Append citations if present
        if [[ -n "$citations" ]]; then
            result="${result}

---
**Sources:**
${citations}"
        fi

        if [[ -n "$output_file" ]]; then
            echo "$result" > "$output_file"
        else
            echo "$result"
        fi
    fi
}
