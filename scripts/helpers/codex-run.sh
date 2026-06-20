#!/usr/bin/env bash
# codex-run.sh — guarded wrapper around `codex exec` for OSS/local models.
#
# WHY THIS EXISTS:
#   The codex CLI has built-in OSS/local-model support: when pinned to a gpt-oss*
#   (or ollama-tagged) model it serves the model through ollama and SILENTLY
#   auto-pulls it if absent. There is NO codex flag to disable that download —
#   verified against `codex exec --help`: only `--oss` and `--local-provider`
#   exist, neither suppresses the pull. So when a provider-failure cascade pins
#   codex to an unavailable OSS model, codex fires an unbounded multi-GB
#   `ollama pull` with no human in the loop. Observed 2026-06-20: a ~42 GB pull
#   kicked off by a codex researcher agent (result file codex-1781942943.md).
#
#   Octopus's own Ollama provider is already guarded by ollama-run.sh, but that
#   guard never sees codex's pull because codex talks to ollama directly. This
#   shim closes that SECOND vector: dispatch routes an OSS-model codex through
#   here, and we ensure the model is already present (or refuse) BEFORE codex
#   runs — so codex's own auto-pull never fires unbounded. Non-OSS codex models
#   (gpt-5.x, o3, gpt-4.1, …) pass straight through untouched.
#
# Usage:   codex-run.sh <codex-bin> exec --model <model> ... -
#          i.e. the full codex argv exactly as dispatch built it; prompt on stdin.
#
# Env: shares the ollama pull-guard contract (see ollama-pull-guard.lib.sh) —
#   OCTOPUS_OLLAMA_ALLOW_PULL=true|1   allow pulling absent models (default: off)
#   OCTOPUS_OLLAMA_MAX_PULL_GB=<n>     size cap for an allowed pull (default: 20)
#   OCTOPUS_OLLAMA_BIN=<path>          override the ollama binary (testing)
#   OCTOPUS_CODEX_OSS_PATTERNS=<ere>   extra ERE of model names to treat as OSS
#
# Exit codes (from the shared guard): 64 usage, 69 ollama missing,
#   70 refused (absent + no opt-in), 75 pull exceeded cap.

set -uo pipefail

_codex_run_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# Fail CLOSED: if the shared guard cannot be loaded, refuse rather than launch
# codex unguarded (which could auto-pull an absent OSS model).
if ! source "${_codex_run_dir}/ollama-pull-guard.lib.sh" 2>/dev/null; then
    echo "codex-run: cannot load ollama-pull-guard.lib.sh — refusing to run codex unguarded." >&2
    exit 70
fi

# ── Does <model> look like an OSS/local model that codex serves via ollama?
#    codex's built-in OSS family is gpt-oss*; ollama-served models also carry a
#    size tag like ':20b' / ':120b' / ':7b'. Cloud codex models (gpt-5.x, o3,
#    gpt-4.1, gpt-5.2-codex) never use that tag form, so this stays conservative.
#    NOTE: keep in sync with _codex_dispatch_is_oss_model() in lib/dispatch.sh. ──
_codex_model_is_oss() {
    local m="$1"
    [[ -z "$m" ]] && return 1
    shopt -s nocasematch
    local rc=1
    if [[ "$m" == gpt-oss* ]] || [[ "$m" =~ :[0-9]+(\.[0-9]+)?b$ ]]; then
        rc=0
    elif [[ -n "${OCTOPUS_CODEX_OSS_PATTERNS:-}" && "$m" =~ ${OCTOPUS_CODEX_OSS_PATTERNS} ]]; then
        rc=0
    fi
    shopt -u nocasematch
    return $rc
}

# ── Pull the value of --model / -m out of the codex argv. ──
_codex_extract_model() {
    local prev="" tok
    for tok in "$@"; do
        case "$prev" in
            --model|-m) printf '%s' "$tok"; return 0 ;;
        esac
        case "$tok" in
            --model=*) printf '%s' "${tok#--model=}"; return 0 ;;
            -m=*)      printf '%s' "${tok#-m=}"; return 0 ;;
        esac
        prev="$tok"
    done
    return 0
}

# ── Is an explicit codex OSS flag present in the argv? (defence in depth) ──
_codex_has_oss_flag() {
    local tok
    for tok in "$@"; do
        [[ "$tok" == "--oss" || "$tok" == "--local-provider" ]] && return 0
    done
    return 1
}

main() {
    if [[ $# -eq 0 ]]; then
        echo "codex-run: no codex command given" >&2
        exit 64
    fi

    local model
    model="$(_codex_extract_model "$@")"

    # Guard only when codex would route to a local/OSS model. A concrete model
    # name is required to size-check the pull; Octopus dispatch always supplies
    # one via --model.
    if [[ -n "$model" ]] && { _codex_model_is_oss "$model" || _codex_has_oss_flag "$@"; }; then
        local rc=0
        ollama_guard_ensure_present "$model" "codex OSS/local model" || rc=$?
        if [[ "$rc" -ne 0 ]]; then
            echo "codex-run: not launching codex — OSS model '$model' is unavailable under the pull guard (rc=$rc)." >&2
            exit "$rc"
        fi
    fi

    # Cloud model, or OSS model already present / pulled within cap → run codex.
    # stdin (the prompt) passes straight through.
    exec "$@"
}

# Run only when executed directly; sourcing (tests) just loads the functions.
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
    main "$@"
fi
