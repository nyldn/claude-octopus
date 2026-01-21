#!/usr/bin/env bash
# Pre-commit hook to validate critical plugin configuration
# This prevents breaking changes from being committed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "🔍 Pre-commit validation..."

# Validate plugin name (critical - prevents command prefix breakage)
if ! "$PROJECT_ROOT/tests/validate-plugin-name.sh"; then
    echo ""
    echo "❌ Pre-commit validation failed!"
    echo "   Plugin name must be 'octo' to maintain correct command prefixes."
    echo "   See .claude-plugin/PLUGIN_NAME_LOCK.md for details."
    exit 1
fi

echo "✅ Pre-commit validation passed"
exit 0
