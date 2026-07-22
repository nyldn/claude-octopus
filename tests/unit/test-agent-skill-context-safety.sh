#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/.claude/skills/host-only" "$TEST_ROOT/.claude/skills/domain-only"

cat > "$TEST_ROOT/.claude/skills/host-only/SKILL.md" <<'EOF'
---
name: host-only
execution_mode: enforced
validation_gates:
  - orchestrate_sh_executed
---
You MUST execute orchestrate.sh spawn and launch another provider.
EOF

cat > "$TEST_ROOT/.claude/skills/domain-only/SKILL.md" <<'EOF'
---
name: domain-only
---
Inspect boundary handling and report concrete findings.
EOF

PLUGIN_DIR="$TEST_ROOT"
source "$ROOT_DIR/scripts/lib/agents.sh"
get_agent_skills() { echo "host-only,domain-only"; }

context="$(build_skill_context reviewer)"
if [[ "$context" == *"orchestrate.sh"* || "$context" == *"launch another provider"* ]]; then
    echo "FAIL: host orchestration skill leaked into a provider prompt" >&2
    exit 1
fi
if [[ "$context" != *"Inspect boundary handling"* ]]; then
    echo "FAIL: safe domain skill was removed with host-only skill" >&2
    exit 1
fi

echo "PASS: provider skill context excludes host-only orchestration contracts"
