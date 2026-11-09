#!/usr/bin/env bash
# v11.19.0 metadata framing, retained as an independent stat-based reference.
_octo_capture_file_signature() {
    local path="$1"
    [[ -e "$path" ]] || { printf '%s\n' missing; return 0; }
    if stat -f '%z:%m' "$path" >/dev/null 2>&1; then
        stat -f '%z:%m' "$path"
    elif stat -c '%s:%Y' "$path" >/dev/null 2>&1; then
        stat -c '%s:%Y' "$path"
    else
        printf '%s:%s\n' "$(wc -c < "$path" 2>/dev/null || echo 0)" unknown
    fi
}

_octo_capture_worktree_fingerprint() {
    local worktree="${1:-}"
    [[ -n "$worktree" && -d "$worktree" ]] || { printf '%s\n' none; return 0; }
    command -v git >/dev/null 2>&1 || { printf '%s\n' none; return 0; }

    # Hash status plus size/mtime metadata for every changed or untracked file.
    # This notices continued writes to an already-modified path without hashing
    # entire file contents or large binary diffs on every poll.
    _octo_capture_worktree_state() {
        git -C "$worktree" status --porcelain -uall 2>/dev/null | \
            sed -E '/^.. \.octo(\/|$)/d' || true
        {
            git -C "$worktree" diff --name-only -z 2>/dev/null || true
            git -C "$worktree" diff --cached --name-only -z 2>/dev/null || true
            git -C "$worktree" ls-files --others --exclude-standard -z 2>/dev/null || true
        } | while IFS= read -r -d '' rel; do
            [[ -n "$rel" ]] || continue
            case "$rel" in .octo|.octo/*) continue ;; esac
            printf 'path=%s;' "$rel"
            _octo_capture_file_signature "$worktree/$rel"
        done
    }

    if command -v sha256sum >/dev/null 2>&1; then
        _octo_capture_worktree_state | sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        _octo_capture_worktree_state | shasum -a 256 | awk '{print $1}'
    else
        printf '%s\n' unavailable
    fi
    unset -f _octo_capture_worktree_state 2>/dev/null || true
}
