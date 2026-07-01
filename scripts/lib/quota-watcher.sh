#!/usr/bin/env bash
# Shared quota fast-fail watcher for provider CLIs that retry for a long time
# after quota exhaustion instead of exiting promptly.

# Terminal-only quota/auth errors — the provider CLI cannot recover from these on its own.
# Excludes RetryableQuotaError and "Attempt N failed" retry log lines, which the Gemini CLI
# emits during its own backoff/retry cycle. Matching those caused premature SIGTERM before the
# CLI's retry landed, silently dropping reviewer roles (exit 143, empty output). (issue #516)
# Overridable via env var so operators can narrow the pattern without patching. (issue #536)
OCTOPUS_QUOTA_PATTERN=${OCTOPUS_QUOTA_PATTERN:-'QUOTA_EXHAUSTED|TerminalQuotaError|exhausted your capacity|insufficient_quota|HTTP 401'}

# Session-scoped "this provider is quota/auth-dead" cache (oco-cbb). When a
# terminal quota/auth error is seen at dispatch, the provider is marked here so
# preflight (check-providers.sh) and is_agent_available skip it for the rest of
# the run instead of re-dispatching into the same failure + timeout.
octo_quota_dead_file() {
    printf '%s\n' "${WORKSPACE_DIR:-$HOME/.claude-octopus}/state/.provider-quota-dead"
}

octo_quota_mark_dead() {
    local provider="$1"
    [[ -n "$provider" ]] || return 0
    local f dir
    f="$(octo_quota_dead_file)"; dir="$(dirname "$f")"
    mkdir -p "$dir" 2>/dev/null || return 0
    grep -qxF "$provider" "$f" 2>/dev/null || printf '%s\n' "$provider" >> "$f"
}

octo_quota_is_dead() {
    local provider="$1"
    [[ -n "$provider" ]] || return 1
    grep -qxF "$provider" "$(octo_quota_dead_file)" 2>/dev/null
}

quota_watcher_has_match() {
    local temp_err="$1"
    local temp_out="$2"
    local _matches

    # Exclude lines that contain "Retrying after" — those are provider-internal
    # retry progress messages (e.g. Gemini burst-throttle 429s) that contain
    # "exhausted your capacity" but recover on their own. Matching them as
    # terminal errors caused SIGTERM mid-retry, dropping reviewer roles with
    # exit 143 and empty output. (issue #536)
    for f in "$temp_err" "$temp_out"; do
        _matches=$(grep -E "$OCTOPUS_QUOTA_PATTERN" "$f" 2>/dev/null | grep -vE "Retrying after") || true
        [[ -n "$_matches" ]] && return 0
    done
    return 1
}

start_quota_watcher() {
    local target_pid="$1"
    local temp_err="$2"
    local temp_out="$3"
    local kill_callback="$4"
    local warning_message="${5:-Quota exhaustion detected - fast-failing}"
    local provider="${6:-}"   # optional: marked quota-dead for the session on match

    > "$temp_err"
    > "$temp_out"

    (
        _consecutive=0
        while kill -0 "$target_pid" 2>/dev/null; do
            sleep 2
            if quota_watcher_has_match "$temp_err" "$temp_out"; then
                _consecutive=$((_consecutive + 1))
                # Require the pattern to persist across two polls (~4 s) before killing.
                # This lets provider CLIs with their own backoff (e.g. Gemini free-tier
                # burst 429s) complete their retry before we act on the first match.
                if [[ $_consecutive -ge 2 ]]; then
                    log "WARN" "$warning_message"
                    octo_quota_mark_dead "$provider"
                    "$kill_callback" "$target_pid"
                    break
                fi
            else
                _consecutive=0
            fi
        done
    ) >/dev/null &
    echo "$!"
}

stop_quota_watcher() {
    local watcher_pid="${1:-}"
    [[ -n "$watcher_pid" ]] || return 0

    kill "$watcher_pid" 2>/dev/null || true
    wait "$watcher_pid" 2>/dev/null || true
}

# octo_provider_probe <provider>
# Opt-in proactive health check for API-key providers (perplexity, openrouter).
# Only called when OCTOPUS_PREFLIGHT_PROBE=1. Result is session-cached via the
# existing quota-dead marker file, so check-providers.sh octo_quota_is_dead
# reads it without any extra wiring.
#
# Fail-open policy: network errors (curl exit codes other than auth failure
# signals) return 0 and do NOT mark the provider dead. Only definitive 401/402
# or quota signals mark the provider dead. This avoids false positives on
# transient connectivity issues.
octo_provider_probe() {
    local provider="$1"
    [[ -n "$provider" ]] || return 0

    # Skip if already known dead (cached from earlier this session).
    octo_quota_is_dead "$provider" && return 1

    local http_code=""
    local curl_exit=0

    case "$provider" in
        perplexity)
            [[ -n "${PERPLEXITY_API_KEY:-}" ]] || return 0
            # Minimal POST: single-token completion to validate the key cheaply.
            http_code=$(curl -s -o /dev/null -w "%{http_code}" \
                --max-time 10 \
                -X POST "https://api.perplexity.ai/chat/completions" \
                -H "Authorization: Bearer ${PERPLEXITY_API_KEY}" \
                -H "Content-Type: application/json" \
                -d '{"model":"sonar","messages":[{"role":"user","content":"hi"}],"max_tokens":1}' \
                2>/dev/null) || curl_exit=$?
            ;;
        openrouter)
            [[ -n "${OPENROUTER_API_KEY:-}" ]] || return 0
            # GET /api/v1/auth/key returns 200 with key metadata or 401 on bad key.
            http_code=$(curl -s -o /dev/null -w "%{http_code}" \
                --max-time 10 \
                -X GET "https://openrouter.ai/api/v1/auth/key" \
                -H "Authorization: Bearer ${OPENROUTER_API_KEY}" \
                2>/dev/null) || curl_exit=$?
            ;;
        *)
            # Unknown provider: no probe defined, fail open.
            return 0
            ;;
    esac

    # Network failure (curl_exit != 0) or no response: fail open.
    if [[ $curl_exit -ne 0 || -z "$http_code" ]]; then
        return 0
    fi

    # Definitive auth/quota failure: mark dead and return 1.
    case "$http_code" in
        401|402)
            octo_quota_mark_dead "$provider"
            return 1
            ;;
        429)
            # Rate limit: not necessarily dead, but a transient quota issue.
            # Mark dead so this session skips the provider (same as reactive path).
            octo_quota_mark_dead "$provider"
            return 1
            ;;
    esac

    # 200/other: alive (or unknown state — fail open).
    return 0
}
