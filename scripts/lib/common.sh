#!/usr/bin/env bash
# Common utility functions for Claude Octopus scripts
# Provides standardized output helpers for consistent terminal UX.

# ── Standard Box Width ───────────────────────────────────────────────────────
# All box-drawing output uses 60 chars for visual consistency.
OCTOPUS_BOX_WIDTH=60

# ── Output Helpers ───────────────────────────────────────────────────────────
# Use these instead of ad-hoc echo with box-drawing characters.

# Show a prominent header box: ╔═══╗ style
# Usage: octopus_header "Title text" [color_var]
octopus_header() {
    local title="$1"
    local color="${2:-${CYAN:-}}"
    local nc="${NC:-\033[0m}"
    local line
    line=$(printf '═%.0s' $(seq 1 $OCTOPUS_BOX_WIDTH))
    echo -e "${color}╔${line}╗${nc}"
    printf -v padded "%-${OCTOPUS_BOX_WIDTH}s" "  🐙 ${title}"
    echo -e "${color}║${nc}${padded}${color}║${nc}"
    echo -e "${color}╚${line}╝${nc}"
}

# Show a section separator: ━━━ style
# Usage: octopus_separator [color_var]
octopus_separator() {
    local color="${1:-${MAGENTA:-}}"
    local nc="${NC:-\033[0m}"
    local line
    line=$(printf '━%.0s' $(seq 1 $OCTOPUS_BOX_WIDTH))
    echo -e "${color}${line}${nc}"
}

# Show a workflow phase banner (two-line separator + title)
# Usage: octopus_phase_banner "Phase Title" "Description" [color_var]
octopus_phase_banner() {
    local title="$1"
    local desc="$2"
    local color="${3:-${MAGENTA:-}}"
    local nc="${NC:-\033[0m}"
    local line
    line=$(printf '═%.0s' $(seq 1 $OCTOPUS_BOX_WIDTH))
    echo -e "${color}${line}${nc}"
    echo -e "  ${color}${title}${nc}: ${desc}"
    echo -e "${color}${line}${nc}"
}

# Show a completion message with consistent format
# Usage: octopus_complete "Workflow name"
octopus_complete() {
    local workflow="$1"
    local green="${GREEN:-\033[32m}"
    local nc="${NC:-\033[0m}"
    echo -e "${green}✓ ${workflow} complete${nc}"
}

octopus_plugin_version() {
    local root="${1:-${PLUGIN_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}}"
    local manifest="$root/.claude-plugin/plugin.json"
    if [[ ! -r "$manifest" ]]; then
        echo "0.0.0-dev"
        return
    fi
    if command -v jq >/dev/null 2>&1; then
        jq -r '.version // "0.0.0-dev"' "$manifest" 2>/dev/null || echo "0.0.0-dev"
    else
        sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest" \
            | head -1 | grep . || echo "0.0.0-dev"
    fi
}

