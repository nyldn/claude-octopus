#!/usr/bin/env bash
# council-wait.sh — block efficiently until a backgrounded council round finishes,
# then print the path to its summary.json. Replaces a lead's coarse hand-rolled
# poll loop (e.g. `sleep 15 x 38` passes, discovering completion up to ~10 minutes
# late) with a short-interval poll of the authoritative completion beacon.
#
# The runner writes run-status.json's `state:"finished"` as the LAST step of
# council_write_summary_json, i.e. only after a valid summary.json is in place, so
# `state == "finished"` reliably means the summary is present. This waiter polls
# that flag and returns the instant it flips — the completion tail drops from
# minutes to one poll interval.
#
# Usage:
#   council-wait.sh --pool <dir> [--interval S] [--timeout N] [--since EPOCH] \
#                   [--supersede-key KEY]
#   council-wait.sh --run-dir <dir> [--interval S] [--timeout N]
#
#   --pool         councils pool dir; the newest run in it is awaited (a council
#                  invocation creates a timestamped run dir the caller can't name
#                  ahead of time, so the pool is the stable handle).
#   --run-dir      await a specific run dir instead of resolving one from a pool.
#   --supersede-key with --pool, prefer the run the pool's latest-<slug> pointer
#                  names (the current gate's round), ignoring older interleaved gates.
#   --since EPOCH  with --pool, only consider run dirs created at/after EPOCH
#                  (seconds), so a stale prior round is never selected.
#   --interval S   poll interval seconds (default 2; floored at 1).
#   --timeout N    max seconds to wait (default 570, kept < the 600s synchronous
#                  tool-call cap; call again to keep waiting a longer council).
#
# Output: on completion, prints the summary.json path to stdout and exits 0.
#         On timeout, prints the awaited run dir (or "pending") to stderr, exits 2.
#         Usage/argument errors exit 64.
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
        --help|-h)       sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)               die_usage "unknown argument: $1" ;;
    esac
done

[[ "$INTERVAL" =~ ^[0-9]+$ ]] || die_usage "--interval must be an integer"
[[ "$TIMEOUT"  =~ ^[0-9]+$ ]] || die_usage "--timeout must be an integer"
[[ -n "$SINCE" && ! "$SINCE" =~ ^[0-9]+$ ]] && die_usage "--since must be an epoch integer"
(( INTERVAL < 1 )) && INTERVAL=1
command -v jq >/dev/null 2>&1 || die_usage "jq is required"

if [[ -n "$RUN_DIR" && -n "$POOL" ]]; then die_usage "pass only one of --run-dir / --pool"; fi
if [[ -z "$RUN_DIR" && -z "$POOL" ]]; then die_usage "one of --run-dir / --pool is required"; fi

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
            rid="$(tr -d '[:space:]' < "$ptr" 2>/dev/null || true)"
            [[ -n "$rid" && -d "$POOL/$rid" ]] && { printf '%s' "$POOL/$rid"; return 0; }
        fi
    fi
    # Otherwise the newest timestamped run dir (optionally created at/after --since).
    local d best=""
    for d in "$POOL"/2*/; do
        [[ -d "$d" ]] || continue
        d="${d%/}"
        if [[ -n "$SINCE" ]]; then
            local mt; mt="$(_dir_mtime "$d")"
            [[ -n "$mt" ]] && (( mt < SINCE )) && continue
        fi
        if [[ -z "$best" || "$d" > "$best" ]]; then best="$d"; fi
    done
    [[ -n "$best" ]] && printf '%s' "$best"
}

_dir_mtime() {
    # Portable mtime in epoch seconds (GNU vs BSD stat).
    stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || true
}

_is_finished() {
    local rd="$1" st="$1/run-status.json"
    [[ -f "$st" ]] || return 1
    [[ "$(jq -r '.state // empty' "$st" 2>/dev/null || true)" == "finished" ]] || return 1
    # Defensive: the beacon flips to finished only after a valid summary.json, but
    # re-check so a torn/partial file is never reported as complete.
    local summary="$rd/summary.json"
    [[ -s "$summary" ]] && jq -e . "$summary" >/dev/null 2>&1
}

now() { date +%s 2>/dev/null || echo 0; }

deadline=$(( $(now) + TIMEOUT ))
run_dir=""
while :; do
    [[ -n "$run_dir" ]] || run_dir="$(_resolve_run_dir || true)"
    if [[ -n "$run_dir" ]] && _is_finished "$run_dir"; then
        printf '%s/summary.json\n' "$run_dir"
        exit 0
    fi
    (( $(now) >= deadline )) && break
    sleep "$INTERVAL"
done

printf 'council-wait: timed out after %ss (run: %s)\n' "$TIMEOUT" "${run_dir:-pending}" >&2
exit 2
