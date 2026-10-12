#!/usr/bin/env bash
# Share the explicit model pin and proxy URL across dispatch and local provider checks.
_octo_litellm_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! declare -f octo_model_automatic_target_allowed >/dev/null 2>&1; then
    source "${_octo_litellm_lib_dir}/models.sh" || return 1
fi

octo_litellm_model() {
    local model config_file
    if [[ $# -gt 0 ]]; then
        model="$1"
    else
        model="${LITELLM_MODEL:-${OCTOPUS_LITELLM_MODEL:-}}"
    fi
    config_file="${OCTOPUS_PROVIDERS_CONFIG:-${HOME}/.claude-octopus/config/providers.json}"
    if [[ $# -eq 0 && -z "$model" && -f "$config_file" ]]; then
        command -v jq >/dev/null 2>&1 || return 1
        model="$(jq -er '.providers.litellm.default
            | select(type == "string" and length > 0)
            | select(test("[\u0000- \u007f]") | not)' "$config_file" 2>/dev/null)" || return 1
    fi
    [[ -n "$model" && "$model" != /* ]] || return 1
    [[ "$model" =~ [[:cntrl:]] ]] && return 1
    # Commas delimit allowlist entries and cannot be part of one model token.
    # Match the remaining dispatch grammar without loading the model resolver.
    case "$model" in
        *[[:space:]]*|*','*|*\\*|*';'*|*'|'*|*'&'*|*'$'*|*'`'*|*"'"*|*'"'*|*'('*|*')'*|*'<'*|*'>'*|*'!'*|*'*'*|*'?'*|*'['*|*']'*|*'{'*|*'}'*) return 1 ;;
    esac
    printf '%s\n' "$model"
}

# LiteLLM has no ranked fallback catalog. As in validate_model_allowed,
# use the first allowed model when the pin is blocked, then validate that
# automatic target before any readiness or dispatch path admits it.
octo_litellm_effective_model() {
    local model fallback allowlist="${LITELLM_ALLOWED_MODELS:-}"
    model="$(octo_litellm_model "$@")" || return 1
    if [[ -n "$allowlist" && ",$allowlist," != *",$model,"* ]]; then
        fallback="${allowlist%%,*}"
        octo_litellm_model "$fallback" >/dev/null || return 1
        octo_model_automatic_target_allowed "$fallback" litellm || return 1
        model="$fallback"
    fi
    printf '%s\n' "$model"
}

# LiteLLM is self-hosted, so unlike the other gateways its endpoint is user
# configuration. Read LITELLM_BASE_URL only from the operator's environment
# (or the argument), defaulting to http://localhost:4000, and normalize it to the
# proxy's OpenAI-compatible root ending in /v1. The proxy serves its routes with
# and without /v1, so both spellings resolve to the same endpoint, and a path
# prefix such as https://host/litellm is kept.
#
# OCTO_LITELLM_BASE_URL_RE is the --base-url grammar that
# _validate_openai_compatible_agent_command in utils.sh enforces at dispatch;
# keep the two identical so a URL reported ready is also dispatchable. The
# host starts alphanumeric and may contain underscores (Docker Compose service
# names), the port is digits only, and the path uses a fixed safe set. "@" is
# outside the grammar, so embedded credentials, which the helper would log,
# are rejected, and the value stays one shell-safe token of the command line.
OCTO_LITELLM_BASE_URL_RE='^https?://[A-Za-z0-9][A-Za-z0-9._-]*(:[0-9]+)?(/[A-Za-z0-9._/:-]*)?$'

octo_litellm_base_url() {
    local url="${1:-}"
    if [[ $# -eq 0 ]]; then
        # A project .env must not choose where an independently supplied key goes.
        url="${LITELLM_BASE_URL:-http://localhost:4000}"
    fi
    [[ "$url" =~ $OCTO_LITELLM_BASE_URL_RE ]] || return 1
    # Match the helper's transport policy before any credentialed probe runs.
    if [[ "$url" == http://* && ! "$url" =~ ^http://(localhost|127\.0\.0\.1)(:[0-9]+)?(/|$) ]]; then
        return 1
    fi
    while [[ "$url" == */ ]]; do url="${url%/}"; done
    url="${url%/v1}"
    while [[ "$url" == */ ]]; do url="${url%/}"; done
    url="${url}/v1"
    [[ "$url" =~ $OCTO_LITELLM_BASE_URL_RE ]] || return 1
    printf '%s\n' "$url"
}
