#!/usr/bin/env bash
# Resolve only this project's readable, searchable Claude auto-memory directory.
# Writers additionally check write access; restoration also works read-only.
octo_claude_project_memory_dir() {
    local project="${CLAUDE_PROJECT_DIR:-$PWD}"
    local config_root="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
    local encoded memory_dir
    [[ "$project" == /* ]] || return 1
    [[ "$project" == / ]] || project="${project%/}"
    encoded="${project//[^a-zA-Z0-9]/-}"
    memory_dir="$config_root/projects/$encoded/memory"
    [[ -d "$memory_dir" && -r "$memory_dir" && -x "$memory_dir" ]] || return 1
    printf '%s\n' "$memory_dir"
}
