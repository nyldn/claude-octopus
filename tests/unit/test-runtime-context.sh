#!/usr/bin/env bash
# Tests for RUNTIME.md convention
# Verifies: template exists, has expected sections, doctor references it, no attribution leaks
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "RUNTIME.md convention"

TEMPLATE="$PROJECT_ROOT/config/templates/RUNTIME.md"
DOCTOR="$PROJECT_ROOT/.claude/skills/skill-doctor.md"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

# ── Template existence ───────────────────────────────────────────────────────

if [[ -f "$TEMPLATE" ]]; then
    pass "RUNTIME.md template exists in config/templates/"
else
    fail "RUNTIME.md template exists in config/templates/" "not found at $TEMPLATE"
fi

# ── Template has expected sections ───────────────────────────────────────────

if grep -q '## API Endpoints' "$TEMPLATE" 2>/dev/null; then
    pass "template has API Endpoints section"
else
    fail "template has API Endpoints section" "missing ## API Endpoints"
fi

if grep -q '## Environment Variables' "$TEMPLATE" 2>/dev/null; then
    pass "template has Environment Variables section"
else
    fail "template has Environment Variables section" "missing ## Environment Variables"
fi

if grep -q '## Test Commands' "$TEMPLATE" 2>/dev/null; then
    pass "template has Test Commands section"
else
    fail "template has Test Commands section" "missing ## Test Commands"
fi

if grep -q '## Build & Deploy' "$TEMPLATE" 2>/dev/null; then
    pass "template has Build & Deploy section"
else
    fail "template has Build & Deploy section" "missing ## Build & Deploy"
fi

if grep -q '## Project Notes' "$TEMPLATE" 2>/dev/null; then
    pass "template has Project Notes section"
else
    fail "template has Project Notes section" "missing ## Project Notes"
fi

# ── Template has instructional header ────────────────────────────────────────

if grep -q 'runtime context' "$TEMPLATE" 2>/dev/null; then
    pass "template mentions runtime context in description"
else
    fail "template mentions runtime context in description" "missing runtime context reference"
fi

# ── skill-doctor.md references RUNTIME.md ────────────────────────────────────

if grep -q 'RUNTIME.md' "$DOCTOR" 2>/dev/null; then
    pass "skill-doctor.md mentions RUNTIME.md"
else
    fail "skill-doctor.md mentions RUNTIME.md" "no RUNTIME.md reference found"
fi

if grep -q 'Runtime Context' "$DOCTOR" 2>/dev/null; then
    pass "skill-doctor.md has Runtime Context section"
else
    fail "skill-doctor.md has Runtime Context section" "missing ## Runtime Context heading"
fi

# ── No attribution references ────────────────────────────────────────────────

gsd_found=0
for check_file in "$TEMPLATE" "$DOCTOR"; do
    if grep -qi 'gsd' "$check_file" 2>/dev/null; then
        gsd_found=1
    fi
    if grep -qi '\.gsd/RUNTIME' "$check_file" 2>/dev/null; then
        gsd_found=1
    fi
done

if [[ "$gsd_found" -eq 0 ]]; then
    pass "no attribution references (gsd, .gsd/RUNTIME) in template or doctor"
else
    fail "no attribution references (gsd, .gsd/RUNTIME) in template or doctor" "found gsd reference"
fi
test_summary
