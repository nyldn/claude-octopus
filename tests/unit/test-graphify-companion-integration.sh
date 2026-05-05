#!/usr/bin/env bash
# Static integration checks for optional Graphify companion wiring.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ORCH="$PROJECT_ROOT/scripts/orchestrate.sh"
REVIEW_LIB="$PROJECT_ROOT/scripts/lib/review.sh"
DOCTOR_LIB="$PROJECT_ROOT/scripts/lib/doctor.sh"
GRAPHIFY_LIB="$PROJECT_ROOT/scripts/lib/graphify.sh"
CLAUDE_SETUP="$PROJECT_ROOT/.claude/commands/setup.md"
CODEX_SETUP="$PROJECT_ROOT/commands/octo-setup.md"
CLAUDE_REVIEW="$PROJECT_ROOT/.claude/commands/review.md"
CODEX_REVIEW="$PROJECT_ROOT/commands/octo-review.md"
CHANGELOG="$PROJECT_ROOT/CHANGELOG.md"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Graphify companion integration"

assert_file_has() {
    local file="$1"
    local pattern="$2"
    local label="$3"
    test_case "$label"
    if grep -qE "$pattern" "$file"; then
        test_pass
    else
        test_fail "pattern not found in $(basename "$file"): $pattern"
    fi
}

assert_file_lacks() {
    local file="$1"
    local pattern="$2"
    local label="$3"
    test_case "$label"
    if grep -qE "$pattern" "$file"; then
        test_fail "unexpected pattern found in $(basename "$file"): $pattern"
    else
        test_pass
    fi
}

test_case "graphify.sh has valid bash syntax"
if [[ -f "$GRAPHIFY_LIB" ]] && bash -n "$GRAPHIFY_LIB" 2>/dev/null; then
    test_pass
else
    test_fail "missing or invalid $GRAPHIFY_LIB"
fi

assert_file_has "$ORCH" 'lib/graphify\.sh' \
    "orchestrate.sh sources Graphify companion module"

assert_file_has "$REVIEW_LIB" 'octo_graphify_context_for_prompt' \
    "review_run reads Graphify companion context"

assert_file_has "$REVIEW_LIB" 'Graphify companion context' \
    "review prompt labels Graphify context"

assert_file_lacks "$REVIEW_LIB" 'graphify extract' \
    "review_run does not auto-build Graphify graphs"

assert_file_has "$DOCTOR_LIB" 'doctor_check_companions' \
    "doctor has companion category"

assert_file_has "$DOCTOR_LIB" 'graphify-cli' \
    "doctor checks Graphify CLI"

assert_file_has "$DOCTOR_LIB" 'graphify-graph' \
    "doctor checks existing Graphify graph"

assert_file_has "$DOCTOR_LIB" 'graphify-freshness' \
    "doctor checks Graphify freshness"

assert_file_has "$CLAUDE_SETUP" 'graphify' \
    "Claude setup detects Graphify"

assert_file_has "$CODEX_SETUP" 'graphify' \
    "Codex setup detects Graphify"

assert_file_has "$CLAUDE_REVIEW" 'Graphify' \
    "Claude review documents Graphify companion"

assert_file_has "$CODEX_REVIEW" 'Graphify' \
    "Codex review documents Graphify companion"

assert_file_has "$CHANGELOG" 'Graphify' \
    "changelog notes Graphify companion"

test_summary
