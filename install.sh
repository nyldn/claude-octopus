#!/bin/bash
# Claude Octopus One-Line Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/nyldn/claude-octopus/main/install.sh | bash

set -euo pipefail

echo "🐙 Installing Claude Octopus..."

# Clone to plugins directory
PLUGIN_DIR="$HOME/.claude/plugins/claude-octopus"

if [ -d "$PLUGIN_DIR" ]; then
    echo "📦 Updating existing installation..."
    cd "$PLUGIN_DIR"
    git pull
else
    echo "📦 Installing to $PLUGIN_DIR..."
    git clone https://github.com/nyldn/claude-octopus.git "$PLUGIN_DIR"
fi

echo ""
echo "✅ Installation complete!"
echo ""
echo "Next steps:"
echo "1. Restart Claude Code"
echo "2. Run: /claude-octopus:setup"
echo ""
