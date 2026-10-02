#!/usr/bin/env bash
# Wait for a Council completion beacon and print its summary.json path.
# Completion can include a partial or failed Council result. Read the summary
# to determine that result; exit 0 means the artifacts are ready.
#
# Usage:
#   council-wait.sh --pool DIR [--since EPOCH] [--supersede-key KEY]
#                   [--interval SECONDS] [--timeout SECONDS]
#   council-wait.sh --run-dir DIR [--interval SECONDS] [--timeout SECONDS]
#
# Pool selection uses the creation counter, with run names for legacy ties.
# --since filters immutable UTC creation timestamps in run names.
# --supersede-key waits only for matching current rounds and follows a newer
# matching pointer during the wait. Invalid pointers cannot select another pool.
# The interval defaults to 2 seconds and is floored at 1. The timeout defaults
# to 570 seconds; sleeping never extends it. Time values accept decimal integers.
# A finished beacon and one valid summary object are required before success.
# Exit 0 prints the path, 2 reports timeout, and 64 reports invalid arguments.

set -euo pipefail

POOL="" RUN_DIR="" INTERVAL=2 TIMEOUT=570 SINCE="" KEY=""

die_usage() { printf '%s\n' "$1" >&2; printf 'See: council-wait.sh --help\n' >&2; exit 64; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --pool)          [[ $# -ge 2 ]] || die_usage "--pool requires a value"; POOL="$2"; shift 2 ;;
        --run-dir)       [[ $# -ge 2 ]] || die_usage "--run-dir requires a value"; RUN_DIR="$2"; shift 2 ;;
        --supersede-key) [[ $# -ge 2 ]] || die_usage "--supersede-key requires a value"; KEY="$2"; shift 2 ;;
        --since)         [[ $# -ge 2 ]] || die_usage "--since requires a value"; SINCE="$2"; shift 2 ;;
        --interval)      [[ $# -ge 2 ]] || die_usage "--interval requires a value"; INTERVAL="$2"; shift 2 ;;
        --timeout)       [[ $# -ge 2 ]] || die_usage "--timeout requires a value"; TIMEOUT="$2"; shift 2 ;;
        --help|-h)       awk 'NR == 1 {next} /^#/ {sub(/^# ?/, ""); print; next} {exit}' "$0"; exit 0 ;;
        *)               die_usage "unknown argument: $1" ;;
    esac
done

_integer() {
    local value="$1" option="$2"
    [[ "$value" =~ ^[0-9]+$ ]] || die_usage "$option must be an integer"
    value="$(printf '%s' "$value" | sed 's/^0*//')"
    value="${value:-0}"
    [[ ${#value} -le 10 ]] && (( 10#$value <= 2147483647 )) || die_usage "$option is too large"
    printf '%s' "$value"
}
INTERVAL="$(_integer "$INTERVAL" --interval)" || exit 64
TIMEOUT="$(_integer "$TIMEOUT" --timeout)" || exit 64
if [[ -n "$SINCE" ]]; then SINCE="$(_integer "$SINCE" --since)" || exit 64; fi
(( INTERVAL < 1 )) && INTERVAL=1
command -v jq >/dev/null 2>&1 || die_usage "jq is required"

if [[ -n "$RUN_DIR" && -n "$POOL" ]]; then die_usage "pass only one of --run-dir / --pool"; fi
if [[ -z "$RUN_DIR" && -z "$POOL" ]]; then die_usage "one of --run-dir / --pool is required"; fi
[[ -z "$RUN_DIR" || ( -z "$KEY" && -z "$SINCE" ) ]] || die_usage "--since and --supersede-key require --pool"

_slug() {
    # Mirror council_supersede_key_slug so --supersede-key resolves the same pointer.
    local key="$1" safe hash
    safe="$(printf '%s' "$key" | tr -c 'A-Za-z0-9._-' '_' | cut -c1-64)"
    hash="$(printf '%s' "$key" | cksum | cut -d' ' -f1)"
    printf '%s-%s' "$safe" "$hash"
}

_resolve_run_dir() {
    # Echo the run dir to await, or nothing if none is visible yet.
    if [[ -n "$RUN_DIR" ]]; then
        [[ -d "$RUN_DIR" ]] && printf '%s' "$RUN_DIR"
        return 0
    fi
    [[ -d "$POOL" ]] || return 0
    # Prefer the supersede-key pointer when given (the current gate's latest round).
    if [[ -n "$KEY" ]]; then
        local ptr="$POOL/latest-$(_slug "$KEY")" rid
        if [[ -f "$ptr" ]]; then
            rid="$(cat -- "$ptr" 2>/dev/null || true)"
            if [[ "$rid" =~ ^2[0-9]{7}-[0-9]{6}-[0-9a-fA-F]+(-[0-9]+)?$ ]] && _eligible "$POOL/$rid"; then
                printf '%s' "$POOL/$rid"; return 0
            fi
        fi
    fi
    # Otherwise the newest timestamped run dir (optionally created at/after --since).
    local d best="" order best_order=0
    for d in "$POOL"/2*/; do
        (( SECONDS <= deadline )) || break
        [[ -d "$d" ]] || continue
        d="${d%/}"
        _eligible "$d" || continue
        order="$(jq -r 'if (.created_order | type) == "number" and .created_order > 0 and .created_order <= 9007199254740991 and (.created_order | floor) == .created_order then .created_order else 0 end' "$d/run-status.json" 2>/dev/null)" || continue
        [[ "$order" =~ ^[0-9]{1,16}$ ]] || continue
        if [[ -z "$best" ]] || (( order > best_order )) || { (( order == best_order )) && [[ "$d" > "$best" ]]; }; then
            best="$d"; best_order="$order"
        fi
    done
    [[ -n "$best" ]] && printf '%s' "$best"
}

_eligible() {
    local rd="$1" rid="${1##*/}" stamp epoch
    [[ -d "$rd" && ! -L "$rd" && -s "$rd/run-status.json" ]] || return 1
    [[ "$rid" =~ ^2[0-9]{7}-[0-9]{6}-[0-9a-fA-F]+(-[0-9]+)?$ ]] || return 1
    jq -e -s --arg rid "$rid" --arg key "$KEY" '
        length == 1 and (.[0] | type) == "object" and .[0].run_id == $rid
        and ($key == "" or (.[0].supersede_key == $key and .[0].superseded != true))
    ' "$rd/run-status.json" >/dev/null 2>&1 || return 1
    if [[ -n "$SINCE" ]]; then
        # The UTC run name is immutable. Directory mtime changes as results arrive.
        stamp="${rid:0:15}"
        epoch="$(date -u -j -f '%Y%m%d-%H%M%S' "$stamp" '+%s' 2>/dev/null)" ||
            epoch="$(date -u -d "${stamp:0:4}-${stamp:4:2}-${stamp:6:2} ${stamp:9:2}:${stamp:11:2}:${stamp:13:2}" '+%s' 2>/dev/null)" || return 1
        [[ "$epoch" =~ ^[0-9]+$ ]] && (( epoch >= SINCE )) || return 1
    fi
}

_is_finished() {
    local rd="$1" st="$1/run-status.json"
    [[ -f "$st" ]] || return 1
    jq -e -s --arg rid "${rd##*/}" 'length == 1 and (.[0] | type) == "object" and .[0].state == "finished" and .[0].run_id == $rid' "$st" >/dev/null 2>&1 || return 1
    # Defensive: the beacon flips to finished only after a valid summary.json, but
    # re-check so a torn/partial file is never reported as complete.
    local summary="$rd/summary.json"
    [[ -s "$summary" ]] && jq -e -s --arg rid "${rd##*/}" 'length == 1 and (.[0] | type) == "object" and (.[0].status | type) == "string" and (.[0].status | length) > 0 and (.[0].run_id == null or .[0].run_id == $rid)' "$summary" >/dev/null 2>&1
}

deadline=$(( SECONDS + TIMEOUT ))
run_dir=""
while :; do
    if [[ -z "$run_dir" || -n "$KEY" ]]; then run_dir="$(_resolve_run_dir || true)"; fi
    if [[ -n "$run_dir" ]] && _is_finished "$run_dir"; then
        if [[ -n "$KEY" && "$(_resolve_run_dir || true)" != "$run_dir" ]]; then
            run_dir=""
        else
            printf '%s/summary.json\n' "$run_dir"
            exit 0
        fi
    fi
    remaining=$(( deadline - SECONDS ))
    (( remaining > 0 )) || break
    delay="$INTERVAL"
    (( delay <= remaining )) || delay="$remaining"
    sleep "$delay"
done

printf 'council-wait: timed out after %ss (run: %s)\n' "$TIMEOUT" "${run_dir:-pending}" >&2
exit 2
