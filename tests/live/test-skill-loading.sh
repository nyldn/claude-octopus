#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "$SCRIPT_DIR/../helpers/live-test-harness.sh"

echo -e "${BLUE}Skill Loading Live Tests${NC}"
echo -e "Testing that skills load efficiently without loops"
echo ""

live_test "Debate skill - single load" \
    "octo debate tabs vs spaces. Give one sentence per side and stop." \
    --timeout 60 \
    --max-skill-loads 2 \
    --expect "tab\|space\|indent" \
    --workdir "$PROJECT_ROOT"

live_test "Research skill - single load" \
    "octo research what is markdown. One paragraph only." \
    --timeout 60 \
    --max-skill-loads 2 \
    --expect "Markdown\|markdown\|format" \
    --workdir "$PROJECT_ROOT"

live_test_summary
