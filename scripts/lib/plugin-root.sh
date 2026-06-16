#!/usr/bin/env bash
# Plugin root helpers for Claude Octopus.
# Source-safe: no main execution block.

octo_is_windows_git_bash() {
    local uname_s="${1:-}"
    if [[ -z "$uname_s" ]]; then
        uname_s="$(uname -s 2>/dev/null || true)"
    fi

    case "$uname_s" in
        MINGW*|MSYS*|CYGWIN*) return 0 ;;
    esac

    [[ "${OS:-}" == "Windows_NT" ]] && {
        [[ -n "${MSYSTEM:-}" ]] || [[ -n "${MINGW_PREFIX:-}" ]] ||
        [[ "${OSTYPE:-}" == msys* ]] || [[ "${OSTYPE:-}" == mingw* ]] ||
        [[ "${OSTYPE:-}" == cygwin* ]]
    }
}

octo_write_stable_script_shim() {
    local plugin_root="$1"
    local stable_root="$2"
    local rel_path="$3"
    local src="${plugin_root}/${rel_path}"
    local dst="${stable_root}/${rel_path}"

    [[ -f "$src" ]] || return 0

    # Refuse to write a shim that resolves to its own source file. If
    # stable_root's children are symlinks into the live plugin cache (rather
    # than stable_root itself being a single symlink), dst can physically
    # resolve to src, and writing the exec stub there corrupts the live
    # script into a self-referential exec loop. See #521.
    local rsrc rdst
    rsrc="$(cd "$(dirname "$src")" 2>/dev/null && pwd -P)/$(basename "$src")"
    rdst="$(cd "$(dirname "$dst")" 2>/dev/null && pwd -P)/$(basename "$dst")"
    [[ -n "$rsrc" && "$rsrc" == "$rdst" ]] && return 0

    local quoted_src
    printf -v quoted_src '%q' "$src"
    mkdir -p "$(dirname "$dst")"
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf 'exec %s "$@"\n' "$quoted_src"
    } > "$dst"
    chmod +x "$dst" 2>/dev/null || true
}

octo_discover_plugin_root() {
    # Auto-discover the Octopus plugin root from CC marketplace cache or Cowork
    # plugin cache. Returns the path on stdout, or empty string on failure.
    # Used when CLAUDE_PLUGIN_ROOT is not set (LLM Bash tool context). (#377)
    local candidate=""

    # Strategy 1: CC marketplace cache (standard install path)
    local cache_base="${HOME}/.claude/plugins/cache/nyldn-plugins/octo"
    if [[ -d "$cache_base" ]]; then
        candidate="$(ls -1dt "$cache_base"/*/ 2>/dev/null | head -1)"
        candidate="${candidate%/}"
        if [[ -n "$candidate" && -f "${candidate}/scripts/orchestrate.sh" ]]; then
            printf '%s' "$candidate"
            return 0
        fi
    fi

    # Strategy 2: Cowork / desktop-app plugin cache
    local search_root
    for search_root in \
        "${HOME}/Library/Application Support/Claude" \
        "${LOCALAPPDATA:-/dev/null}/Claude" \
        "${XDG_DATA_HOME:-${HOME}/.local/share}/Claude"; do
        if [[ -d "$search_root" ]]; then
            local found
            found="$(find "$search_root" -maxdepth 8 -path "*/nyldn-plugins/octo/*/scripts/orchestrate.sh" -print -quit 2>/dev/null)"
            if [[ -n "$found" ]]; then
                candidate="$(cd "$(dirname "$(dirname "$found")")" 2>/dev/null && pwd -P)"
                if [[ -n "$candidate" ]]; then
                    printf '%s' "$candidate"
                    return 0
                fi
            fi
        fi
    done

    return 1
}

octo_ensure_stable_plugin_root() {
    local plugin_root="$1"
    local stable_root="${2:-${HOME}/.claude-octopus/plugin}"

    # If plugin_root is empty or missing, try auto-discovery (#377)
    if [[ -z "$plugin_root" || ! -d "$plugin_root" ]]; then
        plugin_root="$(octo_discover_plugin_root)" || true
    fi

    [[ -n "$plugin_root" && -d "$plugin_root" ]] || return 1

    mkdir -p "$(dirname "$stable_root")"

    # Defense in depth: if the existing stable_root already resolves to the same
    # physical directory as plugin_root, leave it alone. Without this guard, a
    # caller that passes the stable_root path as plugin_root (e.g., from a
    # SCRIPT_DIR resolved without `pwd -P`) would cause us to `rm -f` the
    # symlink and then `ln -s` it pointing at itself → ELOOP. See #371.
    if [[ -L "$stable_root" ]]; then
        local _resolved_plugin _resolved_stable
        _resolved_plugin="$(cd "$plugin_root" 2>/dev/null && pwd -P)" || _resolved_plugin=""
        _resolved_stable="$(cd "$stable_root" 2>/dev/null && pwd -P)" || _resolved_stable=""
        if [[ -n "$_resolved_plugin" && "$_resolved_plugin" == "$_resolved_stable" ]]; then
            return 0
        fi
    fi

    if [[ -L "$stable_root" || -f "$stable_root" ]]; then
        rm -f "$stable_root" 2>/dev/null || true
    fi

    if [[ ! -e "$stable_root" ]]; then
        ln -s "$plugin_root" "$stable_root" 2>/dev/null || true
    fi

    if [[ -L "$stable_root" && -x "$stable_root/scripts/orchestrate.sh" ]]; then
        return 0
    fi

    if [[ -e "$stable_root" && ! -d "$stable_root" ]]; then
        rm -f "$stable_root" 2>/dev/null || true
    fi

    # Windows Git Bash often cannot create native symlinks without Developer
    # Mode/admin rights. Keep the stable path usable by writing tiny wrappers
    # for script entry points referenced by commands and skills.
    mkdir -p "$stable_root"
    octo_write_stable_script_shim "$plugin_root" "$stable_root" "scripts/orchestrate.sh"
    octo_write_stable_script_shim "$plugin_root" "$stable_root" "scripts/install-deps.sh"
    octo_write_stable_script_shim "$plugin_root" "$stable_root" "scripts/helpers/check-providers.sh"
    octo_write_stable_script_shim "$plugin_root" "$stable_root" "scripts/scheduler/octopus-scheduler.sh"
    octo_write_stable_script_shim "$plugin_root" "$stable_root" "scripts/state-manager.sh"
    octo_write_stable_script_shim "$plugin_root" "$stable_root" "scripts/octo-state.sh"
    octo_write_stable_script_shim "$plugin_root" "$stable_root" "scripts/agent-registry.sh"
    octo_write_stable_script_shim "$plugin_root" "$stable_root" "scripts/reactions.sh"
    octo_write_stable_script_shim "$plugin_root" "$stable_root" "scripts/migrate-todos.sh"
    octo_write_stable_script_shim "$plugin_root" "$stable_root" "scripts/claude-mem-bridge.sh"

    [[ -x "$stable_root/scripts/orchestrate.sh" ]]
}
