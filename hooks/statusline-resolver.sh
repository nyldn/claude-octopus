#!/usr/bin/env bash
# Claude Octopus Statusline Resolver — version-agnostic launcher
# ═══════════════════════════════════════════════════════════════════════════════
# Installed to ~/.claude-octopus/statusline.sh by the plugin.
# settings.json points here so the statusline survives plugin updates.
# Finds the latest cached plugin version and delegates to octopus-statusline.sh.

CACHE_BASE="$HOME/.claude/plugins/cache/nyldn-plugins/octo"
LATEST=$(ls "$CACHE_BASE" 2>/dev/null | sort -V | tail -1)
[[ -z "$LATEST" ]] && exit 0
exec bash "$CACHE_BASE/$LATEST/hooks/octopus-statusline.sh"
