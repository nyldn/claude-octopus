#!/usr/bin/env bash
# ollama-pull-guard.lib.sh — shared primitives that stop an unbounded `ollama pull`.
#
# WHY THIS EXISTS:
#   Two distinct code paths in Octopus can trigger a silent, unbounded multi-GB
#   `ollama pull` during a provider-failure cascade:
#     1. Octopus's own Ollama provider (`ollama run <model>` auto-pulls a missing
#        model) — guarded by helpers/ollama-run.sh.
#     2. The codex CLI's built-in OSS/local-model handling (codex serves a
#        gpt-oss* model through ollama and auto-pulls it) — guarded by
#        helpers/codex-run.sh.
#   Both wrappers must make the SAME refuse/allow/cap decision, so the decision
#   lives here once. (Observed 2026-06-20: a ~42 GB pull fired by a codex agent;
#   result file codex-1781942943.md.)
#
# Env contract (shared by every caller):
#   OCTOPUS_OLLAMA_ALLOW_PULL=true|1   allow pulling absent models (default: off)
#   OCTOPUS_OLLAMA_MAX_PULL_GB=<n>     size cap for an allowed pull (default: 20)
#   OCTOPUS_OLLAMA_BIN=<path>          override the ollama binary (testing)
#
# Exit-code conventions returned by ollama_guard_ensure_present():
#   0   model present (already installed, or pulled within the size cap)
#   69  ollama binary not found
#   70  model absent and auto-pull not opted in (refused — NO download)
#   75  allowed pull exceeded the size cap or otherwise did not complete
#
# This file is meant to be SOURCED; it defines functions and one variable and
# runs no work of its own.

OLLAMA_PULL_GUARD_BIN="${OCTOPUS_OLLAMA_BIN:-ollama}"

# ── Is <model> already present locally? Matches an exact name and, for a bare
#    name with no tag, its ":latest" form (how `ollama list` renders defaults). ──
_ollama_model_present() {
    local want="$1" name
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        [[ "$name" == "$want" ]] && return 0
        [[ "$want" != *:* && "$name" == "${want}:latest" ]] && return 0
    done < <("$OLLAMA_PULL_GUARD_BIN" list 2>/dev/null | awk 'NR>1 {print $1}')
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

    "$OLLAMA_PULL_GUARD_BIN" pull "$model" >"$logf" 2>&1 &
    local pid=$!

    local aborted=0
    while kill -0 "$pid" 2>/dev/null; do
        local total_gb
        total_gb="$(_parse_total_gb "$logf")"
        if [[ -n "$total_gb" ]] && awk -v t="$total_gb" -v m="$max_gb" 'BEGIN{exit !(t>m)}'; then
            echo "ollama-pull-guard: '$model' total size ${total_gb} GB exceeds cap ${max_gb} GB — aborting pull." >&2
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

# ── Ensure <model> is present locally, applying the opt-in + size-cap guard.
#    $1 = model name (the same name ollama uses, e.g. gpt-oss:120b)
#    $2 = human context label for messages (e.g. "Octopus Ollama provider")
#    Prints guidance to stderr on refusal/abort and returns a guard exit code
#    (see header). The CALLER decides what runs after a successful (0) return —
#    `ollama run` for the Ollama provider, `codex exec` for the codex shim. ──
ollama_guard_ensure_present() {
    local model="$1"
    local context="${2:-local model}"

    if ! command -v "$OLLAMA_PULL_GUARD_BIN" >/dev/null 2>&1; then
        echo "ollama-pull-guard: '$OLLAMA_PULL_GUARD_BIN' not found in PATH" >&2
        return 69
    fi

    # Fast path: already installed → nothing to pull.
    if _ollama_model_present "$model"; then
        return 0
    fi

    # ── Model is ABSENT. An auto-pull would fire here. Gate it. ──
    local allow_pull="${OCTOPUS_OLLAMA_ALLOW_PULL:-false}"
    if [[ "$allow_pull" != "true" && "$allow_pull" != "1" ]]; then
        cat >&2 <<EOF
ollama-pull-guard: model '$model' (${context}) is not installed locally.
Refusing to auto-pull it — an unbounded multi-GB download triggered by a
provider-failure fallback is a disk/bandwidth risk.

To allow downloads, set:
    export OCTOPUS_OLLAMA_ALLOW_PULL=true
    export OCTOPUS_OLLAMA_MAX_PULL_GB=20   # optional size cap (default 20)

Or pre-pull the model yourself:
    $OLLAMA_PULL_GUARD_BIN pull $model
EOF
        return 70
    fi

    # Pull is opted-in. Enforce a size cap so even an allowed pull cannot run away.
    local max_gb="${OCTOPUS_OLLAMA_MAX_PULL_GB:-20}"
    echo "ollama-pull-guard: OCTOPUS_OLLAMA_ALLOW_PULL set — pulling '$model' (cap ${max_gb} GB)..." >&2
    if ! _ollama_capped_pull "$model" "$max_gb"; then
        echo "ollama-pull-guard: pull of '$model' did not complete within the ${max_gb} GB cap; aborting." >&2
        return 75
    fi
    return 0
}
