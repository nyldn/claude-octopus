#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "$SCRIPT_DIR/../helpers/live-test-harness.sh"

echo -e "${BLUE}PRD Skill Live Tests${NC}"
echo -e "Testing that PRD skill loads once and executes without looping"
echo ""

live_test "PRD natural language - no excessive skill loading" \
    "octo design a simple PRD for a hello world CLI tool. Just output the executive summary section, nothing more." \
    --timeout 90 \
    --max-skill-loads 2 \
    --expect "Executive Summary\|Summary\|Hello World" \
    --workdir "$PROJECT_ROOT"

live_test "PRD command - direct execution" \
    "/octo:prd hello world CLI tool. Just output the executive summary, nothing more." \
    --timeout 90 \
    --max-skill-loads 2 \
    --expect "Executive Summary\|Summary\|Hello World" \
    --workdir "$PROJECT_ROOT"

live_test_summary
