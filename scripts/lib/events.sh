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
    local output_var="${1:-}"
    local path=""
    case "${OCTO_EVENT_LOG:-}" in
        "") return 1 ;;
        auto) path="${WORKSPACE_DIR:-$PWD}/.octo/events.jsonl" ;;
        *) path="$OCTO_EVENT_LOG" ;;
    esac
    if [[ -n "$output_var" ]]; then
        printf -v "$output_var" '%s' "$path"
    else
        printf '%s\n' "$path"
    fi
}

octo_event_enabled() {
    local path=""
    octo_event_log_path path
}

_octo_json_string() {
    local value="$1"
    local output_var="${2:-}"

    # Keep event serialization shell-native. Spawning an encoder once per field
    # is expensive on Windows, and probing WindowsApps/python3 can open Store.
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
    if [[ -n "$output_var" ]]; then
        printf -v "$output_var" '"%s"' "$out"
    else
        printf '"%s"\n' "$out"
    fi
}

# Portable best-effort exclusive lock. flock is Linux-only; mkdir is atomic on
# every POSIX filesystem. Bounded spin (~1s) so a dead lock holder degrades to a
# lockless write rather than hanging the caller. Returns 0 if acquired, 1 if not.
_octo_event_epoch() {
    local output_var="$1"
    local epoch=""
    if ! TZ=UTC printf -v epoch '%(%s)T' -1 2>/dev/null; then
        epoch=$(date +%s 2>/dev/null || true)
    fi
    printf -v "$output_var" '%s' "$epoch"
}

_octo_event_reclaim_stale_lock() {
    local lockdir="$1"
    local stale_seconds="${OCTO_EVENT_LOCK_STALE_SECONDS:-30}"
    [[ "$stale_seconds" =~ ^[1-9][0-9]*$ ]] || stale_seconds=30

    local modified="" now=""
    read -r modified 2>/dev/null < "$lockdir/created" || true
    if ! [[ "$modified" =~ ^[0-9]+$ ]]; then
        modified=$(stat -c %Y "$lockdir" 2>/dev/null || stat -f %m "$lockdir" 2>/dev/null || true)
    fi
    [[ "$modified" =~ ^[0-9]+$ ]] || return 1
    _octo_event_epoch now
    [[ "$now" =~ ^[0-9]+$ ]] || return 1
    (( now - modified >= stale_seconds )) || return 1

    # Rename first so a concurrent unlock or reclaimer cannot make us remove a
    # newly acquired lock at the original path.
    local stale_dir="${lockdir}.stale.${BASHPID:-$$}.${RANDOM:-0}"
    mv "$lockdir" "$stale_dir" 2>/dev/null || return 1
    rm -rf "$stale_dir" 2>/dev/null || true
    return 0
}

_octo_event_lock() {
    local lockdir="$1.lock"
    local tries=0
    while ! mkdir "$lockdir" 2>/dev/null; do
        tries=$((tries + 1))
        if _octo_event_reclaim_stale_lock "$lockdir"; then
            continue
        fi
        [[ "$tries" -ge 50 ]] && return 1
        sleep 0.02 2>/dev/null || return 1
    done
    local created=""
    _octo_event_epoch created
    printf '%s\n' "$created" > "$lockdir/created" 2>/dev/null || true
    return 0
}

_octo_event_unlock() {
    rm -f "$1.lock/created" 2>/dev/null || true
    rmdir "$1.lock" 2>/dev/null || true
}

_octo_event_trim() {
    local file="$1"
    local max_lines="${OCTO_EVENT_MAX_LINES:-1000}"

    [[ "$max_lines" =~ ^[0-9]+$ ]] || max_lines=1000
    [[ "$max_lines" -gt 0 ]] || return 0
    [[ -f "$file" ]] || return 0

    if ! type mapfile >/dev/null 2>&1; then
        # macOS Bash 3.2 compatibility; modern Bash uses the no-fork path below.
        local legacy_count
        legacy_count=$(wc -l < "$file" 2>/dev/null | tr -d ' ')
        [[ "$legacy_count" =~ ^[0-9]+$ ]] || return 0
        [[ "$legacy_count" -le "$max_lines" ]] && return 0
        local legacy_tmp="${file}.tmp.$$"
        tail -n "$max_lines" "$file" > "$legacy_tmp" && mv "$legacy_tmp" "$file" || {
            rm -f "$legacy_tmp"
            return 1
        }
        return 0
    fi

    local -a lines=()
    mapfile -t lines < "$file" 2>/dev/null || return 0
    local count="${#lines[@]}"
    [[ "$count" -le "$max_lines" ]] && return 0

    local tmp="${file}.tmp.$$"
    local first=$((count - max_lines)) i
    : > "$tmp" || return 1
    for ((i = first; i < count; i++)); do
        printf '%s\n' "${lines[$i]}" >> "$tmp" || return 1
    done
    mv "$tmp" "$file" || {
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

    local log_file=""
    octo_event_log_path log_file || return 0

    [[ "$event" =~ ^[A-Za-z0-9_.:-]+$ ]] || return 2

    local attrs="" sep=""
    local pair key value key_json value_json
    for pair in "$@"; do
        key="${pair%%=*}"
        value="${pair#*=}"
        [[ "$pair" == *=* ]] || return 2
        [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_.:-]*$ ]] || return 2
        _octo_json_string "$key" key_json
        _octo_json_string "$value" value_json
        attrs="${attrs}${sep}${key_json}:${value_json}"
        sep=","
    done

    local timestamp=""
    if ! TZ=UTC printf -v timestamp '%(%Y-%m-%dT%H:%M:%SZ)T' -1 2>/dev/null; then
        timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +%s)
    fi

    local dir
    if [[ "$log_file" == */* ]]; then
        dir="${log_file%/*}"
        [[ -n "$dir" ]] || dir="/"
    else
        dir="."
    fi
    mkdir -p "$dir" 2>/dev/null || return 0

    local record timestamp_json event_json source_json session_json
    _octo_json_string "$timestamp" timestamp_json
    _octo_json_string "$event" event_json
    _octo_json_string "${OCTO_EVENT_SOURCE:-octopus}" source_json
    _octo_json_string "${OCTOPUS_SESSION_ID:-}" session_json
    printf -v record '{"timestamp":%s,"event":%s,"source":%s,"pid":%s,"session_id":%s,"attributes":{%s}}\n' \
        "$timestamp_json" \
        "$event_json" \
        "$source_json" \
        "$$" \
        "$session_json" \
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
