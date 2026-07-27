#!/usr/bin/env bash
# Single source of truth for the model-resolution cache path.
#
# Sourced library: sets no shell options (they would leak into the caller).
#
# This used to be duplicated as a literal in five places. lib/model-resolver.sh
# honoured $TMPDIR while lib/provider-routing.sh and helpers/octo-model-config.sh
# hardcoded /tmp, so on macOS (where TMPDIR is a per-user /var/folders path) the
# writer and the invalidating `rm -f` addressed different files and cache busting
# silently did nothing.

# Directory that will hold the cache file. Prefers $TMPDIR, falls back to /tmp,
# and echoes nothing when neither is writable (callers then skip file caching).
octo_model_cache_dir() {
    local dir="${TMPDIR:-/tmp}"
    if mkdir -p "$dir" 2>/dev/null && [[ -d "$dir" && -w "$dir" ]]; then
        printf '%s\n' "${dir%/}"
        return 0
    fi
    if mkdir -p /tmp 2>/dev/null && [[ -d /tmp && -w /tmp ]]; then
        printf '%s\n' "/tmp"
        return 0
    fi
    return 1
}

# Full path to the per-user, per-session model cache file. Echoes nothing and
# returns 1 when no writable temp directory is available.
octo_model_cache_file() {
    local dir
    dir="$(octo_model_cache_dir)" || return 1
    printf '%s/octo-model-cache-%s-%s.json\n' \
        "$dir" \
        "${USER:-${USERNAME:-unknown}}" \
        "${CLAUDE_CODE_SESSION:-global}"
}
