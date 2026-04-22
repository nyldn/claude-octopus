#!/bin/bash
# Claude Octopus Statusline Auto-Repair
# ═══════════════════════════════════════════════════════════════════════════════
# SessionStart hook: ensures ~/.claude-octopus/statusline.sh exists and
# settings.json points to it instead of a versioned cache path that goes stale.

set -euo pipefail
# EXIT trap — emits diagnostic stderr ONLY when the hook exits non-zero, so
# the Claude Code harness error "No stderr output" can never recur. EXIT (not
# ERR) avoids over-firing on intermediate `grep -o`/`cmd | ...` inside $() that
# the hook's logic already handles. See issue #313.
_octo_hook_exit() { local c=$?; if [[ $c -ne 0 ]]; then echo "[hook:$(basename "$0")] exit $c" >&2 2>/dev/null || true; fi; return 0; }
trap _octo_hook_exit EXIT


RESOLVER_SRC="${CLAUDE_PLUGIN_ROOT}/hooks/statusline-resolver.sh"
RESOLVER_DST="$HOME/.claude-octopus/statusline.sh"
SETTINGS="$HOME/.claude/settings.json"
STABLE_CMD="bash ~/.claude-octopus/statusline.sh"

# ── Step 1: Install/update the resolver if missing or outdated ────────────────
if [[ -f "$RESOLVER_SRC" ]]; then
    needs_update=false
    if [[ ! -f "$RESOLVER_DST" ]]; then
        needs_update=true
    elif ! diff -q "$RESOLVER_SRC" "$RESOLVER_DST" &>/dev/null; then
        needs_update=true
    fi
    if [[ "$needs_update" == "true" ]]; then
        mkdir -p "$(dirname "$RESOLVER_DST")"
        cp "$RESOLVER_SRC" "$RESOLVER_DST"
        chmod +x "$RESOLVER_DST"
    fi
fi

# ── Step 2: Fix settings.json if statusline points to a versioned cache path ──
if [[ -f "$SETTINGS" ]] && command -v grep &>/dev/null; then
    # Match: plugins/cache/nyldn-plugins/octo/<version>/hooks/octopus-statusline.sh
    if grep -q 'plugins/cache/nyldn-plugins/octo/[0-9]' "$SETTINGS" 2>/dev/null; then
        # Only fix if the resolver is installed
        if [[ -f "$RESOLVER_DST" ]]; then
            # Use a temp file for atomic replacement
            tmp="${SETTINGS}.octotmp.$$"
            if sed "s|bash.*plugins/cache/nyldn-plugins/octo/[0-9][^\"]*|${STABLE_CMD}|g" \
                "$SETTINGS" > "$tmp" 2>/dev/null; then
                mv "$tmp" "$SETTINGS"
            else
                rm -f "$tmp"
            fi
        fi
    fi
fi

echo '{"decision": "continue"}'
exit 0
