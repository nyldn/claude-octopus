#!/usr/bin/env bash
# Perplexity & OpenRouter API execution
# Extracted from orchestrate.sh — v9.7.5
# Hardened in v9.7.8: timeout, HTTP status handling, 429 retry, dedup

# OpenRouter model-specific agent wrapper (v8.11.0, hardened v9.7.8)
# Used by openrouter-glm5, openrouter-kimi, openrouter-deepseek
# First arg is the fixed model ID, remaining args are prompt/task/complexity/output
# Features: --max-time 60, HTTP status code handling (429 retry w/ Retry-After,
#           502/503/524 error reporting)
openrouter_execute_model() {
    local model="$1"
    local prompt="$2"
    local task_type="${3:-general}"
    local complexity="${4:-2}"
    local output_file="${5:-}"

    # stdin fallback: probe_single_agent pipes prompt via stdin (#305)
    if [[ -z "$prompt" && ! -t 0 ]]; then
        prompt=$(cat)
    fi

    if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
        log ERROR "OPENROUTER_API_KEY not set"
        return 1
    fi

    [[ "$VERBOSE" == "true" ]] && log DEBUG "OpenRouter request: model=$model" || true

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

    # Temporary file for response headers (needed for Retry-After parsing)
    local header_file
    header_file=$(mktemp "${TMPDIR:-/tmp}/octo-or-headers.XXXXXX")

    local raw_response http_code response
    local attempt=0
    local max_attempts=2  # Initial + 1 retry on 429

    while (( attempt < max_attempts )); do
        raw_response=$(curl -s -X POST "https://openrouter.ai/api/v1/chat/completions" \
            --max-time 60 \
            -w "%{http_code}" \
            -D "$header_file" \
            -H "Authorization: Bearer ${OPENROUTER_API_KEY}" \
            -H "Content-Type: application/json" \
            -H "Connection: keep-alive" \
            -H "HTTP-Referer: https://github.com/nyldn/claude-octopus" \
            -H "X-Title: Claude Octopus" \
            -d "$payload") || {
            log ERROR "OpenRouter curl failed (timeout or network error, model=$model)"
            rm -f "$header_file"
            return 1
        }

        # Split response body from HTTP status code (last 3 chars)
        http_code="${raw_response: -3}"
        response="${raw_response:0:${#raw_response}-3}"

        case "$http_code" in
            200) break ;;  # Success
            429)
                if (( attempt + 1 >= max_attempts )); then
                    log ERROR "OpenRouter rate limited (429) after retry (model=$model)"
                    rm -f "$header_file"
                    return 1
                fi
                # Parse Retry-After header (seconds); default to 5s if absent
                local retry_after=5
                local header_val
                header_val=$(grep -i '^retry-after:' "$header_file" 2>/dev/null | tr -d '\r' | sed 's/[^:]*: *//' | head -n1) || true
                if [[ -n "$header_val" && "$header_val" =~ ^[0-9]+$ ]]; then
                    retry_after="$header_val"
                    # Cap at 30s to avoid hanging
                    (( retry_after > 30 )) && retry_after=30
                fi
                log WARN "OpenRouter rate limited (429), retrying in ${retry_after}s (model=$model)"
                sleep "$retry_after"
                ;;
            502)
                log ERROR "OpenRouter bad gateway (502) — upstream provider down (model=$model)"
                rm -f "$header_file"
                return 1
                ;;
            503)
                log ERROR "OpenRouter service unavailable (503) — model may be overloaded (model=$model)"
                rm -f "$header_file"
                return 1
                ;;
            524)
                log ERROR "OpenRouter timeout (524) — upstream request took too long (model=$model)"
                rm -f "$header_file"
                return 1
                ;;
            *)
                if [[ "${http_code:0:1}" != "2" ]]; then
                    log ERROR "OpenRouter HTTP $http_code (model=$model)"
                    rm -f "$header_file"
                    return 1
                fi
                break ;;
        esac
        (( attempt++ ))
    done

    rm -f "$header_file"

    # Extract content from OpenAI-compatible nested path .choices[0].message.content.
    # `json_extract` only reads top-level keys, so it silently returned empty and the
    # caller got the raw JSON dumped to its result file. Fixed in v9.29 (issue #307).
    local content=""
    if command -v jq &>/dev/null; then
        content=$(printf '%s' "$response" | jq -re '.choices[0].message.content // empty' 2>/dev/null) || content=""
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

# OpenRouter agent wrapper for spawn_agent compatibility (v9.7.8: delegates to openrouter_execute_model)
# Resolves model from task_type/complexity, then calls the core implementation
openrouter_execute() {
    local prompt="$1"
    local task_type="${2:-general}"

    # stdin fallback: probe_single_agent pipes prompt via stdin (#305)
    if [[ -z "$prompt" && ! -t 0 ]]; then
        prompt=$(cat)
    fi
    local complexity="${3:-2}"
    local output_file="${4:-}"

    local model
    model=$(get_openrouter_model "$task_type" "$complexity")

    openrouter_execute_model "$model" "$prompt" "$task_type" "$complexity" "$output_file"
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

    # stdin fallback: probe_single_agent pipes prompt via stdin (#305)
    if [[ -z "$prompt" && ! -t 0 ]]; then
        prompt=$(cat)
    fi

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

    # Extract content from OpenAI-compatible nested path .choices[0].message.content.
    # See openrouter_execute_model above — same bug, same fix (issue #307).
    local content=""
    if command -v jq &>/dev/null; then
        content=$(printf '%s' "$response" | jq -re '.choices[0].message.content // empty' 2>/dev/null) || content=""
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
