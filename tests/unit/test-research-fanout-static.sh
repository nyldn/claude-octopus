#!/usr/bin/env bash
# Static coverage for research fanout and synthesis safeguards.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Research fanout safeguards"

test_case "research command supports breadth routing"
research_cmd="$(<"$PROJECT_ROOT/.claude/commands/research.md")"
if [[ "$research_cmd" == *"--breadth=light|standard|exhaustive"* && "$research_cmd" == *"[breadth=exhaustive]"* ]]; then
    test_pass
else
    test_fail "expected breadth parsing in research command"
fi

test_case "discover skill requires dynamic multi-provider fleet"
discover_skill="$(<"$(resolve_claude_skill_path "flow-discover")")"
if [[ "$discover_skill" == *"build-fleet.sh"* && "$discover_skill" == *"Codex, Gemini, Copilot, Qwen, OpenCode"* ]]; then
    test_pass
else
    test_fail "expected dynamic provider fleet instructions"
fi

test_case "discover skill surfaces agent summary before synthesis"
if [[ "$discover_skill" == *"orchestrate.sh\" agent-summary"* && "$discover_skill" == *"Failed provider output"* ]]; then
    test_pass
else
    test_fail "expected agent-summary gate before synthesis"
fi

test_summary
