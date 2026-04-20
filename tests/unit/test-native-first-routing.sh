#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

source "$PROJECT_ROOT/tests/helpers/test-framework.sh"
test_suite "Native First Routing"

SKILL_FILE="$PROJECT_ROOT/.claude/skills/skill-native-escalation-routing.md"
PLUGIN_JSON="$PROJECT_ROOT/.claude-plugin/plugin.json"

grep -q '^name: skill-native-escalation-routing$' "$SKILL_FILE"
grep -q 'Claude-native first' "$SKILL_FILE"
grep -q '/review' "$SKILL_FILE"
grep -q '/security-review' "$SKILL_FILE"
grep -q '/init' "$SKILL_FILE"
grep -q 'multiple model opinions' "$SKILL_FILE"
grep -q 'skill-native-escalation-routing.md' "$PLUGIN_JSON"

echo "PASS: native-first routing skill exists and is registered"
test_summary
