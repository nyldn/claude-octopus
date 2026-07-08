#!/usr/bin/env bash
# Source-safe helpers for generic OpenAI-compatible provider availability.

openai_compatible_api_key_env() {
    echo "${OPENAI_COMPAT_API_KEY_ENV:-OPENAI_API_KEY}"
}

openai_compatible_is_available() {
    local compat_key_env
    compat_key_env="$(openai_compatible_api_key_env)"
    [[ -n "${OPENAI_COMPAT_BASE_URL:-}" && ( -n "${OPENAI_COMPAT_API_KEY:-}" || -n "${!compat_key_env:-}" ) ]]
}
