#!/bin/bash
# Install git hooks for claude-octopus development

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
HOOKS_DIR="$REPO_DIR/hooks"
GIT_HOOKS_DIR="$REPO_DIR/.git/hooks"

echo "🐙 Installing Claude Octopus git hooks..."

# Ensure hooks directory exists
mkdir -p "$GIT_HOOKS_DIR"

# Install pre-push hook
if [[ -f "$HOOKS_DIR/pre-push" ]]; then
    ln -sf "../../hooks/pre-push" "$GIT_HOOKS_DIR/pre-push"
    echo "✓ Installed pre-push hook"
fi

echo "✓ Git hooks installed successfully"
echo ""
echo "Hooks will check:"
echo "  - Version consistency (plugin.json ↔ README.md)"
echo "  - CHANGELOG entries for current version"
echo "  - Git tag existence"
