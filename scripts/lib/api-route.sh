#!/usr/bin/env bash
# Share the explicit model pin across dispatch and local provider checks.
_octo_api_route_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! declare -f octo_model_automatic_target_allowed >/dev/null 2>&1; then
    source "${_octo_api_route_lib_dir}/models.sh" || return 1
fi

octo_api_route_model() {
    local model config_file
    if [[ $# -gt 0 ]]; then
        model="$1"
    else
        model="${API_ROUTE_MODEL:-${OCTOPUS_API_ROUTE_MODEL:-${OPENAI_COMPAT_MODEL:-}}}"
    fi
    config_file="${OCTOPUS_PROVIDERS_CONFIG:-${HOME}/.claude-octopus/config/providers.json}"
    if [[ $# -eq 0 && -z "$model" && -f "$config_file" ]]; then
        command -v jq >/dev/null 2>&1 || return 1
        model="$(jq -er '.providers["api-route"].default
            | select(type == "string" and length > 0)
            | select(test("[\u0000-\u0020\u007f]") | not)' "$config_file" 2>/dev/null)" || return 1
    fi
    [[ -n "$model" && "$model" != /* ]] || return 1
    [[ "$model" =~ [[:cntrl:]] ]] && return 1
    # Match the dispatch model-name grammar without loading the model resolver.
    case "$model" in
        *[[:space:]]*|*\\*|*';'*|*'|'*|*'&'*|*'$'*|*'`'*|*"'"*|*'"'*|*'('*|*')'*|*'<'*|*'>'*|*'!'*|*'*'*|*'?'*|*'['*|*']'*|*'{'*|*'}'*) return 1 ;;
    esac
    printf '%s\n' "$model"
}

# API Route has no ranked fallback catalog. As in validate_model_allowed,
# use the first allowed model when the pin is blocked, then validate that
# automatic target before any readiness or dispatch path admits it.
octo_api_route_effective_model() {
    local model fallback allowlist="${API_ROUTE_ALLOWED_MODELS:-}"
    model="$(octo_api_route_model "$@")" || return 1
    if [[ -n "$allowlist" && ",$allowlist," != *",$model,"* ]]; then
        fallback="${allowlist%%,*}"
        octo_api_route_model "$fallback" >/dev/null || return 1
        octo_model_automatic_target_allowed "$fallback" api-route || return 1
        model="$fallback"
    fi
    printf '%s\n' "$model"
}
