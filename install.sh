#!/bin/bash
# Claude Octopus One-Line Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/nyldn/claude-octopus/main/install.sh | bash

set -euo pipefail

echo "🐙 Installing Claude Octopus..."

# Configuration
PLUGIN_DIR="$HOME/.claude/plugins/claude-octopus"
INSTALLED_PLUGINS="$HOME/.claude/plugins/installed_plugins.json"
CACHE_DIR="$HOME/.claude/plugins/cache"

# Check for jq
if ! command -v jq &>/dev/null; then
    echo "❌ Error: jq is required but not installed."
    echo "   Install it with: brew install jq (macOS) or apt-get install jq (Linux)"
    exit 1
fi

# Clean up old installations (from previous versions)
echo "🧹 Cleaning up old installations..."
rm -rf "$CACHE_DIR/nyldn-plugins/claude-octopus" 2>/dev/null || true
rm -rf "$CACHE_DIR/parallel-agents-global/parallel-agents" 2>/dev/null || true
echo "✓ Removed old cache"

# 1. Clone/update the plugin
echo "📦 Installing plugin files..."
if [ -d "$PLUGIN_DIR/.git" ]; then
    cd "$PLUGIN_DIR"
    git pull --quiet
    echo "✓ Updated existing installation"
else
    rm -rf "$PLUGIN_DIR"
    git clone --quiet https://github.com/nyldn/claude-octopus.git "$PLUGIN_DIR"
    echo "✓ Cloned repository"
fi

# 2. Register in installed_plugins.json as a local plugin
echo "📝 Registering with Claude Code..."
mkdir -p "$(dirname "$INSTALLED_PLUGINS")"

# Get current git commit
VERSION=$(cd "$PLUGIN_DIR" && git rev-parse --short HEAD 2>/dev/null || echo "local")
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

# Initialize or update installed_plugins.json
if [ ! -f "$INSTALLED_PLUGINS" ]; then
    echo '{"version": 2, "plugins": {}}' > "$INSTALLED_PLUGINS"
fi

# Remove old entries first
TMP_FILE=$(mktemp)
jq 'del(.plugins["claude-octopus@nyldn-plugins"]) | del(.plugins["parallel-agents@parallel-agents-global"])' "$INSTALLED_PLUGINS" > "$TMP_FILE"
mv "$TMP_FILE" "$INSTALLED_PLUGINS"

# Add/update the plugin entry as a local installation
TMP_FILE=$(mktemp)
jq --arg path "$PLUGIN_DIR" \
   --arg version "$VERSION" \
   --arg timestamp "$TIMESTAMP" \
   '.plugins["claude-octopus"] = [{
     "scope": "user",
     "installPath": $path,
     "version": $version,
     "installedAt": $timestamp,
     "lastUpdated": $timestamp,
     "source": "local"
   }]' "$INSTALLED_PLUGINS" > "$TMP_FILE"

mv "$TMP_FILE" "$INSTALLED_PLUGINS"
echo "✓ Registered as local plugin"

echo ""
echo "✅ Installation complete!"
echo ""
echo "📋 Installation details:"
echo "   Location: $PLUGIN_DIR"
echo "   Version:  $VERSION"
echo ""
echo "Next steps:"
echo "1. Restart Claude Code completely (Cmd+Q then reopen)"
echo "2. Run: /claude-octopus:setup"
echo ""
echo "Troubleshooting:"
echo "- If commands don't appear, check: ~/.claude/debug/*.txt"
echo "- Verify installation: ls -la $PLUGIN_DIR/.claude/"
echo ""
