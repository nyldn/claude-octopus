#!/usr/bin/env bash
# Source-safe helpers for generic OpenAI-compatible provider availability.

_openai_compatible_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if ! declare -f _octo_value_has_nonwhitespace >/dev/null 2>&1; then
    source "${_openai_compatible_lib_dir}/auth.sh" 2>/dev/null || true
fi

openai_compatible_api_key_env() {
    echo "${OPENAI_COMPAT_API_KEY_ENV:-OPENAI_API_KEY}"
}

openai_compatible_api_key_value() {
    local compat_key_env
    compat_key_env="$(openai_compatible_api_key_env)"
    [[ "$compat_key_env" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1
    printf '%s\n' "${!compat_key_env:-}"
}

openai_compatible_is_available() {
    local compat_key_value=""
    compat_key_value="$(openai_compatible_api_key_value 2>/dev/null || true)"
    _octo_value_has_nonwhitespace "${OPENAI_COMPAT_BASE_URL:-}" && \
        { _octo_value_has_nonwhitespace "${OPENAI_COMPAT_API_KEY:-}" || \
          _octo_value_has_nonwhitespace "$compat_key_value"; }
}
