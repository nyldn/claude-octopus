#!/usr/bin/env bash
# Claude Octopus plugin update health and explicit host-managed updates.
#
# Source-safe. Status inspection is local-only: it reads the loaded manifest and
# host package-manager state, but never invokes a CLI or performs network I/O.
# octo_plugin_update_run is the only function allowed to invoke an updater, and
# callers must select it explicitly.

octo_plugin_version_gt() {
    local candidate="${1:-}" baseline="${2:-}"
    [[ -n "$candidate" && -n "$baseline" && "$candidate" != "unknown" && "$baseline" != "unknown" ]] || return 1
    awk -v a="$candidate" -v b="$baseline" '
        BEGIN {
            sub(/^v/, "", a); sub(/^v/, "", b)
            split(a, av, /[^0-9]+/); split(b, bv, /[^0-9]+/)
            for (i = 1; i <= 4; i++) {
                ai = (av[i] == "" ? 0 : av[i] + 0)
                bi = (bv[i] == "" ? 0 : bv[i] + 0)
                if (ai > bi) exit 0
                if (ai < bi) exit 1
            }
            exit 1
        }
    '
}

octo_plugin_newest_version() {
    local versions="${1:-}" newest="" version=""
    while IFS= read -r version; do
        [[ -n "$version" && "$version" != "null" && "$version" != "unknown" ]] || continue
        if [[ -z "$newest" ]] || octo_plugin_version_gt "$version" "$newest"; then
            newest="$version"
        fi
    done <<EOF
$versions
EOF
    printf '%s\n' "${newest:-unknown}"
}

octo_plugin_version_gte() {
    local candidate="${1:-}" baseline="${2:-}"
    [[ "$candidate" == "$baseline" && "$candidate" != "unknown" ]] \
        || octo_plugin_version_gt "$candidate" "$baseline"
}

octo_plugin_update_confirmed() {
    local expected="${1:-unknown}"
    local confirmed
    confirmed="$(octo_plugin_newest_version "${OCTO_PLUGIN_INSTALLED_VERSION}
${OCTO_PLUGIN_CACHE_VERSION}")"

    if [[ "$expected" == "unknown" ]]; then
        printf 'Host update commands completed, but no expected plugin version could be determined from local metadata.\n' >&2
        return 1
    fi
    if ! octo_plugin_version_gte "$confirmed" "$expected"; then
        printf 'Host update commands exited successfully, but local state did not confirm the update (expected %s; installed %s; cache %s).\n' \
            "$expected" "$OCTO_PLUGIN_INSTALLED_VERSION" "$OCTO_PLUGIN_CACHE_VERSION" >&2
        return 1
    fi
    return 0
}

octo_plugin_detect_host() {
    local plugin_root="${1:-}"
    if [[ -n "${OCTOPUS_PLUGIN_HOST:-}" ]]; then
        printf '%s\n' "$OCTOPUS_PLUGIN_HOST"
    elif [[ -n "${DROID_PLUGIN_ROOT:-}" ]]; then
        printf 'factory\n'
    elif [[ -n "${CODEX_HOME:-}" || -n "${CODEX_SANDBOX:-}" || -n "${CODEX_PLUGIN_ROOT:-}" ]]; then
        printf 'codex\n'
    elif [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
        printf 'claude\n'
    elif [[ "$plugin_root" == *"/.codex/"* ]]; then
        printf 'codex\n'
    elif [[ "$plugin_root" == *"/.claude/"* ]]; then
        printf 'claude\n'
    else
        printf 'standalone\n'
    fi
}

octo_plugin_running_inside_codex() {
    local override="${OCTOPUS_CODEX_ACTIVE_SESSION:-auto}"
    local process_pid="${1:-${PPID:-}}" process_name="" parent_pid="" depth=0

    case "$override" in
        true|1|yes) return 0 ;;
    esac

    [[ -n "${CODEX_SANDBOX:-}" || -n "${CODEX_PLUGIN_ROOT:-}" ]] && return 0

    case "$override" in
        false|0|no) return 1 ;;
    esac

    command -v ps >/dev/null 2>&1 || return 2
    [[ "$process_pid" =~ ^[0-9]+$ ]] || return 2
    [[ "$process_pid" -gt 1 ]] || return 2
    while [[ "$process_pid" -gt 1 ]]; do
        [[ "$depth" -lt 12 ]] || return 2
        process_name="$(ps -o comm= -p "$process_pid" 2>/dev/null)" || return 2
        process_name="$(printf '%s' "$process_name" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        [[ -n "$process_name" ]] || return 2
        process_name="${process_name##*/}"
        case "$process_name" in
            codex|codex.exe) return 0 ;;
        esac

        parent_pid="$(ps -o ppid= -p "$process_pid" 2>/dev/null)" || return 2
        parent_pid="${parent_pid//[[:space:]]/}"
        [[ "$parent_pid" =~ ^[0-9]+$ ]] || return 2
        [[ "$parent_pid" != "$process_pid" ]] || return 2
        process_pid="$parent_pid"
        depth=$((depth + 1))
    done

    return 1
}

octo_plugin_update_load() {
    local plugin_root="${1:-${CLAUDE_PLUGIN_ROOT:-}}"
    local requested_host="${2:-}"
    local host_root="" plugin_name="octo" installed_key="octo@nyldn-plugins"
    local manifest="${OCTOPUS_UPDATE_MANIFEST:-${plugin_root}/.claude-plugin/plugin.json}"
    local installed_file="" catalog_file="" cache_root="" known_file=""
    local versions="" cache_versions="" entry_type=""

    OCTO_PLUGIN_UPDATE_HOST="${requested_host:-$(octo_plugin_detect_host "$plugin_root")}"
    OCTO_PLUGIN_LOADED_VERSION="unknown"
    OCTO_PLUGIN_INSTALLED_VERSION="unknown"
    OCTO_PLUGIN_CATALOG_VERSION="unknown"
    OCTO_PLUGIN_CACHE_VERSION="unknown"
    OCTO_PLUGIN_NEWEST_VERSION="unknown"
    OCTO_PLUGIN_AUTO_UPDATE="unavailable"
    OCTO_PLUGIN_UPDATE_AVAILABLE="false"
    OCTO_PLUGIN_RELOAD_REQUIRED="false"

    command -v jq >/dev/null 2>&1 || return 0
    if [[ -r "$manifest" ]]; then
        OCTO_PLUGIN_LOADED_VERSION="$(jq -r '.version // "unknown"' "$manifest" 2>/dev/null || printf 'unknown\n')"
    fi

    case "$OCTO_PLUGIN_UPDATE_HOST" in
        claude)
            host_root="${OCTOPUS_CLAUDE_DIR:-${HOME}/.claude}"
            known_file="${host_root}/plugins/known_marketplaces.json"
            installed_file="${host_root}/plugins/installed_plugins.json"
            catalog_file="${host_root}/plugins/marketplaces/nyldn-plugins/.claude-plugin/marketplace.json"
            cache_root="${host_root}/plugins/cache/nyldn-plugins/octo"

            if [[ ! -e "$known_file" ]]; then
                OCTO_PLUGIN_AUTO_UPDATE="missing"
            elif ! jq -e . "$known_file" >/dev/null 2>&1; then
                OCTO_PLUGIN_AUTO_UPDATE="malformed"
            elif ! jq -e 'has("nyldn-plugins") and (."nyldn-plugins" | has("autoUpdate"))' "$known_file" >/dev/null 2>&1; then
                OCTO_PLUGIN_AUTO_UPDATE="missing"
            else
                entry_type="$(jq -r '."nyldn-plugins".autoUpdate | type' "$known_file" 2>/dev/null || printf 'invalid\n')"
                if [[ "$entry_type" == "boolean" ]]; then
                    if jq -e '."nyldn-plugins".autoUpdate == true' "$known_file" >/dev/null 2>&1; then
                        OCTO_PLUGIN_AUTO_UPDATE="enabled"
                    else
                        OCTO_PLUGIN_AUTO_UPDATE="disabled"
                    fi
                else
                    OCTO_PLUGIN_AUTO_UPDATE="malformed"
                fi
            fi
            ;;
        codex)
            host_root="${OCTOPUS_CODEX_DIR:-${CODEX_HOME:-${HOME}/.codex}}"
            plugin_name="claude-octopus"
            installed_key="claude-octopus@nyldn-plugins"
            installed_file="${host_root}/plugins/installed_plugins.json"
            catalog_file="${host_root}/plugins/marketplaces/nyldn-plugins/.claude-plugin/marketplace.json"
            cache_root="${host_root}/plugins/cache/nyldn-plugins/claude-octopus"
            ;;
        *)
            return 0
            ;;
    esac

    if [[ -r "$installed_file" ]]; then
        versions="$(jq -r --arg key "$installed_key" '.plugins[$key] // [] | if type == "array" then .[] else . end | .version // empty' "$installed_file" 2>/dev/null || true)"
        OCTO_PLUGIN_INSTALLED_VERSION="$(octo_plugin_newest_version "$versions")"
    fi
    if [[ -r "$catalog_file" ]]; then
        OCTO_PLUGIN_CATALOG_VERSION="$(jq -r --arg name "$plugin_name" '.plugins[]? | select(.name == $name) | .version // empty' "$catalog_file" 2>/dev/null | head -1 || true)"
        OCTO_PLUGIN_CATALOG_VERSION="${OCTO_PLUGIN_CATALOG_VERSION:-unknown}"
    fi
    if [[ -d "$cache_root" ]]; then
        local cache_dir=""
        for cache_dir in "$cache_root"/*; do
            [[ -d "$cache_dir" ]] || continue
            cache_versions="${cache_versions}${cache_versions:+$'\n'}$(basename "$cache_dir")"
        done
        OCTO_PLUGIN_CACHE_VERSION="$(octo_plugin_newest_version "$cache_versions")"
    fi

    OCTO_PLUGIN_NEWEST_VERSION="$(octo_plugin_newest_version "${OCTO_PLUGIN_INSTALLED_VERSION}
${OCTO_PLUGIN_CATALOG_VERSION}
${OCTO_PLUGIN_CACHE_VERSION}")"
    if octo_plugin_version_gt "$OCTO_PLUGIN_NEWEST_VERSION" "$OCTO_PLUGIN_LOADED_VERSION"; then
        OCTO_PLUGIN_UPDATE_AVAILABLE="true"
    fi
    if octo_plugin_version_gt "$OCTO_PLUGIN_INSTALLED_VERSION" "$OCTO_PLUGIN_LOADED_VERSION"; then
        OCTO_PLUGIN_RELOAD_REQUIRED="true"
    fi
}

octo_plugin_update_run() {
    local plugin_root="${1:-${CLAUDE_PLUGIN_ROOT:-}}"
    local host="${2:-$(octo_plugin_detect_host "$plugin_root")}"
    local expected_before="unknown" expected_after="unknown" codex_session_rc=0

    octo_plugin_update_load "$plugin_root" "$host"
    expected_before="$OCTO_PLUGIN_NEWEST_VERSION"

    case "$host" in
        claude)
            if ! command -v claude >/dev/null 2>&1; then
                printf 'Claude Code CLI is not available; update through /plugin instead.\n' >&2
                return 1
            fi
            printf 'Refreshing the nyldn-plugins marketplace with Claude Code...\n'
            claude plugin marketplace update nyldn-plugins || return $?
            claude plugin update octo@nyldn-plugins || return $?
            octo_plugin_update_load "$plugin_root" claude
            expected_after="$(octo_plugin_newest_version "${expected_before}
${OCTO_PLUGIN_CATALOG_VERSION}")"
            octo_plugin_update_confirmed "$expected_after" || return $?
            printf 'Host update commands completed (loaded %s; installed %s; newest local %s).\n' \
                "$OCTO_PLUGIN_LOADED_VERSION" "$OCTO_PLUGIN_INSTALLED_VERSION" \
                "$OCTO_PLUGIN_NEWEST_VERSION"
            printf 'Run /reload-plugins or restart Claude Code before continuing.\n'
            ;;
        codex)
            octo_plugin_running_inside_codex "" || codex_session_rc=$?
            if [[ "$codex_session_rc" -eq 0 ]]; then
                printf '%s\n' \
                    'Claude Octopus will not replace its plugin cache from inside the running Codex session.' \
                    'Exit Codex, run the update outside the running Codex session, then start Codex again:' \
                    '  codex plugin marketplace upgrade nyldn-plugins' \
                    '  codex plugin add claude-octopus@nyldn-plugins' >&2
                return 2
            fi
            if [[ "$codex_session_rc" -ne 1 ]]; then
                printf '%s\n' \
                    'Claude Octopus could not safely determine whether this terminal belongs to a running Codex session.' \
                    'No update was attempted. Run the update from a separate terminal, or set OCTOPUS_CODEX_ACTIVE_SESSION=false there.' >&2
                return 2
            fi
            if ! command -v codex >/dev/null 2>&1; then
                printf 'Codex CLI is not available; update through the Codex plugin manager instead.\n' >&2
                return 1
            fi
            printf 'Refreshing the nyldn-plugins marketplace with Codex...\n'
            codex plugin marketplace upgrade nyldn-plugins || return $?
            codex plugin add claude-octopus@nyldn-plugins || return $?
            octo_plugin_update_load "$plugin_root" codex
            expected_after="$(octo_plugin_newest_version "${expected_before}
${OCTO_PLUGIN_CATALOG_VERSION}")"
            octo_plugin_update_confirmed "$expected_after" || return $?
            printf 'Host update commands completed (loaded %s; installed %s; newest local %s).\n' \
                "$OCTO_PLUGIN_LOADED_VERSION" "$OCTO_PLUGIN_INSTALLED_VERSION" \
                "$OCTO_PLUGIN_NEWEST_VERSION"
            printf 'Restart Codex before continuing.\n'
            ;;
        factory)
            printf 'Factory manages plugin updates. Update octo@nyldn-plugins through the Factory plugin manager, then restart the session.\n' >&2
            return 2
            ;;
        *)
            printf 'No host-managed updater was detected. Update the installation source, then restart the host.\n' >&2
            return 2
            ;;
    esac
}
