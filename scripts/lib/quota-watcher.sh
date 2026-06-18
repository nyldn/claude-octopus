#!/usr/bin/env bash
# Shared quota fast-fail watcher for provider CLIs that retry for a long time
# after quota exhaustion instead of exiting promptly.

# Terminal-only quota/auth errors — the provider CLI cannot recover from these on its own.
# Excludes RetryableQuotaError and "Attempt N failed" retry log lines, which the Gemini CLI
# emits during its own backoff/retry cycle. Matching those caused premature SIGTERM before the
# CLI's retry landed, silently dropping reviewer roles (exit 143, empty output). (issue #516)
OCTOPUS_QUOTA_PATTERN='QUOTA_EXHAUSTED|TerminalQuotaError|exhausted your capacity|insufficient_quota|HTTP 401'

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

    grep -qE "$OCTOPUS_QUOTA_PATTERN" "$temp_err" 2>/dev/null || \
        grep -qE "$OCTOPUS_QUOTA_PATTERN" "$temp_out" 2>/dev/null
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
