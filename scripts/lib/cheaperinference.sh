#!/usr/bin/env bash
# Share the explicit model pin across dispatch and local provider checks.
octo_cheaperinference_model() {
    local model config_file
    model="${CHEAPER_INFERENCE_MODEL:-${OCTOPUS_CHEAPERINFERENCE_MODEL:-${OPENAI_COMPAT_MODEL:-}}}"
    config_file="${HOME}/.claude-octopus/config/providers.json"
    if [[ -z "$model" && -f "$config_file" ]]; then
        command -v jq >/dev/null 2>&1 || return 1
        model="$(jq -er '.providers.cheaperinference.default
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
