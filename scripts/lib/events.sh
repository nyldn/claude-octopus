#!/usr/bin/env bash
# Source-safe: no shell options set at top. Setting `set -e`/`pipefail` here would
# leak errexit into every sourcer (this lib is sourced, not executed). Helpers
# guard their own return codes instead.

# Claude Octopus event stream helpers.
#
# The event stream is opt-in. Set OCTO_EVENT_LOG to a JSONL file path, or to
# "auto" to write ${WORKSPACE_DIR:-$PWD}/.octo/events.jsonl.
# Normal command output is unchanged when OCTO_EVENT_LOG is unset.

octo_event_log_path() {
    case "${OCTO_EVENT_LOG:-}" in
        "") return 1 ;;
        auto) printf '%s\n' "${WORKSPACE_DIR:-$PWD}/.octo/events.jsonl" ;;
        *) printf '%s\n' "$OCTO_EVENT_LOG" ;;
    esac
}

octo_event_enabled() {
    octo_event_log_path >/dev/null 2>&1
}

_octo_json_string() {
    local value="$1"

    if command -v python3 >/dev/null 2>&1; then
        python3 - "$value" <<'PY' 2>/dev/null && return 0
import json
import sys

print(json.dumps(sys.argv[1]))
PY
    fi

    if command -v jq >/dev/null 2>&1; then
        jq -Rn --arg value "$value" '$value' 2>/dev/null && return 0
    fi

    local out="" ch ord esc
    local i
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    for ((i = 0; i < ${#value}; i++)); do
        ch="${value:i:1}"
        case "$ch" in
            $'\b') out="${out}\\b" ;;
            $'\f') out="${out}\\f" ;;
            $'\n') out="${out}\\n" ;;
            $'\r') out="${out}\\r" ;;
            $'\t') out="${out}\\t" ;;
            *)
                LC_ALL=C printf -v ord '%d' "'$ch"
                if (( ord < 32 )); then
                    printf -v esc '\\u%04x' "$ord"
                    out="${out}${esc}"
                else
                    out="${out}${ch}"
                fi
                ;;
        esac
    done
    printf '"%s"\n' "$out"
}

# Portable best-effort exclusive lock. flock is Linux-only; mkdir is atomic on
# every POSIX filesystem. Bounded spin (~1s) so a dead lock holder degrades to a
# lockless write rather than hanging the caller. Returns 0 if acquired, 1 if not.
_octo_event_lock() {
    local lockdir="$1.lock"
    local tries=0
    while ! mkdir "$lockdir" 2>/dev/null; do
        tries=$((tries + 1))
        [[ "$tries" -ge 50 ]] && return 1
        sleep 0.02 2>/dev/null || return 1
    done
    return 0
}

_octo_event_unlock() {
    rmdir "$1.lock" 2>/dev/null || true
}

_octo_event_trim() {
    local file="$1"
    local max_lines="${OCTO_EVENT_MAX_LINES:-1000}"

    [[ "$max_lines" =~ ^[0-9]+$ ]] || max_lines=1000
    [[ "$max_lines" -gt 0 ]] || return 0
    [[ -f "$file" ]] || return 0

    local count
    count=$(wc -l < "$file" 2>/dev/null | tr -d ' ')
    [[ "$count" =~ ^[0-9]+$ ]] || return 0
    [[ "$count" -le "$max_lines" ]] && return 0

    local tmp="${file}.tmp.$$"
    tail -n "$max_lines" "$file" > "$tmp" && mv "$tmp" "$file" || {
        rm -f "$tmp"
        return 1
    }
}

# octo_event_emit EVENT [key=value ...]
# Appends one JSON object to OCTO_EVENT_LOG. Attribute values are strings by
# design; callers that need richer data can link records by run_id/session_id.
octo_event_emit() {
    local event="${1:-}"
    shift || true

    local log_file
    log_file=$(octo_event_log_path 2>/dev/null) || return 0

    [[ "$event" =~ ^[A-Za-z0-9_.:-]+$ ]] || return 2

    local attrs="" sep=""
    local pair key value
    for pair in "$@"; do
        key="${pair%%=*}"
        value="${pair#*=}"
        [[ "$pair" == *=* ]] || return 2
        [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_.:-]*$ ]] || return 2
        attrs="${attrs}${sep}$(_octo_json_string "$key"):$(_octo_json_string "$value")"
        sep=","
    done

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +%s)

    local dir
    dir="$(dirname "$log_file")"
    mkdir -p "$dir" 2>/dev/null || return 0

    local record
    printf -v record '{"timestamp":%s,"event":%s,"source":%s,"pid":%s,"session_id":%s,"attributes":{%s}}\n' \
        "$(_octo_json_string "$timestamp")" \
        "$(_octo_json_string "$event")" \
        "$(_octo_json_string "${OCTO_EVENT_SOURCE:-octopus}")" \
        "$$" \
        "$(_octo_json_string "${OCTOPUS_SESSION_ID:-}")" \
        "$attrs"

    # Serialize append+trim under one lock so a concurrent emit can never have
    # its just-appended line clobbered by another emit's trim (mv). If the lock
    # can't be acquired (~1s spin), fall back to a lockless write — same
    # best-effort behavior as before, and it never blocks the caller.
    if _octo_event_lock "$log_file"; then
        { printf '%s' "$record" 2>/dev/null >> "$log_file" && _octo_event_trim "$log_file"; } || {
            _octo_event_unlock "$log_file"
            return 0
        }
        _octo_event_unlock "$log_file"
    else
        printf '%s' "$record" 2>/dev/null >> "$log_file" || return 0
        _octo_event_trim "$log_file" || return 0
    fi

    return 0
}
