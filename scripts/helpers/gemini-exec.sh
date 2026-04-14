#!/usr/bin/env bash
# Claude Octopus — Gemini CLI wrapper with model fallback
# ═══════════════════════════════════════════════════════════════════════════════
# WHY: Gemini preview models (e.g. gemini-3.1-pro-preview) can return 404
#   ModelNotFoundError mid-workflow when account quota or regional availability
#   changes. Without an in-band fallback, the whole workflow aborts and callers
#   revert to single-provider mode, silently losing the multi-AI signal.
#
# WHY NOT retry transient errors (429, 5xx, timeout): that is the circuit
#   breaker's job (lib/provider-router.sh). Retrying the SAME model on a
#   transient fault is the breaker's call; retrying a DIFFERENT model on a
#   permanent "not found" is ours.
#
# USAGE:
#   echo "prompt" | gemini-exec.sh <primary_model> [additional gemini flags...]
#
# ENV:
#   OCTOPUS_GEMINI_FALLBACK_MODELS  Colon-separated fallbacks. Default:
#                                   "gemini-2.5-flash" (GA, always available).
#   OCTOPUS_GEMINI_ALLOWED_MODELS   Comma-separated policy allowlist; when set,
#                                   fallback candidates outside it are dropped
#                                   so cost/compliance gates are not bypassed.
#   OCTOPUS_GEMINI_FALLBACK_QUIET   If "true", suppress fallback INFO log.
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "gemini-exec.sh: missing primary model argument" >&2
    echo "usage: gemini-exec.sh <model> [gemini flags...]" >&2
    exit 2
fi

primary_model="$1"
shift

# WHY allowlist filter: a cost/compliance gate declared at dispatch time must
# not be silently bypassed by an implicit fallback.
allowed_models="${OCTOPUS_GEMINI_ALLOWED_MODELS:-}"
IFS=':' read -r -a fallback_arr <<<"${OCTOPUS_GEMINI_FALLBACK_MODELS:-gemini-2.5-flash}"
declare -a model_list=("$primary_model")
for m in "${fallback_arr[@]}"; do
    [[ -z "$m" || "$m" == "$primary_model" ]] && continue
    if [[ -n "$allowed_models" && ",$allowed_models," != *",$m,"* ]]; then
        continue
    fi
    skip=0
    for existing in "${model_list[@]}"; do
        [[ "$existing" == "$m" ]] && { skip=1; break; }
    done
    [[ $skip -eq 0 ]] && model_list+=("$m")
done

# WHY cache stdin: the Gemini CLI consumes it once, so retry attempts need a
# replayable copy.
prompt_file=""
stdout_file=$(mktemp -t "octo-gemini-stdout.XXXXXX")
trap 'rm -f "${prompt_file:-}" "${stdout_file:-}" "${err_file:-}"' EXIT

if [[ ! -t 0 ]]; then
    prompt_file=$(mktemp -t "octo-gemini-prompt.XXXXXX")
    cat > "$prompt_file"
fi

# WHY bash pattern matching instead of `grep -q`: under `set -o pipefail`,
# `printf | grep -q` can return non-zero because printf sees EPIPE when grep
# exits early on a match, intermittently misclassifying real model errors.
is_model_error() {
    (
        shopt -s nocasematch
        [[ "$1" =~ 404|ModelNotFoundError|model.*not.*(found|available|exist)|unknown[[:space:]]model|invalid[[:space:]]model ]]
    )
}

last_exit=0
last_err=""
attempt=0
total=${#model_list[@]}

for model in "${model_list[@]}"; do
    attempt=$((attempt + 1))
    err_file=$(mktemp -t "octo-gemini-stderr.XXXXXX")
    : > "$stdout_file"

    # WHY buffer stdout: a failed attempt's partial stdout would otherwise leak
    # into the caller's stream before the fallback runs, corrupting downstream
    # parsing. Only the winning attempt's stdout is forwarded.
    set +e
    if [[ -n "$prompt_file" ]]; then
        gemini -m "$model" "$@" <"$prompt_file" >"$stdout_file" 2>"$err_file"
    else
        gemini -m "$model" "$@" >"$stdout_file" 2>"$err_file"
    fi
    last_exit=$?
    set -e

    if [[ $last_exit -eq 0 ]]; then
        cat "$stdout_file"
        cat "$err_file" >&2
        rm -f "$err_file"
        exit 0
    fi

    last_err=$(<"$err_file")
    rm -f "$err_file"

    if is_model_error "$last_err" && [[ $attempt -lt $total ]]; then
        if [[ "${OCTOPUS_GEMINI_FALLBACK_QUIET:-false}" != "true" ]]; then
            next="${model_list[$attempt]}"
            printf 'gemini-exec: %s returned model-not-found; falling back to %s\n' \
                "$model" "$next" >&2
        fi
        continue
    fi

    printf '%s' "$last_err" >&2
    exit "$last_exit"
done

printf '%s' "$last_err" >&2
exit "$last_exit"
