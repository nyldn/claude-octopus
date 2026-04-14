#!/usr/bin/env bash
# Claude Octopus — Gemini CLI wrapper with model fallback
# ═══════════════════════════════════════════════════════════════════════════════
# WHY: Gemini preview models (e.g. gemini-3.1-pro-preview) can return 404
#   ModelNotFoundError mid-workflow when account quota or regional availability
#   changes. Without an in-band fallback, the whole workflow aborts and callers
#   revert to single-provider mode, silently losing the multi-AI signal.
#
# WHAT: This wrapper runs the Gemini CLI with a primary model, then on any
#   hard "model" failure (404 / ModelNotFoundError / "model ... not available")
#   retries the same invocation with each fallback in OCTOPUS_GEMINI_FALLBACK_MODELS
#   until one succeeds or the list is exhausted.
#
# NOT WHAT: This does NOT retry on transient errors (429, 5xx, timeout) — those
#   are the circuit breaker's job (lib/provider-router.sh). We only handle the
#   specific class of "this model name is not addressable" errors, which no
#   amount of retrying the SAME model will fix.
#
# USAGE:
#   echo "prompt" | gemini-exec.sh <primary_model> [additional gemini flags...]
#
# ENV:
#   OCTOPUS_GEMINI_FALLBACK_MODELS  Colon-separated fallbacks. Default:
#                                   "gemini-2.5-flash" (GA, always available).
#   OCTOPUS_GEMINI_FALLBACK_QUIET   If "true", suppress fallback INFO log.
#
# EXIT:
#   0    Primary or a fallback succeeded.
#   N    Exit code of the last attempted model if all attempts failed.
# ═══════════════════════════════════════════════════════════════════════════════

set -o pipefail

if [[ $# -lt 1 ]]; then
    echo "gemini-exec.sh: missing primary model argument" >&2
    echo "usage: gemini-exec.sh <model> [gemini flags...]" >&2
    exit 2
fi

primary_model="$1"
shift

# Build the ordered model list: primary, then fallbacks, dedup in order.
IFS=':' read -r -a fallback_arr <<<"${OCTOPUS_GEMINI_FALLBACK_MODELS:-gemini-2.5-flash}"
declare -a model_list=("$primary_model")
for m in "${fallback_arr[@]}"; do
    [[ -z "$m" || "$m" == "$primary_model" ]] && continue
    # Dedup
    skip=0
    for existing in "${model_list[@]}"; do
        [[ "$existing" == "$m" ]] && { skip=1; break; }
    done
    [[ $skip -eq 0 ]] && model_list+=("$m")
done

# The Gemini CLI consumes stdin once. To retry with a different model we must
# cache the prompt to a temp file the first time we read stdin.
prompt_file=""
if [[ ! -t 0 ]]; then
    prompt_file=$(mktemp -t "octo-gemini-prompt.XXXXXX")
    trap 'rm -f "$prompt_file"' EXIT
    cat > "$prompt_file"
fi

# Classify a gemini invocation's stderr to decide whether to fall back.
# Returns 0 when the error class is "model addressability" (fallback-eligible).
is_model_error() {
    local err="$1"
    # Preview CLI emits "ModelNotFoundError" plus HTTP 404 in the status line.
    # Also match the human-phrased variants surfaced by different CLI versions.
    printf '%s' "$err" | grep -qiE '404|ModelNotFoundError|model.*not.*(found|available|exist)|unknown model|invalid model'
}

last_exit=0
last_err=""
attempt=0
total=${#model_list[@]}

for model in "${model_list[@]}"; do
    attempt=$((attempt + 1))
    err_file=$(mktemp -t "octo-gemini-stderr.XXXXXX")

    if [[ -n "$prompt_file" ]]; then
        gemini -m "$model" "$@" <"$prompt_file" 2>"$err_file"
    else
        gemini -m "$model" "$@" 2>"$err_file"
    fi
    last_exit=$?

    if [[ $last_exit -eq 0 ]]; then
        # Success — forward stderr (may contain non-fatal warnings) and exit.
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

    # Non-fallback-eligible error, or out of fallbacks — surface the last stderr.
    printf '%s' "$last_err" >&2
    exit "$last_exit"
done

# Exhausted list (defensive — loop above should have exited).
printf '%s' "$last_err" >&2
exit "$last_exit"
