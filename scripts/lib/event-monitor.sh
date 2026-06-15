#!/usr/bin/env bash
# event-monitor.sh — local HUD over the Octopus JSONL event stream (oco-8gw).
#
# A passive observer (like claude-hud): tails OCTO_EVENT_LOG and renders a live,
# colorized one-line feed of provider/dispatch/circuit lifecycle events. Run it
# in a second terminal alongside a workflow:
#
#   bin/octo-hud                       # reads $OCTO_EVENT_LOG
#   bin/octo-hud /path/to/events.jsonl
#
# Degrades to a no-op when stdout is not a TTY (CI/headless), so piping is safe.
# Source-safe: no main execution block. bash 3.2 compatible (no assoc arrays).

# Extract a value from one JSONL event record. Looks in attributes.<key> first,
# then top-level <key>. Uses jq when available, else a tolerant sed fallback.
octo_hud_field() {
    local line="$1" key="$2"
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$line" \
            | jq -r --arg k "$key" '(.attributes[$k]? // .[$k]? // "") | tostring' 2>/dev/null
        return 0
    fi
    # Fallback: match "key":"value" or "key":value anywhere in the line.
    printf '%s' "$line" | sed -n "s/.*\"$key\":\"\\([^\"]*\\)\".*/\\1/p" | head -1
}

# Format one event record into a colorized HUD line. Returns non-zero (and emits
# nothing) for blank/malformed input so the caller can skip it safely.
octo_hud_format_line() {
    local line="$1"
    [[ -n "${line// /}" ]] || return 1

    local event ts provider outcome status command exit_code
    event="$(octo_hud_field "$line" event)"
    [[ -n "$event" ]] || return 1   # not a recognizable event record

    ts="$(octo_hud_field "$line" timestamp)"; ts="${ts##*T}"; ts="${ts%Z}"
    provider="$(octo_hud_field "$line" provider)"
    outcome="$(octo_hud_field "$line" outcome)"
    status="$(octo_hud_field "$line" status)"
    command="$(octo_hud_field "$line" command)"
    exit_code="$(octo_hud_field "$line" exit_code)"

    # Color by event family (guard colors so non-TTY/no-tput still works).
    local c_reset c_dim c_evt
    c_reset=$'\033[0m'; c_dim=$'\033[2m'
    case "$event" in
        *timeout|circuit-breaker.open|provider.status) c_evt=$'\033[31m' ;;   # red
        dispatch.end)
            if [[ "$outcome" == "error" ]]; then c_evt=$'\033[31m'; else c_evt=$'\033[32m'; fi ;;
        circuit-breaker.closed|circuit-breaker.half-open|provider.selected) c_evt=$'\033[36m' ;; # cyan
        *) c_evt=$'\033[0m' ;;
    esac

    local detail=""
    [[ -n "$provider" ]]  && detail="${detail} provider=${provider}"
    [[ -n "$status" ]]    && detail="${detail} status=${status}"
    [[ -n "$command" ]]   && detail="${detail} cmd=${command}"
    [[ -n "$outcome" ]]   && detail="${detail} outcome=${outcome}"
    [[ -n "$exit_code" ]] && detail="${detail} exit=${exit_code}"

    printf '%s%s%s  %s%-22s%s%s\n' \
        "$c_dim" "${ts:-now}" "$c_reset" "$c_evt" "$event" "$c_reset" "$detail"
}

# Tail the event log and render the live feed. No-op when stdout is not a TTY.
octo_hud_run() {
    local log="${1:-${OCTO_EVENT_LOG:-}}"
    if [[ ! -t 1 ]]; then
        return 0   # headless/piped — render nothing
    fi
    if [[ -z "$log" || "$log" == "off" ]]; then
        echo "octo-hud: no event log (set OCTO_EVENT_LOG or pass a path)" >&2
        return 1
    fi
    # Wait briefly for the log to appear (a run may not have emitted yet).
    local _w=0
    while [[ ! -f "$log" && $_w -lt 30 ]]; do sleep 0.5; _w=$((_w + 1)); done
    [[ -f "$log" ]] || { echo "octo-hud: event log not found: $log" >&2; return 1; }

    printf '\033[2J\033[H'   # clear screen
    printf '🐙 Octopus HUD — %s  (Ctrl-C to exit)\n' "$log"
    printf '%s\n' "------------------------------------------------------------"
    # -n +1: include existing lines; -F: keep following across rotation/trim.
    tail -n +1 -F "$log" 2>/dev/null | while IFS= read -r _line; do
        octo_hud_format_line "$_line" || true
    done
}
