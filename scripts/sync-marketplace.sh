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

log() {
    local level="$1"
    shift
    printf '[%s] %s\n' "$level" "$*" >&2
}

CHECK_ONLY=false
[[ "${1:-}" == "--check" ]] && CHECK_ONLY=true

# Count packaged plugin artifacts from the manifest users install.
PLUGIN_JSON="$ROOT_DIR/.claude-plugin/plugin.json"
SKILL_COUNT=$(python3 -c "import json; print(len(json.load(open('$PLUGIN_JSON')).get('skills', [])))")
COMMAND_COUNT=$(python3 -c "import json; print(len(json.load(open('$PLUGIN_JSON')).get('commands', [])))")
PERSONA_COUNT=$(find "$ROOT_DIR/agents/personas" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')

# Get current version from plugin.json (source of truth)
VERSION=$(python3 -c "import json; print(json.load(open('$PLUGIN_JSON')).get('version', ''))")
if [[ -z "$VERSION" ]]; then
    echo "ERROR: version missing in $PLUGIN_JSON" >&2
    exit 1
fi

# Read the current marketplace description (compared against expected below)
CURRENT_DESC=$(python3 -c "
import json, sys
m = json.load(open('$ROOT_DIR/.claude-plugin/marketplace.json'))
for p in m.get('plugins', []):
    if p.get('name') == 'octo':
        print(p.get('description', ''))
        break
else:
    print('ERROR: octo plugin entry not found', file=sys.stderr)
    sys.exit(1)
")

# Derive the feature summary from plugin.json (the source of truth), NOT from
# marketplace.json's previous description. Sourcing it from marketplace.json
# made the summary self-referential: it could only change via a hand-edit to a
# file documented as never-hand-edit, which is how the v9.50 summary survived
# into v9.51 and how a hand-written "42 agents, ..." fragment stacked with the
# generated counts. Strip: version prefix, any counts fragments (agents or
# personas variants), and the trailing "Run /octo:setup." (re-appended below).
PLUGIN_DESC=$(python3 -c "import json; print(json.load(open('$PLUGIN_JSON')).get('description', ''))")
if [[ -z "$PLUGIN_DESC" ]]; then
    log ERROR "description missing in $PLUGIN_JSON"
    exit 1
fi
FEATURE_SUMMARY=$(echo "$PLUGIN_DESC" | sed -E 's/^v[0-9]+\.[0-9]+\.[0-9]+ [-—] //' | sed -E 's/[.,] [0-9]+ (agents|personas),[^.]*\.//g' | sed -E 's/\.? *Run \/octo:setup\.?$//' | sed -E 's/\.$//')

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
