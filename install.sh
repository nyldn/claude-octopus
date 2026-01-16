#!/bin/bash
# Claude Octopus One-Line Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/nyldn/claude-octopus/main/install.sh | bash

set -euo pipefail

echo "🐙 Installing Claude Octopus..."

# Configuration
MARKETPLACE="local"
CACHE_DIR="$HOME/.claude/plugins/cache/$MARKETPLACE/claude-octopus"
MARKETPLACE_DIR="$HOME/.claude/plugins/marketplaces/$MARKETPLACE"
INSTALLED_PLUGINS="$HOME/.claude/plugins/installed_plugins.json"
KNOWN_MARKETPLACES="$HOME/.claude/plugins/known_marketplaces.json"

# Check for jq
if ! command -v jq &>/dev/null; then
    echo "❌ Error: jq is required but not installed."
    echo "   Install it with: brew install jq (macOS) or apt-get install jq (Linux)"
    exit 1
fi

# Clean up old installations (from previous versions)
echo "🧹 Cleaning up old installations..."
rm -rf "$HOME/.claude/plugins/claude-octopus" 2>/dev/null || true
rm -rf "$HOME/.claude/plugins/cache/nyldn-plugins/claude-octopus" 2>/dev/null || true
rm -rf "$HOME/.claude/plugins/cache/parallel-agents-global/parallel-agents" 2>/dev/null || true
echo "✓ Removed old cache"

# 1. Set up local marketplace
echo "📦 Setting up local marketplace..."
mkdir -p "$MARKETPLACE_DIR"
if [ ! -f "$KNOWN_MARKETPLACES" ]; then
    echo '{}' > "$KNOWN_MARKETPLACES"
fi

TMP_FILE=$(mktemp)
jq --arg path "$MARKETPLACE_DIR" --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")" \
   '.["local"] = {"source": {"source": "local"}, "installLocation": $path, "lastUpdated": $timestamp}' \
   "$KNOWN_MARKETPLACES" > "$TMP_FILE"
mv "$TMP_FILE" "$KNOWN_MARKETPLACES"
echo "✓ Registered local marketplace"

# 2. Clone plugin to cache location (following Claude Code's pattern)
echo "📦 Installing plugin files..."
# Get latest version
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

git clone --quiet https://github.com/nyldn/claude-octopus.git "$TEMP_DIR/claude-octopus"
VERSION=$(cd "$TEMP_DIR/claude-octopus" && git rev-parse --short HEAD)

INSTALL_PATH="$CACHE_DIR/$VERSION"
mkdir -p "$(dirname "$INSTALL_PATH")"
rm -rf "$INSTALL_PATH"
cp -r "$TEMP_DIR/claude-octopus" "$INSTALL_PATH"
echo "✓ Installed to cache ($VERSION)"

# 3. Register in installed_plugins.json
echo "📝 Registering with Claude Code..."
if [ ! -f "$INSTALLED_PLUGINS" ]; then
    echo '{"version": 2, "plugins": {}}' > "$INSTALLED_PLUGINS"
fi

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

# Remove old entries
TMP_FILE=$(mktemp)
jq 'del(.plugins["claude-octopus"]) | del(.plugins["claude-octopus@nyldn-plugins"]) | del(.plugins["parallel-agents@parallel-agents-global"])' "$INSTALLED_PLUGINS" > "$TMP_FILE"
mv "$TMP_FILE" "$INSTALLED_PLUGINS"

# Add new entry with @local marketplace format
TMP_FILE=$(mktemp)
jq --arg path "$INSTALL_PATH" \
   --arg version "$VERSION" \
   --arg timestamp "$TIMESTAMP" \
   '.plugins["claude-octopus@local"] = [{
     "scope": "user",
     "installPath": $path,
     "version": $version,
     "installedAt": $timestamp,
     "lastUpdated": $timestamp
   }]' "$INSTALLED_PLUGINS" > "$TMP_FILE"

mv "$TMP_FILE" "$INSTALLED_PLUGINS"
echo "✓ Registered as claude-octopus@local"

echo ""
echo "✅ Installation complete!"
echo ""
echo "📋 Installation details:"
echo "   Registry:  claude-octopus@local"
echo "   Location:  $INSTALL_PATH"
echo "   Version:   $VERSION"
echo ""
echo "Next steps:"
echo "1. Restart Claude Code completely (Cmd+Q then reopen)"
echo "2. Run: /claude-octopus:setup"
echo ""
echo "Troubleshooting:"
echo "- If commands don't appear, check: ~/.claude/debug/*.txt"
echo "- Verify installation: ls -la $INSTALL_PATH/.claude/"
echo ""
