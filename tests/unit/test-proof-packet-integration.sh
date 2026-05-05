#!/usr/bin/env bash
# Static integration checks for proof-packet wiring.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ORCH="$PROJECT_ROOT/scripts/orchestrate.sh"
REVIEW_LIB="$PROJECT_ROOT/scripts/lib/review.sh"
PROOF_LIB="$PROJECT_ROOT/scripts/lib/proof-packet.sh"
CLAUDE_CMD="$PROJECT_ROOT/.claude/commands/review.md"
CODEX_CMD="$PROJECT_ROOT/commands/octo-review.md"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "proof packet integration"

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

test_case "proof-packet.sh has valid bash syntax"
if [[ -f "$PROOF_LIB" ]] && bash -n "$PROOF_LIB" 2>/dev/null; then
    test_pass
else
    test_fail "missing or invalid $PROOF_LIB"
fi

assert_file_has "$ORCH" 'lib/proof-packet\.sh' \
    "orchestrate.sh sources proof packet module"

assert_file_has "$REVIEW_LIB" 'octo_proof_init' \
    "review_run initializes a proof packet"

assert_file_has "$REVIEW_LIB" 'octo_proof_artifact' \
    "review_run records findings artifacts"

assert_file_has "$REVIEW_LIB" 'octo_proof_capture_provider_status' \
    "review_run captures provider status"

assert_file_has "$REVIEW_LIB" 'octo_proof_finalize' \
    "review_run finalizes the proof packet"

assert_file_has "$CLAUDE_CMD" '~/.claude-octopus/runs' \
    "Claude slash command documents proof packet location"

assert_file_has "$CLAUDE_CMD" 'OCTOPUS_PROOF_PACKET=0' \
    "Claude slash command documents proof packet opt-out"

assert_file_has "$CODEX_CMD" 'proof packet' \
    "Codex command mirrors proof packet behavior"

test_summary
