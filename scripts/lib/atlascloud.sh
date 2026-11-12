#!/usr/bin/env bash
# Share the explicit model pin across dispatch and local provider checks.
_octo_atlascloud_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! declare -f octo_model_automatic_target_allowed >/dev/null 2>&1; then
    source "${_octo_atlascloud_lib_dir}/models.sh" || return 1
fi

octo_atlascloud_model() {
    local model config_file from_config=false
    if [[ $# -gt 0 ]]; then
        model="$1"
    else
        model="${ATLASCLOUD_MODEL:-${OCTOPUS_ATLASCLOUD_MODEL:-}}"
    fi
    config_file="${OCTOPUS_PROVIDERS_CONFIG:-${HOME}/.claude-octopus/config/providers.json}"
    if [[ $# -eq 0 && -z "$model" && -f "$config_file" ]]; then
        command -v jq >/dev/null 2>&1 || return 1
        model="$(jq -er '(.providers.atlascloud.default // .providers.atlascloud.model)
            | select(type == "string" and length > 0)
            | select(test("[\u0000-\u0020\u007f]") | not)' "$config_file" 2>/dev/null)" || return 1
        from_config=true
    fi
    [[ -n "$model" && "$model" != /* ]] || return 1
    [[ "$model" =~ [[:cntrl:]] ]] && return 1
    # Commas delimit allowlist entries and cannot be part of one model token.
    # Match the remaining dispatch grammar without loading the model resolver.
    case "$model" in
        *[[:space:]]*|*','*|*\\*|*';'*|*'|'*|*'&'*|*'$'*|*'`'*|*"'"*|*'"'*|*'('*|*')'*|*'<'*|*'>'*|*'!'*|*'*'*|*'?'*|*'['*|*']'*|*'{'*|*'}'*) return 1 ;;
    esac
    [[ "$from_config" != true ]] || octo_model_automatic_target_allowed "$model" atlascloud || return 1
    printf '%s\n' "$model"
}

