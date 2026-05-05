#!/usr/bin/env bash
# sync-marketplace.sh - Auto-update marketplace.json from actual plugin state
# Run on every push to keep marketplace description in sync with actual counts
#
# Usage:
#   ./scripts/sync-marketplace.sh          # Update marketplace.json
#   ./scripts/sync-marketplace.sh --check  # Check only, exit 1 if out of date

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

CHECK_ONLY=false
[[ "${1:-}" == "--check" ]] && CHECK_ONLY=true

# Count shipped plugin artifacts.
# Source of truth is .claude/skills/*.md (excludes .tmpl templates)
SKILL_COUNT=$(find "$ROOT_DIR/.claude/skills" -maxdepth 1 -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
COMMAND_COUNT=$(find "$ROOT_DIR/.claude/commands" -maxdepth 1 -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
PERSONA_COUNT=$(find "$ROOT_DIR/agents/personas" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')

# Get current version from plugin.json (source of truth)
VERSION=$(grep '"version"' "$ROOT_DIR/.claude-plugin/plugin.json" | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')

# Read current marketplace description
CURRENT_DESC=$(python3 -c "
import json, sys
m = json.load(open('$ROOT_DIR/.claude-plugin/marketplace.json'))
for p in m.get('plugins', []):
    if p.get('name') == 'octo':
        desc = p.get('description', '')
        if not desc:
            print('ERROR: octo plugin description is empty', file=sys.stderr)
            sys.exit(1)
        print(desc)
        break
else:
    print('ERROR: octo plugin entry not found', file=sys.stderr)
    sys.exit(1)
")

# Extract the feature summary (first part before counts)
# Format: "Feature summary. 32 personas, 48 commands, 52 skills. Run /octo:setup."
# We preserve the feature summary but regenerate the counts
# Strip any legacy version prefix, counts suffix, and trailing "Run /octo:setup." (we re-append it)
FEATURE_SUMMARY=$(echo "$CURRENT_DESC" | sed -E 's/^v[0-9]+\.[0-9]+\.[0-9]+ [-—] //' | sed -E 's/[.,] [0-9]+ personas,.*//' | sed -E 's/\.? *Run \/octo:setup\.?$//')

# Build expected description — version prefix derived from version field
EXPECTED_DESC="v${VERSION} - ${FEATURE_SUMMARY}. ${PERSONA_COUNT} personas, ${COMMAND_COUNT} commands, ${SKILL_COUNT} skills. Run /octo:setup."

if [[ "$CURRENT_DESC" == "$EXPECTED_DESC" ]]; then
    echo "✓ marketplace.json is up to date (${PERSONA_COUNT} personas, ${COMMAND_COUNT} commands, ${SKILL_COUNT} skills)"
    exit 0
fi

if $CHECK_ONLY; then
    echo "✗ marketplace.json is out of date"
    echo "  Current:  $CURRENT_DESC"
    echo "  Expected: $EXPECTED_DESC"
    exit 1
fi

# Update marketplace.json
python3 -c "
import json

with open('$ROOT_DIR/.claude-plugin/marketplace.json') as f:
    m = json.load(f)

for p in m.get('plugins', []):
    if p.get('name') == 'octo':
        p['description'] = '''$EXPECTED_DESC'''
        p['version'] = '$VERSION'
        break

with open('$ROOT_DIR/.claude-plugin/marketplace.json', 'w') as f:
    json.dump(m, f, indent=2)
    f.write('\n')
"

echo "✓ marketplace.json updated (${PERSONA_COUNT} personas, ${COMMAND_COUNT} commands, ${SKILL_COUNT} skills)"
