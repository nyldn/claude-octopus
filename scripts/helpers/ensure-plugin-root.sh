#!/usr/bin/env bash
# Claude Octopus — Ensure ~/.claude-octopus/plugin symlink exists
# Lightweight preflight for command files. Idempotent and safe to call
# from LLM Bash tool context where ${CLAUDE_PLUGIN_ROOT} is NOT available.
#
# After marketplace install the SessionStart hook normally creates this
# symlink, but if the hook hasn't fired yet (first command invoked before
# session start) or silently errored, this script self-heals.
#
# Exit code: 0 on success, 1 if plugin root cannot be resolved.
# See: https://github.com/nyldn/claude-octopus/issues/377

set -eo pipefail

STABLE_ROOT="${HOME}/.claude-octopus/plugin"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PLUGIN_ROOT_LIB="${SCRIPT_DIR}/../lib/plugin-root.sh"

if [[ -f "$PLUGIN_ROOT_LIB" ]]; then
    source "$PLUGIN_ROOT_LIB"
fi

# Fast path — already points to the version that invoked this helper. Merely
# checking that the old target still exists strands users on a stale cache after
# the host installs a newer version but keeps older cache directories around.
if [[ -d "$STABLE_ROOT" && -x "$STABLE_ROOT/scripts/orchestrate.sh" ]]; then
    expected_root="${CLAUDE_PLUGIN_ROOT:-}"
    [[ -n "$expected_root" ]] || expected_root="$(dirname "$(dirname "$SCRIPT_DIR")")"
    expected_physical="$(cd "$expected_root" 2>/dev/null && pwd -P || true)"
    stable_physical="$(cd "$STABLE_ROOT" 2>/dev/null && pwd -P || true)"
    if [[ -n "$expected_physical" && "$stable_physical" == "$expected_physical" ]]; then
        exit 0
    fi
fi

# --- Resolve plugin root ---
PLUGIN_ROOT=""

# Strategy 1: CLAUDE_PLUGIN_ROOT env var (set by CC in hook context)
if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" && -d "${CLAUDE_PLUGIN_ROOT}" ]]; then
    PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
fi

# Strategy 2: Relative to this script (works when script is inside the plugin tree)
if [[ -z "$PLUGIN_ROOT" ]]; then
    candidate="$(dirname "$(dirname "$SCRIPT_DIR")")"
    if [[ -f "$candidate/scripts/orchestrate.sh" ]]; then
        PLUGIN_ROOT="$candidate"
    fi
fi

# Strategy 3: Shared marketplace/cache discovery
if [[ -z "$PLUGIN_ROOT" ]] && declare -f octo_discover_plugin_root >/dev/null 2>&1; then
    PLUGIN_ROOT="$(octo_discover_plugin_root)" || true
fi

if [[ -z "$PLUGIN_ROOT" ]]; then
    echo "error: could not locate Octopus plugin root. Run /octo:setup or reinstall." >&2
    exit 1
fi

# Canonicalize to physical path to avoid self-referential symlinks (#371)
PLUGIN_ROOT="$(cd "$PLUGIN_ROOT" && pwd -P)"

# Source the full self-heal helper if available (handles Windows shims etc.)
if [[ -f "$PLUGIN_ROOT/scripts/lib/plugin-root.sh" ]]; then
    source "$PLUGIN_ROOT/scripts/lib/plugin-root.sh"
    if declare -f octo_ensure_stable_plugin_root >/dev/null 2>&1; then
        helper_output="$(octo_ensure_stable_plugin_root "$PLUGIN_ROOT" 2>&1)" && helper_status=0 || helper_status=$?
        if [[ -d "$STABLE_ROOT" && -x "$STABLE_ROOT/scripts/orchestrate.sh" ]]; then
            exit 0
        fi
        echo "warning: octo_ensure_stable_plugin_root did not create a valid stable root (exit=$helper_status): ${helper_output:-no output}" >&2
    fi
fi

# Simple fallback: create symlink directly
mkdir -p "${HOME}/.claude-octopus"

# Remove stale symlink/file if present
if [[ -L "$STABLE_ROOT" || -e "$STABLE_ROOT" ]]; then
    rm -f "$STABLE_ROOT" 2>/dev/null || true
fi

ln -sfn "$PLUGIN_ROOT" "$STABLE_ROOT" 2>/dev/null || true

# Verify
if [[ -d "$STABLE_ROOT" && -x "$STABLE_ROOT/scripts/orchestrate.sh" ]]; then
    exit 0
else
    echo "error: failed to create stable plugin root at $STABLE_ROOT" >&2
    exit 1
fi
