#!/usr/bin/env bash
# path-runtime.sh — shared cross-platform canonicalization and containment.

[[ -n "${_OCTOPUS_PATH_RUNTIME_LOADED:-}" ]] && return 0
_OCTOPUS_PATH_RUNTIME_LOADED=1

pathrt_is_windows() {
    case "$(uname -s 2>/dev/null || true)" in
        MINGW*|MSYS*|CYGWIN*) return 0 ;;
    esac
    return 1
}

_pathrt_validate_input() {
    local path="${1:-}"
    [[ -n "$path" ]] || return 2
    [[ "$path" != *$'\n'* && "$path" != *$'\r'* ]] || return 2

    # UNC/device paths and drive-relative paths do not have an unambiguous
    # workspace meaning in the Git/MSYS runtime and are denied.
    [[ "$path" != \\\\* && "$path" != //* ]] || return 2
    if [[ "$path" =~ ^[A-Za-z]:$ || "$path" =~ ^[A-Za-z]:[^/\\] ]]; then
        return 2
    fi
    return 0
}

_pathrt_runtime_input() {
    local path="$1"
    _pathrt_validate_input "$path" || return 2

    if [[ "$path" =~ ^[A-Za-z]:[/\\] ]]; then
        pathrt_is_windows || return 2
        command -v cygpath >/dev/null 2>&1 || return 2
        cygpath -u "$path" 2>/dev/null || return 2
        return 0
    fi

    # Backslashes outside an absolute drive path are ambiguous and are not
    # silently reinterpreted as separators.
    [[ "$path" != *\\* ]] || return 2
    printf '%s\n' "$path"
}

_pathrt_format_canonical() {
    local path="$1"
    if pathrt_is_windows; then
        path=$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')
    fi
    while [[ "$path" != "/" && ! "$path" =~ ^/[a-z]$ && "$path" == */ ]]; do
        path="${path%/}"
    done
    printf '%s\n' "$path"
}

pathrt_canon_existing() {
    local input runtime_path canonical
    input="${1:-}"
    runtime_path=$(_pathrt_runtime_input "$input") || return 2
    canonical=$(realpath -e -- "$runtime_path" 2>/dev/null) || return 2
    _pathrt_format_canonical "$canonical"
}

pathrt_canon_target() {
    local input runtime_path parent base canonical_parent candidate
    input="${1:-}"
    runtime_path=$(_pathrt_runtime_input "$input") || return 2

    if [[ -e "$runtime_path" || -L "$runtime_path" ]]; then
        pathrt_canon_existing "$runtime_path"
        return $?
    fi

    while [[ "$runtime_path" != "/" && "$runtime_path" == */ ]]; do
        runtime_path="${runtime_path%/}"
    done
    parent=$(dirname -- "$runtime_path" 2>/dev/null) || return 2
    base=$(basename -- "$runtime_path" 2>/dev/null) || return 2
    [[ -n "$base" && "$base" != "." && "$base" != ".." ]] || return 2
    canonical_parent=$(pathrt_canon_existing "$parent") || return 2
    [[ -d "$canonical_parent" ]] || return 2

    if [[ "$canonical_parent" == "/" ]]; then
        candidate="/$base"
    else
        candidate="$canonical_parent/$base"
    fi
    _pathrt_format_canonical "$candidate"
}

_pathrt_within_canonical() {
    local root="$1" candidate="$2"
    if [[ "$root" == "/" ]]; then
        [[ "$candidate" == /* ]] && return 0
        return 1
    fi
    case "$candidate" in
        "$root"|"$root"/*) return 0 ;;
    esac
    return 1
}

pathrt_within_existing() {
    local root candidate
    root=$(pathrt_canon_existing "${1:-}") || return 2
    candidate=$(pathrt_canon_existing "${2:-}") || return 2
    _pathrt_within_canonical "$root" "$candidate"
}

pathrt_within_target() {
    local root candidate
    root=$(pathrt_canon_existing "${1:-}") || return 2
    candidate=$(pathrt_canon_target "${2:-}") || return 2
    _pathrt_within_canonical "$root" "$candidate"
}

# Native Windows Git cannot consume /c/... when MSYS argument conversion is
# explicitly disabled. Convert only at the execution boundary; containment
# always uses the canonical runtime form above.
pathrt_for_git() {
    local canonical
    canonical=$(pathrt_canon_existing "${1:-}") || return 2
    if pathrt_is_windows; then
        command -v cygpath >/dev/null 2>&1 || return 2
        cygpath -m "$canonical" 2>/dev/null || return 2
        return 0
    fi
    printf '%s\n' "$canonical"
}
