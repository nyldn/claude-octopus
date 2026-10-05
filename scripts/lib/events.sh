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

    # Fast path: pure-bash escaping for values with no control characters, which
    # covers essentially every real event attribute. The python3/jq paths below
    # each cost a process spawn (~20ms), and octo_event_emit calls this helper
    # 5+ times per record — that was ~175ms per emitted event. Only `"` and `\`
    # need escaping here; control chars fall through to the slow paths.
    # [[:cntrl:]] (not a $'\x01'-$'\x1f' range): bracket ranges collate by
    # locale, so under a UTF-8 locale the range silently fails to match TAB/LF
    # and raw control characters would reach the output as invalid JSON.
    case "$value" in
        *[[:cntrl:]]*) : ;;
        *)
            local _fast="${value//\\/\\\\}"
            printf '"%s"\n' "${_fast//\"/\\\"}"
            return 0
            ;;
    esac

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

# Kernel directory creation avoids utilities reporting success after EEXIST.
# Python is required for durable locking; optional event capture retains its
# best-effort unlocked fallback when the runtime is unavailable.
_octo_event_mkdir() {
    command -v python3 >/dev/null 2>&1 || return 1
    python3 - "$1" <<'PY'
import os
import sys

try:
    os.mkdir(sys.argv[1])
except FileExistsError:
    sys.exit(75)
except OSError:
    sys.exit(1)
PY
}

# Portable best-effort exclusive lock. Owner metadata lets a later caller
# reclaim a lock leaked by SIGKILL without stealing a live holder's lock.
_octo_event_reclaim_stale_lock() (
    local lockdir="$1" stale_secs="${OCTO_EVENT_LOCK_STALE_SECS:-30}"
    local owner="" timestamp="" now
    [[ "$stale_secs" =~ ^[0-9]+$ ]] || stale_secs=30
    case "$lockdir" in /*) ;; *) lockdir="$PWD/$lockdir" ;; esac
    [[ -d "$lockdir" && ! -L "$lockdir" ]] || return 1
    # The working directory pins this inode even if its public name is reused.
    CDPATH= cd -P -- "$lockdir" >/dev/null 2>&1 || return 1
    [[ ! -L pid && ! -L ts ]] || return 1

    if [[ -e pid ]]; then
        [[ -f pid && -r pid ]] || return 1
        if [[ -s pid ]]; then
            IFS= read -r owner < pid || return 1
        fi
    fi
    if [[ "$owner" =~ ^[0-9]+$ ]] && kill -0 "$owner" 2>/dev/null; then
        return 75
    fi
    if [[ -e ts ]]; then
        [[ -f ts && -r ts ]] || return 1
        if [[ -s ts ]]; then
            IFS= read -r timestamp < ts || return 1
        fi
    fi
    if [[ ! "$timestamp" =~ ^[0-9]+$ ]]; then
        # A failed BSD-style call can still print filesystem diagnostics on
        # GNU/uutils stat. Keep its output separate from the fallback value.
        timestamp="$(stat -f %m . 2>/dev/null)" ||
            timestamp="$(stat -c %Y . 2>/dev/null)" || return 1
    fi
    now="$(date +%s)" || return 1
    [[ "$timestamp" =~ ^[0-9]+$ && $((now - timestamp)) -ge "$stale_secs" ]] || return 1

    rm -f pid ts 2>/dev/null || return 1
    rmdir "$lockdir" 2>/dev/null
)

_octo_event_lock() {
    local lockdir="$1.lock"
    local tries=0 reclaim_rc claim_rc owner="${BASHPID:-$$}"
    case "$lockdir" in /*) ;; *) lockdir="$PWD/$lockdir" ;; esac
    # The kernel must create this directory. An exclusive PID claim additionally
    # prevents replacing metadata before the caller can enter the critical section.
    while :; do
        if _octo_event_mkdir "$lockdir" 2>/dev/null; then
            if (
                [[ ! -L "$lockdir" ]] || exit 1
                CDPATH= cd -P -- "$lockdir" >/dev/null || exit 1
                [[ ! -L pid && ! -L ts ]] || exit 1
                [[ ! -e pid ]] || exit 75
                [[ ! -e ts || -f ts ]] || exit 1
                set -C
                exec 3> pid || exit 75
                if printf '%s\n' "$owner" >&3 && date +%s > ts && [[ "$lockdir" -ef . ]]; then
                    exit 0
                fi
                # Only names relative to the inode containing our own claim.
                rm -f pid ts || true
                rmdir "$lockdir" || true
                exit 1
            ) 2>/dev/null; then
                break
            else
                claim_rc=$?
                if [[ "$claim_rc" -ne 75 ]]; then
                    return 1
                fi
            fi
        else
            claim_rc=$?
            [[ "$claim_rc" -eq 75 ]] || return 1
        fi
        tries=$((tries + 1))
        if [[ "$tries" -ge 50 ]]; then
            if _octo_event_reclaim_stale_lock "$lockdir"; then
                tries=0
            else
                reclaim_rc=$?
                # Only verified live ownership is ordinary contention.
                # Preserve metadata and cleanup failures for durable callers.
                return "$reclaim_rc"
            fi
        fi
        sleep 0.02 2>/dev/null || return 1
    done
    return 0
}

_octo_event_unlock() {
    local lockdir="$1.lock" caller="${BASHPID:-$$}"
    case "$lockdir" in /*) ;; *) lockdir="$PWD/$lockdir" ;; esac
    (
        local owner=""
        [[ -d "$lockdir" && ! -L "$lockdir" ]] || exit 0
        CDPATH= cd -P -- "$lockdir" >/dev/null 2>&1 || exit 0
        [[ ! -L pid && ! -L ts ]] || exit 0
        [[ -f pid && -r pid ]] || exit 0
        IFS= read -r owner < pid || exit 0
        [[ "$owner" =~ ^[0-9]+$ ]] || exit 0
        # Preserve a replacement held by another live caller. A finished
        # subshell's abandoned claim remains cleanable by its parent.
        if [[ "$owner" != "$caller" ]] && kill -0 "$owner" 2>/dev/null; then
            exit 0
        fi
        rm -f pid ts 2>/dev/null || true
        rmdir "$lockdir" 2>/dev/null || true
    )
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
