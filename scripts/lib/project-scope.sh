#!/usr/bin/env bash
# lib/project-scope.sh — the directory a run's learned state belongs to.
#
# Heuristic patterns and provider history are learned from one project's runs
# and injected into later prompts. They are stored under ~/.claude-octopus, so
# without a scope one worktree's paths reached another's prompts (sail-cruisey
# #3244's codex prompt carried #2867's review-prompt path). Each run's state is
# keyed to the git worktree root of its project directory (PROJECT_ROOT, set
# from --dir / OCTOPUS_PROJECT_DIR), or that directory when it is not in git.

[[ -n "${_OCTOPUS_PROJECT_SCOPE_LOADED:-}" ]] && return 0
_OCTOPUS_PROJECT_SCOPE_LOADED=true

octo_project_scope_root() {
    local dir="${PROJECT_ROOT:-${OCTOPUS_PROJECT_DIR:-$PWD}}" top
    dir="$(cd "$dir" 2>/dev/null && pwd -P)" || return 1
    if top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" && [[ -n "$top" ]]; then
        dir="$(cd "$top" 2>/dev/null && pwd -P)" || return 1
    fi
    printf '%s\n' "$dir"
}

# A short, filesystem-safe key for the scope root.
octo_project_scope_key() {
    local root digest
    root="$(octo_project_scope_root)" || return 1
    digest="$(printf '%s' "$root" | { shasum -a 256 2>/dev/null || sha256sum 2>/dev/null; } | cut -c1-16)"
    [[ "$digest" =~ ^[0-9a-f]{16}$ ]] || return 1
    printf '%s\n' "$digest"
}

# A relative path that stays inside the scope root and exists there. Learned
# paths that are absolute, climb out with "..", name a file this project does
# not have, or reach outside through a symlink (the final component, or a
# symlinked directory on the way) are never recorded or shown. The root is the
# physical path from octo_project_scope_root.
octo_project_scope_has_path() {
    local root="$1" path="$2" full parent
    [[ -n "$root" && -n "$path" ]] || return 1
    case "$path" in
        /*|~*) return 1 ;;
    esac
    case "/$path/" in
        */../*) return 1 ;;
    esac
    full="$root/$path"
    [[ -e "$full" && ! -L "$full" ]] || return 1
    parent="$(cd "$(dirname "$full")" 2>/dev/null && pwd -P)" || return 1
    case "$parent/" in
        "$root"/*) return 0 ;;
    esac
    return 1
}
