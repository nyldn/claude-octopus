#!/usr/bin/env bash
# Host runtime detection shared by orchestrate.sh, lifecycle.sh and
# plugin-update.sh. Source-safe: no main execution block.
#
# Runtime markers outrank configuration hints. Codex injects CODEX_THREAD_ID,
# CODEX_SESSION_ID and CODEX_VERSION into every command it runs (and
# CODEX_SANDBOX under the macOS sandbox), and it also supplies
# CLAUDE_PLUGIN_ROOT to plugin hooks, so Codex markers are checked first.
# CODEX_HOME only names a config directory and is often exported globally, so
# it is the last hint: treating it as a runtime marker made Claude Code
# sessions look like Codex hosts, which marked codex council seats host-native.

# True when a path is inside a Codex plugin cache (default or CODEX_HOME).
_octo_is_codex_plugin_cache() {
    local root="${1:-}" codex_home="${CODEX_HOME:-}"
    [[ -n "$root" ]] || return 1
    [[ "$root" == *"/.codex/plugins/cache/"* ]] && return 0
    codex_home="${codex_home%/}"
    [[ -n "$codex_home" && "$root" == "$codex_home/plugins/cache/"* ]]
}

# Print factory, codex, claude or standalone.
octo_detect_host_runtime() {
    local plugin_root="${1:-}"

    if [[ -n "${DROID_PLUGIN_ROOT:-}" ]]; then
        printf 'factory\n'
    elif [[ -n "${CODEX_THREAD_ID:-}" || -n "${CODEX_SESSION_ID:-}" || \
            -n "${CODEX_SANDBOX:-}" || -n "${CODEX_PLUGIN_ROOT:-}" ]]; then
        printf 'codex\n'
    elif _octo_is_codex_plugin_cache "${CLAUDE_PLUGIN_ROOT:-}"; then
        # Codex supplies CLAUDE_PLUGIN_ROOT to plugin hooks; a root inside a
        # Codex plugin cache still means Codex (same rule as safety-contract.py).
        printf 'codex\n'
    elif [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
        printf 'claude\n'
    elif [[ "$plugin_root" == *"/.codex/"* ]]; then
        printf 'codex\n'
    elif [[ "$plugin_root" == *"/.claude/"* ]]; then
        printf 'claude\n'
    elif [[ -n "${CODEX_HOME:-}" ]]; then
        printf 'codex\n'
    else
        printf 'standalone\n'
    fi
}
