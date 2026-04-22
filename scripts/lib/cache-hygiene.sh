#!/usr/bin/env bash
# cache-hygiene.sh — detect and clean stale octo plugin cache versions.
# All functions are read-only by default; cleanup is opt-in via octo_cache_clean.
#
# Layout: ~/.claude/plugins/cache/nyldn-plugins/octo/<version>/
#
# Keep policy: current + 1 previous (for rollback safety). Override via
# OCTOPUS_CACHE_KEEP=N (must be >=1).

OCTO_CACHE_DIR="${HOME}/.claude/plugins/cache/nyldn-plugins/octo"

# Versions on disk, sorted oldest → newest.
octo_cache_versions() {
    [[ -d "$OCTO_CACHE_DIR" ]] || return 0
    # -V handles semver; tolerate macOS sort which lacks -V on older systems
    if sort -V </dev/null >/dev/null 2>&1; then
        ls -1 "$OCTO_CACHE_DIR" 2>/dev/null | sort -V
    else
        ls -1 "$OCTO_CACHE_DIR" 2>/dev/null | sort
    fi
}

# Active version, derived from CLAUDE_PLUGIN_ROOT (set by CC at hook time).
# Returns empty when not running inside a hook context.
octo_cache_active_version() {
    [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]] || return 0
    case "$CLAUDE_PLUGIN_ROOT" in
        */cache/nyldn-plugins/octo/*) basename "$CLAUDE_PLUGIN_ROOT" ;;
    esac
}

# Versions safe to delete (everything except the last $keep).
# Defaults to keeping current + 1 previous.
octo_cache_stale() {
    local keep="${OCTOPUS_CACHE_KEEP:-2}"
    [[ "$keep" =~ ^[1-9][0-9]*$ ]] || keep=2
    local total
    total=$(octo_cache_versions | wc -l | tr -d ' ')
    [[ "$total" -le "$keep" ]] && return 0
    local drop=$((total - keep))
    octo_cache_versions | head -n "$drop"
}

# Total bytes used by stale versions (for user-facing reports).
octo_cache_stale_bytes() {
    local v size=0 path
    while IFS= read -r v; do
        [[ -z "$v" ]] && continue
        path="${OCTO_CACHE_DIR}/${v}"
        [[ -d "$path" ]] || continue
        # du -sk: 1024-byte blocks, portable across macOS/Linux
        local kb
        kb=$(du -sk "$path" 2>/dev/null | awk '{print $1}')
        [[ -n "$kb" ]] && size=$((size + kb * 1024))
    done < <(octo_cache_stale)
    printf '%s' "$size"
}

# Human-readable size formatter (KB/MB/GB).
octo_cache_format_bytes() {
    local b="${1:-0}"
    if [[ "$b" -ge 1073741824 ]]; then
        printf '%.1fGB' "$(echo "scale=1; $b/1073741824" | bc 2>/dev/null || echo "$b")"
    elif [[ "$b" -ge 1048576 ]]; then
        printf '%.1fMB' "$(echo "scale=1; $b/1048576" | bc 2>/dev/null || echo "$b")"
    elif [[ "$b" -ge 1024 ]]; then
        printf '%.1fKB' "$(echo "scale=1; $b/1024" | bc 2>/dev/null || echo "$b")"
    else
        printf '%dB' "$b"
    fi
}

# Delete stale versions. Skips the active version even if older than the keep
# window (defensive — should never happen, but cheap insurance).
# Outputs one line per deletion. Non-zero exit only on filesystem error.
octo_cache_clean() {
    local active stale_versions deleted=0
    active=$(octo_cache_active_version)
    while IFS= read -r v; do
        [[ -z "$v" ]] && continue
        if [[ -n "$active" && "$v" == "$active" ]]; then
            continue
        fi
        local path="${OCTO_CACHE_DIR}/${v}"
        [[ -d "$path" ]] || continue
        if rm -rf "$path" 2>/dev/null; then
            echo "removed: $v"
            deleted=$((deleted + 1))
        else
            echo "failed: $v" >&2
        fi
    done < <(octo_cache_stale)
    [[ "$deleted" -gt 0 ]] || echo "no stale versions to remove"
}

# Direct CLI: list | stale | clean | size
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-list}" in
        list)  octo_cache_versions ;;
        stale) octo_cache_stale ;;
        size)  octo_cache_format_bytes "$(octo_cache_stale_bytes)" ;;
        clean) octo_cache_clean ;;
        *) echo "Usage: $0 {list|stale|size|clean}" >&2; exit 1 ;;
    esac
fi
