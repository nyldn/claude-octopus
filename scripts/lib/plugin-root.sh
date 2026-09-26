#!/usr/bin/env bash
# Plugin root helpers for Claude Octopus.
# Source-safe: no main execution block.

_octo_stable_script_paths() {
    printf '%s\n' scripts/orchestrate.sh scripts/install-deps.sh \
        scripts/helpers/check-providers.sh scripts/scheduler/octopus-scheduler.sh \
        scripts/state-manager.sh scripts/octo-state.sh scripts/agent-registry.sh \
        scripts/reactions.sh scripts/migrate-todos.sh scripts/claude-mem-bridge.sh
}

_octo_stable_wrapper() {
    local quoted
    printf -v quoted '%q' "$1"
    printf '#!/usr/bin/env bash\nexec %s "$@"\n' "$quoted"
}

octo_stable_shim_source() {
    local file="$1" rel="$2" first line token char decoded=""
    [[ -f "$file" && ! -L "$file" ]] || return 1
    { IFS= read -r first && IFS= read -r line; } < "$file" || return 1
    [[ "$first" == '#!/usr/bin/env bash' && "$line" == 'exec '*' "$@"' ]] || return 1
    token="${line#exec }"; token="${token% \"\$@\"}"
    # Decode only backslash-escaped path characters. Never evaluate wrapper code.
    while [[ -n "$token" ]]; do
        char="${token:0:1}"; token="${token:1}"
        if [[ "$char" == \\ ]]; then
            [[ -n "$token" ]] || return 1
            char="${token:0:1}"; token="${token:1}"
        fi
        decoded="$decoded$char"
    done
    case "$decoded" in /*/"$rel") ;; *) return 1 ;; esac
    # Byte equality rejects appended code, extra lines, and altered quoting.
    cmp -s "$file" <(_octo_stable_wrapper "$decoded") || return 1
    printf '%s\n' "$decoded"
}

_octo_stable_destination_safe() {
    local stable="$1" rel="$2" path="$1" part rest
    [[ ! -L "$stable" && ( ! -e "$stable" || -d "$stable" ) ]] || return 1
    rest="${rel%/*}"
    while [[ -n "$rest" ]]; do
        part="${rest%%/*}"
        [[ "$part" != .. && -n "$part" ]] || return 1
        path="$path/$part"
        [[ ! -L "$path" && ( ! -e "$path" || -d "$path" ) ]] || return 1
        if [[ "$rest" == */* ]]; then rest="${rest#*/}"; else rest=""; fi
    done
}

octo_stable_shims_status() {
    local root="$1" stable="$2" rel dst src target status=shim
    [[ -x "$stable/scripts/orchestrate.sh" ]] || { printf 'invalid\n'; return 1; }
    while IFS= read -r rel; do
        dst="$stable/$rel"; src="$root/$rel"
        if [[ -e "$dst" && -e "$src" && "$dst" -ef "$src" ]]; then
            [[ "$rel" != scripts/orchestrate.sh ]] || status=ok
            continue
        fi
        _octo_stable_destination_safe "$stable" "$rel" || { printf 'invalid\n'; return 1; }
        if [[ ! -e "$dst" && ! -L "$dst" ]]; then
            [[ ! -f "$src" ]] || status=mismatch
            continue
        fi
        target="$(octo_stable_shim_source "$dst" "$rel")" || { printf 'invalid\n'; return 1; }
        [[ "$target" == "$src" ]] || status=mismatch
    done < <(_octo_stable_script_paths)
    printf '%s\n' "$status"
    [[ "$status" != mismatch ]]
}

# The optional uname argument is a deterministic test seam; production callers
# intentionally omit it so the current host is detected at invocation time.
# shellcheck disable=SC2120
octo_is_windows_git_bash() {
    local uname_s="${1:-}"
    if [[ -z "$uname_s" ]]; then
        uname_s="$(uname -s 2>/dev/null || true)"
    fi

    case "$uname_s" in
        Linux*) return 1 ;;
        MINGW*|MSYS*|CYGWIN*) return 0 ;;
        Darwin*) return 1 ;;
    esac

    [[ "${OS:-}" == "Windows_NT" ]] && {
        [[ -n "${MSYSTEM:-}" ]] || [[ -n "${MINGW_PREFIX:-}" ]] ||
        [[ "${OSTYPE:-}" == msys* ]] || [[ "${OSTYPE:-}" == mingw* ]] ||
        [[ "${OSTYPE:-}" == cygwin* ]]
    }
}

octo_require_supported_workflow_host() {
    local command_name="${1:-}"
    local command_arg="${2:-}"
    octo_is_windows_git_bash || return 0
    case "$command_name" in
        ""|-h|--help|help|guide|doctor|capabilities|cache-check|check-cache|security-audit|repair|handoff|profile|install-state)
            return 0 ;;
        explain|status)
            [[ "$command_arg" == "--run" ]] && return 0 ;;
    esac
    printf '%s\n' "ERROR: Native Windows is unsupported. Run Claude Octopus inside WSL." >&2
    return 78
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
    # than stable_root itself being a single symlink), or dst is itself a
    # symlink aliasing src, writing the exec stub there corrupts the live
    # script into a self-referential exec loop. -ef compares device+inode so
    # it catches aliasing via either a symlinked parent dir or dst itself
    # being a symlink to src. See #521.
    [[ -e "$dst" && "$src" -ef "$dst" ]] && return 0

    _octo_stable_destination_safe "$stable_root" "$rel_path" || return 1
    if [[ -e "$dst" || -L "$dst" ]]; then
        octo_stable_shim_source "$dst" "$rel_path" >/dev/null || return 1
    fi
    local tmp
    mkdir -p "$(dirname "$dst")" || return 1
    tmp="$(mktemp "$(dirname "$dst")/.octo-shim.XXXXXX")" || return 1
    if ! { _octo_stable_wrapper "$src" > "$tmp" && chmod 755 "$tmp" && mv -f "$tmp" "$dst"; }; then
        rm -f "$tmp"
        return 1
    fi
    [[ -f "$dst" && -x "$dst" ]] && cmp -s "$dst" <(_octo_stable_wrapper "$src")
}

octo_discover_plugin_root() {
    # Auto-discover the Octopus plugin root from CC marketplace cache or Cowork
    # plugin cache. Returns the path on stdout, or empty string on failure.
    # Used when CLAUDE_PLUGIN_ROOT is not set (LLM Bash tool context). (#377)
    local candidate=""

    # Strategy 1: CC marketplace cache (standard install path)
    local cache_base="${HOME}/.claude/plugins/cache/nyldn-plugins/octo"
    if [[ -d "$cache_base" ]]; then
        # Preserve the existing newest-by-mtime discovery order.
        # shellcheck disable=SC2012
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

# True when a path is an installed plugin copy (a marketplace or desktop-app
# cache), not a development checkout or worktree.
octo_is_installed_plugin_root() {
    local root="${1:-}"
    [[ -n "$root" ]] || return 1
    case "$root" in
        */plugins/cache/nyldn-plugins/*) return 0 ;;
        */nyldn-plugins/octo/*) return 0 ;;
    esac
    return 1
}

# Self-heal used on every orchestrate.sh run. It repairs a missing or broken
# stable root, and follows an installed plugin (so hosts without a SessionStart
# hook still pick up upgrades), but never moves a working stable root to a
# development checkout. The stable root is machine-wide: repointing it from a
# worktree made every other live session run that worktree's unreleased code.
# Sessions that load a checkout on purpose still claim it through the
# SessionStart hook, which calls octo_ensure_stable_plugin_root directly.
octo_self_heal_stable_plugin_root() {
    local plugin_root="$1"
    local stable_root="${2:-${HOME}/.claude-octopus/plugin}"
    local current_root candidate_version current_version

    if [[ -x "$stable_root/scripts/orchestrate.sh" ]]; then
        octo_is_installed_plugin_root "$plugin_root" || return 0
        # An older installed copy still running in another session must not
        # move the link backwards from a newer install.
        current_root="$(cd "$stable_root" 2>/dev/null && pwd -P)" || current_root=""
        if octo_is_installed_plugin_root "$current_root"; then
            candidate_version="$(_octo_plugin_root_version "$plugin_root")"
            current_version="$(_octo_plugin_root_version "$current_root")"
            if [[ -n "$candidate_version" && -n "$current_version" ]] && \
               _octo_version_lt "$candidate_version" "$current_version"; then
                return 0
            fi
        fi
    fi
    octo_ensure_stable_plugin_root "$plugin_root" "$stable_root"
}

# Print the version recorded in a plugin root's package.json, or nothing.
_octo_plugin_root_version() {
    local file="${1:-}/package.json" line
    [[ -f "$file" ]] || return 0
    line="$(LC_ALL=C grep -m1 '"version"' "$file" 2>/dev/null)" || return 0
    line="${line#*\"version\"}"
    line="${line#*\"}"
    line="${line%%\"*}"
    [[ "$line" =~ ^[0-9]+(\.[0-9]+)*$ ]] && printf '%s\n' "$line"
    return 0
}

# True when dotted numeric version $1 is lower than $2. Bash 3.2 safe: compares
# each field numerically with 10# so leading zeroes are not read as octal.
_octo_version_lt() {
    local a="$1" b="$2" x y
    while [[ -n "$a" || -n "$b" ]]; do
        x="${a%%.*}"; y="${b%%.*}"
        [[ -n "$x" ]] || x=0
        [[ -n "$y" ]] || y=0
        if (( 10#$x < 10#$y )); then return 0; fi
        if (( 10#$x > 10#$y )); then return 1; fi
        if [[ "$a" == *.* ]]; then a="${a#*.}"; else a=""; fi
        if [[ "$b" == *.* ]]; then b="${b#*.}"; else b=""; fi
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

    [[ -n "$plugin_root" && -d "$plugin_root" && -f "$plugin_root/scripts/orchestrate.sh" && -x "$plugin_root/scripts/orchestrate.sh" ]] || return 1
    plugin_root="$(cd "$plugin_root" && pwd -P)" || return 1

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

    if [[ -L "$stable_root" ]]; then
        # Rename a prepared link over the old link without an unlink gap. -h on
        # BSD and -T on GNU prevent following a destination symlink to a directory.
        local staging
        staging="$(mktemp -d "$(dirname "$stable_root")/.octo-link.XXXXXX")" || return 1
        if ln -s "$plugin_root" "$staging/link" &&
            { if [[ "$(uname -s)" == Darwin || "$(uname -s)" == *BSD ]]; then
                mv -fh "$staging/link" "$stable_root"
              else mv -fT "$staging/link" "$stable_root"; fi; }; then
            rmdir "$staging"
            [[ -x "$stable_root/scripts/orchestrate.sh" ]]
            return $?
        fi
        rm -f "$staging/link"; rmdir "$staging"
        return 1
    fi
    [[ ! -e "$stable_root" || -d "$stable_root" ]] || return 1
    if [[ ! -e "$stable_root" ]] && ln -s "$plugin_root" "$stable_root" 2>/dev/null; then
        [[ -x "$stable_root/scripts/orchestrate.sh" ]]
        return $?
    fi

    # Windows Git Bash often cannot create native symlinks without Developer
    # Mode/admin rights. Keep the stable path usable by writing tiny wrappers
    # for script entry points referenced by commands and skills.
    local rel src dst
    # Preflight every destination before changing any existing wrapper.
    while IFS= read -r rel; do
        src="$plugin_root/$rel"; dst="$stable_root/$rel"
        [[ -e "$src" && -e "$dst" && "$src" -ef "$dst" ]] && continue
        _octo_stable_destination_safe "$stable_root" "$rel" || return 1
        if [[ -e "$dst" || -L "$dst" ]]; then
            octo_stable_shim_source "$dst" "$rel" >/dev/null || return 1
        fi
    done < <(_octo_stable_script_paths)
    mkdir -p "$stable_root" || return 1
    while IFS= read -r rel; do
        octo_write_stable_script_shim "$plugin_root" "$stable_root" "$rel" || return 1
    done < <(_octo_stable_script_paths)

    [[ -x "$stable_root/scripts/orchestrate.sh" ]]
}
