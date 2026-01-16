#!/bin/bash
# Claude Octopus One-Line Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/nyldn/claude-octopus/main/install.sh | bash

set -euo pipefail

echo "🐙 Installing Claude Octopus..."

# Configuration
PLUGIN_NAME="claude-octopus"
MARKETPLACE="claude-octopus-marketplace"
CACHE_DIR="$HOME/.claude/plugins/cache/$MARKETPLACE/$PLUGIN_NAME"
INSTALLED_PLUGINS="$HOME/.claude/plugins/installed_plugins.json"

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
rm -rf "$HOME/.claude/plugins/cache/local/claude-octopus" 2>/dev/null || true

# Remove broken marketplace entries
if [ -f "$HOME/.claude/plugins/known_marketplaces.json" ]; then
    TMP_FILE=$(mktemp)
    jq 'del(.local)' "$HOME/.claude/plugins/known_marketplaces.json" > "$TMP_FILE" 2>/dev/null || echo "{}" > "$TMP_FILE"
    mv "$TMP_FILE" "$HOME/.claude/plugins/known_marketplaces.json"
fi
echo "✓ Removed old installations"

# Clone plugin to cache location (following Claude Code's pattern)
echo "📦 Installing plugin files..."
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

git clone --quiet https://github.com/nyldn/claude-octopus.git "$TEMP_DIR/$PLUGIN_NAME"
VERSION=$(cd "$TEMP_DIR/$PLUGIN_NAME" && git rev-parse --short HEAD)

INSTALL_PATH="$CACHE_DIR/$VERSION"
mkdir -p "$(dirname "$INSTALL_PATH")"
rm -rf "$INSTALL_PATH"
cp -r "$TEMP_DIR/$PLUGIN_NAME" "$INSTALL_PATH"
echo "✓ Installed to $INSTALL_PATH"

# Register in installed_plugins.json
echo "📝 Registering with Claude Code..."
if [ ! -f "$INSTALLED_PLUGINS" ]; then
    echo '{"version": 2, "plugins": {}}' > "$INSTALLED_PLUGINS"
fi

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

# Remove old entries
TMP_FILE=$(mktemp)
jq 'del(.plugins["claude-octopus"]) | del(.plugins["claude-octopus@nyldn-plugins"]) | del(.plugins["claude-octopus@local"]) | del(.plugins["parallel-agents@parallel-agents-global"])' "$INSTALLED_PLUGINS" > "$TMP_FILE"
mv "$TMP_FILE" "$INSTALLED_PLUGINS"

# Add new entry
TMP_FILE=$(mktemp)
jq --arg path "$INSTALL_PATH" \
   --arg version "$VERSION" \
   --arg timestamp "$TIMESTAMP" \
   --arg marketplace "$MARKETPLACE" \
   '.plugins["claude-octopus@\($marketplace)"] = [{
     "scope": "user",
     "installPath": $path,
     "version": $version,
     "installedAt": $timestamp,
     "lastUpdated": $timestamp
   }]' "$INSTALLED_PLUGINS" > "$TMP_FILE"

mv "$TMP_FILE" "$INSTALLED_PLUGINS"
echo "✓ Registered as claude-octopus@$MARKETPLACE"

echo ""
echo "✅ Installation complete!"
echo ""
echo "📋 Installation details:"
echo "   Registry:  claude-octopus@$MARKETPLACE"
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
