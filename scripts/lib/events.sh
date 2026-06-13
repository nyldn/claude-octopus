#!/usr/bin/env bash
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

    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}
    value=${value//$'\r'/\\r}
    value=${value//$'\t'/\\t}
    printf '"%s"\n' "$value"
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
    tail -n "$max_lines" "$file" > "$tmp" && mv "$tmp" "$file"
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
    mkdir -p "$dir" 2>/dev/null || return 1

    printf '{"timestamp":%s,"event":%s,"source":%s,"pid":%s,"session_id":%s,"attributes":{%s}}\n' \
        "$(_octo_json_string "$timestamp")" \
        "$(_octo_json_string "$event")" \
        "$(_octo_json_string "${OCTO_EVENT_SOURCE:-octopus}")" \
        "$$" \
        "$(_octo_json_string "${OCTOPUS_SESSION_ID:-}")" \
        "$attrs" >> "$log_file" || return 1

    _octo_event_trim "$log_file"
}
