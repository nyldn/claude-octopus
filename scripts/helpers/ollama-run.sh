#!/usr/bin/env bash
# ollama-run.sh — guarded wrapper around `ollama run <model>`.
#
# WHY THIS EXISTS:
#   `ollama run <model>` SILENTLY auto-pulls a missing model. When a cloud
#   provider dies mid-workflow (observed 2026-06-20: Gemini auth-dead + Codex
#   pinned to an unavailable model) the fleet can fall back to the local Ollama
#   provider. If the configured OCTOPUS_OLLAMA_MODEL is not already present, that
#   fallback triggers an unbounded multi-GB download with NO human in the loop —
#   in the observed incident a ~42 GB pull kicked off by a provider-failure
#   cascade. An unbounded download fired by an automated retry is a real disk and
#   bandwidth risk.
#
#   This shim makes the local fallback FAIL CLOSED. It never auto-pulls a model
#   that is not already present unless the user has explicitly opted in via
#   OCTOPUS_OLLAMA_ALLOW_PULL=true, and even then it caps the download size
#   (OCTOPUS_OLLAMA_MAX_PULL_GB, default 20) so a stray giant model cannot fill
#   the disk. Because dispatch routes ALL Ollama execution through this one shim,
#   no provider-failure cascade can sidestep the guard.
#
# Usage:   ollama-run.sh <model>            (the prompt arrives on stdin)
#
# Env:
#   OCTOPUS_OLLAMA_ALLOW_PULL=true|1   allow pulling absent models (default: off)
#   OCTOPUS_OLLAMA_MAX_PULL_GB=<n>     size cap for an allowed pull (default: 20)
#   OCTOPUS_OLLAMA_BIN=<path>          override the ollama binary (testing)
#
# Exit codes:
#   64  usage error (no model given)
#   69  ollama binary not found
#   70  model absent and auto-pull not opted in (refused — NO download)
#   75  allowed pull exceeded the size cap or otherwise did not complete

set -uo pipefail

OLLAMA_BIN="${OCTOPUS_OLLAMA_BIN:-ollama}"

# ── Is <model> already present locally? Matches an exact name and, for a bare
#    name with no tag, its ":latest" form (how `ollama list` renders defaults). ──
_ollama_model_present() {
    local want="$1" name
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        [[ "$name" == "$want" ]] && return 0
        [[ "$want" != *:* && "$name" == "${want}:latest" ]] && return 0
    done < <("$OLLAMA_BIN" list 2>/dev/null | awk 'NR>1 {print $1}')
    return 1
}

# ── Best-effort: read the largest TOTAL size seen in `ollama pull` progress and
#    return it in GB. Progress lines look like:
#      pulling 4824460d29f2:   0% ▕   ▏ 119 KB/ 42 GB  2.0 MB/s  5h5m...
#    We want the figure AFTER the slash (the total), normalised to GB. ──
_parse_total_gb() {
    local logf="$1"
    grep -oE '/[[:space:]]*[0-9]+(\.[0-9]+)?[[:space:]]*(B|KB|MB|GB|TB)' "$logf" 2>/dev/null \
        | awk '
            {
                n=""; u=""
                if (match($0, /[0-9]+(\.[0-9]+)?/)) { n=substr($0, RSTART, RLENGTH) + 0 }
                if (match($0, /(B|KB|MB|GB|TB)$/))  { u=substr($0, RSTART, RLENGTH) }
                g=n
                if      (u=="B")  g=n/1073741824
                else if (u=="KB") g=n/1048576
                else if (u=="MB") g=n/1024
                else if (u=="GB") g=n
                else if (u=="TB") g=n*1024
                if (g>max) max=g
            }
            END { if (max>0) printf "%.4f", max }
        '
}

# ── Run `ollama pull`, watching its progress for the model TOTAL size. Aborts
#    (kills the pull) the moment the total exceeds max_gb, so an oversized model
#    is stopped after only a few MB instead of downloading the whole thing.
#    Best-effort on size: if no size can be parsed the pull is allowed to proceed
#    (the caller's run_with_timeout still bounds it). Returns 0 only if the model
#    is present afterwards. ──
_ollama_capped_pull() {
    local model="$1" max_gb="$2"
    local logf
    logf="$(mktemp 2>/dev/null || echo "/tmp/octo-ollama-pull-$$.log")"

    "$OLLAMA_BIN" pull "$model" >"$logf" 2>&1 &
    local pid=$!

    local aborted=0
    while kill -0 "$pid" 2>/dev/null; do
        local total_gb
        total_gb="$(_parse_total_gb "$logf")"
        if [[ -n "$total_gb" ]] && awk -v t="$total_gb" -v m="$max_gb" 'BEGIN{exit !(t>m)}'; then
            echo "ollama-run: '$model' total size ${total_gb} GB exceeds cap ${max_gb} GB — aborting pull." >&2
            kill "$pid" 2>/dev/null
            sleep 1
            kill -9 "$pid" 2>/dev/null
            aborted=1
            break
        fi
        sleep 0.5
    done
    wait "$pid" 2>/dev/null
    rm -f "$logf" 2>/dev/null

    [[ "$aborted" == "1" ]] && return 1
    _ollama_model_present "$model"
}

main() {
    local model="${1:-}"
    if [[ -z "$model" ]]; then
        echo "ollama-run: no model specified" >&2
        exit 64
    fi

    if ! command -v "$OLLAMA_BIN" >/dev/null 2>&1; then
        echo "ollama-run: '$OLLAMA_BIN' not found in PATH" >&2
        exit 69
    fi

    # Fast path: model already present → run it directly. stdin (the prompt)
    # passes straight through to `ollama run`.
    if _ollama_model_present "$model"; then
        exec "$OLLAMA_BIN" run "$model"
    fi

    # ── Model is ABSENT. A bare `ollama run` would auto-pull it. Gate that. ──
    local allow_pull="${OCTOPUS_OLLAMA_ALLOW_PULL:-false}"
    if [[ "$allow_pull" != "true" && "$allow_pull" != "1" ]]; then
        cat >&2 <<EOF
ollama-run: model '$model' is not installed locally.
Refusing to auto-pull it — an unbounded multi-GB download triggered by a
provider-failure fallback is a disk/bandwidth risk.

To allow downloads for the Ollama provider, set:
    export OCTOPUS_OLLAMA_ALLOW_PULL=true
    export OCTOPUS_OLLAMA_MAX_PULL_GB=20   # optional size cap (default 20)

Or pre-pull the model yourself:
    $OLLAMA_BIN pull $model
EOF
        exit 70
    fi

    # Pull is opted-in. Enforce a size cap so even an allowed pull cannot run away.
    local max_gb="${OCTOPUS_OLLAMA_MAX_PULL_GB:-20}"
    echo "ollama-run: OCTOPUS_OLLAMA_ALLOW_PULL set — pulling '$model' (cap ${max_gb} GB)..." >&2
    if ! _ollama_capped_pull "$model" "$max_gb"; then
        echo "ollama-run: pull of '$model' did not complete within the ${max_gb} GB cap; aborting." >&2
        exit 75
    fi

    exec "$OLLAMA_BIN" run "$model"
}

main "$@"
