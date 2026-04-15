#!/usr/bin/env bash
# In-band fallback only on model-not-found; transient errors stay with provider-router.

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "gemini-exec.sh: missing primary model argument" >&2
    echo "usage: gemini-exec.sh <model> [gemini flags...]" >&2
    exit 2
fi

primary_model="$1"
shift

# Allowlist gates the primary too — a direct call must not bypass policy.
allowed_models="${OCTOPUS_GEMINI_ALLOWED_MODELS:-}"
if [[ -n "$allowed_models" && ",$allowed_models," != *",$primary_model,"* ]]; then
    printf 'gemini-exec: model %s is not in OCTOPUS_GEMINI_ALLOWED_MODELS\n' \
        "$primary_model" >&2
    exit 2
fi
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

# Gemini CLI consumes stdin once; cache the prompt so retries can replay it.
prompt_file=""
stdout_file=$(mktemp -t "octo-gemini-stdout.XXXXXX")
trap 'rm -f "${prompt_file:-}" "${stdout_file:-}" "${err_file:-}"' EXIT INT TERM

if [[ ! -t 0 ]]; then
    prompt_file=$(mktemp -t "octo-gemini-prompt.XXXXXX")
    cat > "$prompt_file"
fi

# Pattern must mirror lib/smoke.sh::_classify_smoke_error or fallback drifts.
is_model_error() {
    (
        shopt -s nocasematch
        local _re='model.*not (found|available|exist)|does not exist|unknown model|invalid model|no such model|ModelNotFoundError|404'
        [[ "$1" =~ $_re ]]
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

    # Buffer per attempt so a failed attempt's partial stdout never leaks.
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
