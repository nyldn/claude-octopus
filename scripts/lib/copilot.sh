#!/usr/bin/env bash
# GitHub Copilot API execution (v9.8.0 - Issue #198)
# Extracted from orchestrate.sh — copilot_execute, token exchange, role-based model selection.
# Source-safe: no main execution block.
# ═══════════════════════════════════════════════════════════════════════════════

# Returns: ordered list of model IDs to try (org may restrict some)
# Args: $1=internal_model (e.g. copilot-premium, copilot-fast)
_copilot_model_preferences() {
    local model="$1"
    case "$model" in
        copilot-fast)
            # Fast/budget: prefer reasoning models, fall back to GPT
            echo "o3-mini gpt-4.1 gpt-4o-mini"
            ;;
        *)
            # Default copilot/copilot-premium: role is encoded by caller via agent_type
            # The prompt context drives model selection below
            echo "gpt-4.1 claude-3.7-sonnet gemini-2.0-flash gpt-4o"
            ;;
    esac
}

# Select model preferences based on agent type (role-based routing)
# GPT for code, Claude for research/plan, Gemini for refactor
# Args: $1=agent_type suffix (code|research|fast|"")
_copilot_role_model_preferences() {
    local role="$1"
    case "$role" in
        code|implementation)
            # GPT excels at implementation, code generation
            echo "gpt-4.1 claude-3.7-sonnet gemini-2.0-flash gpt-4o"
            ;;
        research|analysis|plan)
            # Claude excels at general understanding, research, planning
            echo "claude-3.7-sonnet gpt-4.1 gemini-2.0-flash"
            ;;
        fast|mini)
            # Budget/fast: prefer smaller models
            echo "o3-mini gpt-4.1 gemini-2.0-flash gpt-4o-mini"
            ;;
        refactor|review)
            # Gemini handles structured refactoring well; Claude for deep review
            echo "gemini-2.0-flash claude-3.7-sonnet gpt-4.1"
            ;;
        *)
            # Default: GPT for unknown roles (best all-rounder for coding assistant)
            echo "gpt-4.1 claude-3.7-sonnet gemini-2.0-flash gpt-4o"
            ;;
    esac
}

# Get GitHub Copilot API token via gh auth token exchange
# Caches token in session temp file (valid for ~3 hours)
# Returns: Copilot token on stdout, empty string on failure
_copilot_get_token() {
    local cache_file="${TMPDIR:-/tmp}/.octo-copilot-token-${USER:-${USERNAME:-user}}"

    # Return cached token if fresh (< 90 minutes old)
    if [[ -f "$cache_file" ]]; then
        local age_s
        age_s=$(( $(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0) ))
        if [[ $age_s -lt 5400 ]]; then
            cat "$cache_file"
            return 0
        fi
    fi

    # Get GitHub OAuth token from gh CLI
    local gh_token
    gh_token=$(gh auth token 2>/dev/null)
    if [[ -z "$gh_token" ]]; then
        log ERROR "copilot: Failed to get GitHub token — run: gh auth login"
        return 1
    fi

    # Exchange GitHub token for Copilot API token
    local token_response copilot_token
    token_response=$(curl -s \
        -H "Authorization: token $gh_token" \
        -H "Accept: application/json" \
        -H "Editor-Version: gh-copilot/1.0.0" \
        "https://api.github.com/copilot_internal/v2/token" 2>/dev/null)

    if command -v jq &>/dev/null; then
        copilot_token=$(echo "$token_response" | jq -r '.token // ""' 2>/dev/null)
    else
        copilot_token=$(echo "$token_response" | grep -o '"token":"[^"]*"' | sed 's/"token":"//;s/"$//')
    fi

    if [[ -z "$copilot_token" || "$copilot_token" == "null" ]]; then
        log ERROR "copilot: Token exchange failed — ensure you have a GitHub Copilot subscription"
        log DEBUG "copilot: Token response: ${token_response:0:200}"
        return 1
    fi

    # Cache the token securely: create with 600 perms BEFORE writing (avoids race condition)
    ( umask 177 && : > "$cache_file" ) 2>/dev/null || true
    echo "$copilot_token" > "$cache_file"
    echo "$copilot_token"
}

# Execute a prompt via GitHub Copilot API
# Args: $1=model (copilot-premium|copilot-fast|copilot-code|copilot-research),
#       $2=prompt, $3=output_file (optional)
# Note: model arg encodes role via agent_type suffix (copilot-code, copilot-research, etc.)
copilot_execute() {
    local model="$1"
    local prompt="$2"
    local output_file="${3:-}"

    # Extract role from model name for role-based model selection
    local role="${model#copilot-}"  # e.g. "copilot-code" -> "code", "copilot-premium" -> "premium"
    [[ "$role" == "premium" || "$role" == "copilot" ]] && role=""

    [[ "${VERBOSE:-}" == "true" ]] && log DEBUG "copilot_execute: model=$model, role=${role:-auto}" || true

    # Get Copilot API token
    local copilot_token
    if ! copilot_token=$(_copilot_get_token); then
        return 1
    fi

    # Get ordered model preferences based on role
    local model_prefs
    if [[ -n "$role" ]]; then
        model_prefs=$(_copilot_role_model_preferences "$role")
    else
        model_prefs=$(_copilot_model_preferences "$model")
    fi

    # Try each preferred model, fall back gracefully on org policy restrictions
    local escaped_prompt
    escaped_prompt=$(json_escape "$prompt")

    local system_prompt="You are GitHub Copilot, an AI programming assistant. Provide detailed, practical, and actionable responses. Focus on real-world implementation patterns, best practices, and concrete examples."

    for api_model in $model_prefs; do
        local payload
        payload=$(cat << EOF
{
  "model": "$api_model",
  "messages": [
    {"role": "system", "content": "$system_prompt"},
    {"role": "user", "content": "$escaped_prompt"}
  ],
  "temperature": 0.1,
  "stream": false
}
EOF
)
        log DEBUG "copilot_execute: trying model=$api_model"

        local response http_code
        response=$(curl -s -w "\n__HTTP_CODE__:%{http_code}" \
            -X POST "https://api.githubcopilot.com/chat/completions" \
            -H "Authorization: Bearer $copilot_token" \
            -H "Content-Type: application/json" \
            -H "Accept: application/json" \
            -H "Editor-Version: gh-copilot/1.0.0" \
            -H "User-Agent: GithubCopilot/1.0.0" \
            --max-time 90 \
            -d "$payload" 2>/dev/null)

        http_code=$(echo "$response" | grep -o '__HTTP_CODE__:[0-9]*' | cut -d: -f2)
        response=$(echo "$response" | sed 's/__HTTP_CODE__:[0-9]*$//')

        if [[ "$http_code" == "200" ]]; then
            # Extract content from OpenAI-compatible response
            local content=""
            if json_extract "$response" "content"; then
                content="$REPLY"
            fi

            if [[ -n "$content" ]]; then
                local result
                result=$(echo "$content" | sed 's/\\n/\n/g; s/\\t/\t/g; s/\\"/"/g')
                if [[ -n "$output_file" ]]; then
                    echo "$result" > "$output_file"
                else
                    echo "$result"
                fi
                log DEBUG "copilot_execute: success with model=$api_model"
                return 0
            fi
        elif [[ "$http_code" == "400" || "$http_code" == "403" || "$http_code" == "404" ]]; then
            # Model may not be available for this org — try next preference
            local err_msg
            if command -v jq &>/dev/null; then
                err_msg=$(echo "$response" | jq -r '.message // .error.message // ""' 2>/dev/null)
            fi
            log WARN "copilot_execute: model '$api_model' unavailable (HTTP $http_code${err_msg:+: $err_msg}) — trying next preference"
            continue
        elif [[ "$http_code" == "401" ]]; then
            # Token expired — invalidate cache and fail
            rm -f "${TMPDIR:-/tmp}/.octo-copilot-token-${USER:-${USERNAME:-user}}" 2>/dev/null || true
            log ERROR "copilot_execute: Token expired (HTTP 401) — re-run to refresh"
            return 1
        elif [[ "$http_code" == "429" ]]; then
            # Rate limit may be model-specific — try next model before giving up
            log WARN "copilot_execute: Rate limited (HTTP 429) on $api_model — trying next model"
            continue
        else
            log WARN "copilot_execute: Unexpected HTTP $http_code from Copilot API, trying next model"
            continue
        fi
    done

    log ERROR "copilot_execute: All model preferences exhausted — no models available for org policy"
    log WARN "copilot_execute: Org may restrict available models. Check your GitHub Copilot settings."
    return 1
}
