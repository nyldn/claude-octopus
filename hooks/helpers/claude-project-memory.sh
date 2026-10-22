#!/usr/bin/env bash
# Resolve only the current project's existing Claude auto-memory directory.
octo_claude_project_memory_dir() {
    local project="${CLAUDE_PROJECT_DIR:-$PWD}"
    local config_root="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
    local encoded memory_dir
    [[ "$project" == /* ]] || return 1
    [[ "$project" == / ]] || project="${project%/}"
    encoded="${project//[^a-zA-Z0-9]/-}"
    memory_dir="$config_root/projects/$encoded/memory"
    [[ -d "$memory_dir" ]] || return 1
    printf '%s\n' "$memory_dir"
}
