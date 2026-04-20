#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

source "$PROJECT_ROOT/tests/helpers/test-framework.sh"
test_suite "Native First Docs"


grep -qi 'Claude-native first' "$PROJECT_ROOT/README.md"
grep -qi 'Octopus for escalation' "$PROJECT_ROOT/README.md"
grep -qi 'Claude-native.*/review' "$PROJECT_ROOT/.claude-plugin/README.md"
grep -qi 'Claude-native.*/security-review' "$PROJECT_ROOT/.claude-plugin/README.md"
grep -qi 'enhanced multi-LLM review' "$PROJECT_ROOT/docs/COMMAND-REFERENCE.md"
grep -qi 'enhanced multi-LLM or adversarial security audit' "$PROJECT_ROOT/docs/COMMAND-REFERENCE.md"

echo "PASS: native-first escalation docs are present"
test_summary
