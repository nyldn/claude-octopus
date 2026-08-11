#!/usr/bin/env bash
# Shared quota fast-fail watcher for provider CLIs that retry for a long time
# after quota exhaustion instead of exiting promptly.

# Terminal-only quota/auth errors — the provider CLI cannot recover from these on its own.
# Excludes RetryableQuotaError and "Attempt N failed" retry log lines, which the Gemini CLI
# emits during its own backoff/retry cycle. Matching those caused premature SIGTERM before the
# CLI's retry landed, silently dropping reviewer roles (exit 143, empty output). (issue #516)
# Overridable via env var so operators can narrow the pattern without patching. (issue #536)
# Added signatures (oco-004 follow-up), both observed live and neither previously
# matched, so the seats kept reporting `available` and kept being dispatched into
# an immediate failure:
#   "Individual quota reached"  — agy/Antigravity, account-wide (not per-model);
#                                 carries a "Resets in NNNhNNm" window.
#   "IneligibleTierError"       — gemini-cli after Google sunset Gemini Code
#                                 Assist free-tier OAuth. Permanent for that
#                                 auth mode, not a transient quota window.
OCTOPUS_QUOTA_PATTERN=${OCTOPUS_QUOTA_PATTERN:-'QUOTA_EXHAUSTED|TerminalQuotaError|exhausted your capacity|insufficient_quota|HTTP 401|Individual quota reached|IneligibleTierError'}

# Session-scoped "this provider is quota/auth-dead" cache (oco-cbb). When a
# terminal quota/auth error is seen at dispatch, the provider is marked here so
# preflight (check-providers.sh) and is_agent_available skip it for the rest of
# the run instead of re-dispatching into the same failure + timeout.
octo_quota_dead_file() {
    printf '%s\n' "${WORKSPACE_DIR:-$HOME/.claude-octopus}/state/.provider-quota-dead"
}

# Per-provider expiry metadata, kept in a sidecar so the main marker file stays a
# plain list of provider names (its on-disk format is depended on by callers and
# tests that grep it directly).
# Format: one "provider<TAB>marked_at_epoch<TAB>ttl_seconds" line per provider.
# ttl_seconds of 0 means "never expires".
octo_quota_dead_meta_file() {
    printf '%s\n' "$(octo_quota_dead_file).meta"
}

# octo_quota_mark_dead <provider> [ttl_seconds]
# ttl_seconds: omit for the OCTOPUS_QUOTA_DEAD_TTL default, 0 for permanent, or a
# provider-supplied window (e.g. agy's "Resets in 156h13m").
octo_quota_mark_dead() {
    local provider="$1" ttl="${2:-}"
    [[ -n "$provider" ]] || return 0
    local f dir meta now tmp
    f="$(octo_quota_dead_file)"; dir="$(dirname "$f")"
    mkdir -p "$dir" 2>/dev/null || return 0
    grep -qxF "$provider" "$f" 2>/dev/null || printf '%s\n' "$provider" >> "$f"

    [[ "$ttl" =~ ^[0-9]+$ ]] || return 0
    meta="$(octo_quota_dead_meta_file)"
    now="$(date +%s 2>/dev/null)" || return 0
    [[ "$now" =~ ^[0-9]+$ ]] || return 0
    tmp="$(mktemp "${meta}.XXXXXX")" 2>/dev/null || return 0
    if [[ -f "$meta" ]]; then
        grep -v "^${provider}	" "$meta" > "$tmp" 2>/dev/null || true
    fi
    printf '%s\t%s\t%s\n' "$provider" "$now" "$ttl" >> "$tmp"
    mv "$tmp" "$meta" 2>/dev/null || rm -f "$tmp" 2>/dev/null
    return 0
}

# octo_quota_clear_dead <provider>
# A successful health probe is stronger evidence than a cached failure. Remove
# both the compatibility marker and any per-provider expiry metadata so a
# recovered provider becomes selectable immediately after its smoke test.
octo_quota_clear_dead() {
    local provider="$1"
    [[ -n "$provider" ]] || return 0

    local f meta tmp
    f="$(octo_quota_dead_file)"
    if [[ -f "$f" ]]; then
        tmp="$(mktemp "${f}.XXXXXX")" 2>/dev/null || return 0
        grep -vxF "$provider" "$f" > "$tmp" 2>/dev/null || true
        mv "$tmp" "$f" 2>/dev/null || rm -f "$tmp" 2>/dev/null
    fi

    meta="$(octo_quota_dead_meta_file)"
    if [[ -f "$meta" ]]; then
        tmp="$(mktemp "${meta}.XXXXXX")" 2>/dev/null || return 0
        grep -v "^${provider}	" "$meta" > "$tmp" 2>/dev/null || true
        mv "$tmp" "$meta" 2>/dev/null || rm -f "$tmp" 2>/dev/null
    fi
    return 0
}

# _octo_quota_meta_expired <provider> — 0 when a recorded per-provider window has
# elapsed, 1 when it is still in force, 2 when no metadata exists (caller falls
# back to the file-mtime default).
_octo_quota_meta_expired() {
    local provider="$1" meta line marked ttl now
    meta="$(octo_quota_dead_meta_file)"
    [[ -f "$meta" ]] || return 2
    line="$(grep "^${provider}	" "$meta" 2>/dev/null | tail -1)" || return 2
    [[ -n "$line" ]] || return 2
    marked="$(printf '%s\n' "$line" | cut -f2)"
    ttl="$(printf '%s\n' "$line" | cut -f3)"
    [[ "$marked" =~ ^[0-9]+$ && "$ttl" =~ ^[0-9]+$ ]] || return 2
    # ttl 0 = permanent (e.g. gemini's IneligibleTierError, which is not a quota
    # window at all but the sunset of an auth mode).
    (( ttl == 0 )) && return 1
    now="$(date +%s 2>/dev/null)"
    [[ "$now" =~ ^[0-9]+$ ]] || return 1
    (( now - marked > ttl ))
}

# How long a quota-dead mark stays in force, in seconds. The marker was
# described as "session-scoped" but nothing ever cleared it, so a mark was in
# practice permanent — a provider that hit one transient quota window stayed
# suppressed until someone deleted the file by hand. That was survivable while
# only four providers consulted the marker; now that check-providers.sh applies
# it to every provider, a stale mark would silently retire a working seat.
# Expire on the file's mtime (coarse but portable, and it keeps the on-disk
# format as bare provider names, which existing tests and files depend on).
# Note the mtime is per-file, so marking any provider refreshes the window for
# all of them — acceptable for a "don't re-dispatch into the same failure right
# now" guard, and it always fails toward retrying rather than suppressing.
OCTOPUS_QUOTA_DEAD_TTL=${OCTOPUS_QUOTA_DEAD_TTL:-3600}

# Portable mtime-in-epoch-seconds. Probe the GNU form FIRST and validate that
# the result is actually a number: on Linux `stat -f` is --file-system, so
# `stat -f %m` does not fail there — it succeeds and prints the mount point.
# Probing BSD-style first therefore yields "/" on Linux, which silently defeats
# any numeric comparison built on it. Echoes nothing if neither form works.
_octo_quota_file_mtime() {
    local f="$1" v
    v="$(stat -c %Y "$f" 2>/dev/null)" || v=""
    [[ "$v" =~ ^[0-9]+$ ]] || v="$(stat -f %m "$f" 2>/dev/null)" || v=""
    [[ "$v" =~ ^[0-9]+$ ]] && printf '%s\n' "$v"
}

octo_quota_is_dead() {
    local provider="$1"
    [[ -n "$provider" ]] || return 1
    local f
    f="$(octo_quota_dead_file)"
    [[ -f "$f" ]] || return 1

    # Per-provider window first. The single global TTL below is wrong for both
    # signatures that motivated this cache: gemini's IneligibleTierError is
    # permanent for that auth mode, and agy's window is ~156h, so a 1h default
    # expired it roughly 156 times before the quota actually reset — putting a
    # known-dead seat straight back into dispatch.
    _octo_quota_meta_expired "$provider"
    case $? in
        0) return 1 ;;   # recorded window elapsed
        1) grep -qxF "$provider" "$f" 2>/dev/null; return $? ;;   # still in force
    esac

    # No metadata (marked by an older version, or a signature with no known
    # window): fall back to the coarse file-mtime default.
    if [[ "$OCTOPUS_QUOTA_DEAD_TTL" =~ ^[0-9]+$ ]] && (( OCTOPUS_QUOTA_DEAD_TTL > 0 )); then
        local mtime now
        mtime="$(_octo_quota_file_mtime "$f")"
        now="$(date +%s 2>/dev/null)"
        if [[ "$mtime" =~ ^[0-9]+$ && "$now" =~ ^[0-9]+$ ]] \
           && (( now - mtime > OCTOPUS_QUOTA_DEAD_TTL )); then
            return 1
        fi
    fi

    grep -qxF "$provider" "$f" 2>/dev/null
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

    : > "$temp_err"
    : > "$temp_out"

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
        orcarouter)
            [[ -n "${ORCAROUTER_API_KEY:-}" ]] || return 0
            # GET /v1/models returns 200 with model list or 401 on bad key.
            http_code=$(curl -s -o /dev/null -w "%{http_code}" \
                --max-time 10 \
                -X GET "https://api.orcarouter.ai/v1/models" \
                -H "Authorization: Bearer ${ORCAROUTER_API_KEY}" \
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
