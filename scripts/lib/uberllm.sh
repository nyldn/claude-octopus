#!/usr/bin/env bash
# Share the explicit model pin across dispatch and local provider checks.
_octo_uberllm_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! declare -f octo_model_automatic_target_allowed >/dev/null 2>&1; then
    source "${_octo_uberllm_lib_dir}/models.sh" || return 1
fi

octo_uberllm_model() {
    local model config_file
    if [[ $# -gt 0 ]]; then
        model="$1"
    else
        model="${UBERLLM_MODEL:-${OCTOPUS_UBERLLM_MODEL:-}}"
    fi
    config_file="${OCTOPUS_PROVIDERS_CONFIG:-${HOME}/.claude-octopus/config/providers.json}"
    if [[ $# -eq 0 && -z "$model" && -f "$config_file" ]]; then
        command -v jq >/dev/null 2>&1 || return 1
        model="$(jq -er '.providers.uberllm.default
            | select(type == "string" and length > 0)
            | select(test("[\u0000-\u0020\u007f]") | not)' "$config_file" 2>/dev/null)" || return 1
    fi
    [[ -n "$model" && "$model" != /* ]] || return 1
    [[ "$model" =~ [[:cntrl:]] ]] && return 1
    # Commas delimit allowlist entries; one model must remain one token.
    case "$model" in
        *[[:space:]]*|*','*|*\\*|*';'*|*'|'*|*'&'*|*'$'*|*'`'*|*"'"*|*'"'*|*'('*|*')'*|*'<'*|*'>'*|*'!'*|*'*'*|*'?'*|*'['*|*']'*|*'{'*|*'}'*) return 1 ;;
    esac
    printf '%s\n' "$model"
}

octo_uberllm_effective_model() {
    local model fallback allowlist="${UBERLLM_ALLOWED_MODELS:-}"
    model="$(octo_uberllm_model "$@")" || return 1
    if [[ -n "$allowlist" && ",$allowlist," != *",$model,"* ]]; then
        fallback="${allowlist%%,*}"
        octo_uberllm_model "$fallback" >/dev/null || return 1
        octo_model_automatic_target_allowed "$fallback" uberllm || return 1
        model="$fallback"
    fi
    if [[ $# -eq 0 && -z "${UBERLLM_MODEL:-${OCTOPUS_UBERLLM_MODEL:-}}" ]]; then
        octo_model_automatic_target_allowed "$model" uberllm || return 1
    fi
    printf '%s\n' "$model"
}
