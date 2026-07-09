#!/usr/bin/env bash
# Static assertions for agentmemory companion compatibility.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "agentmemory companion integration"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

BRIDGE="$PROJECT_ROOT/scripts/agentmemory-bridge.sh"
MEMORY_LIB="$PROJECT_ROOT/scripts/lib/memory.sh"
DOCTOR="$PROJECT_ROOT/scripts/lib/doctor.sh"
SETUP="$PROJECT_ROOT/.claude/commands/setup.md"
CURSOR_SETUP="$PROJECT_ROOT/.cursor-plugin/commands/octo-setup.md"
README="$PROJECT_ROOT/README.md"

if [[ -x "$BRIDGE" ]]; then
    pass "agentmemory bridge exists and is executable"
else
    fail "agentmemory bridge exists and is executable" "missing or not executable"
fi

for cmd in available search observe context; do
    if grep -q "${cmd})" "$BRIDGE"; then
        pass "agentmemory bridge subcommand: $cmd"
    else
        fail "agentmemory bridge subcommand: $cmd" "case dispatch missing for $cmd"
    fi
done

if grep -q '@agentmemory/mcp' "$MEMORY_LIB" && grep -q 'agentmemory-bridge.sh' "$MEMORY_LIB"; then
    pass "memory contract detects and invokes agentmemory"
else
    fail "memory contract detects and invokes agentmemory" "missing detection or bridge invocation"
fi

if grep -q 'companion-agentmemory' "$DOCTOR"; then
    pass "doctor reports agentmemory companion"
else
    fail "doctor reports agentmemory companion" "no companion-agentmemory doctor check"
fi

for file in "$SETUP" "$CURSOR_SETUP"; do
    if grep -q 'agentmemory connect' "$file" && grep -q 'OCTOPUS_MEMORY_BACKEND=agentmemory' "$file"; then
        pass "setup docs include agentmemory path: $(basename "$file")"
    else
        fail "setup docs include agentmemory path: $(basename "$file")" "missing agentmemory setup guidance"
    fi
done

if grep -q 'github.com/rohitg00/agentmemory' "$README"; then
    pass "README mentions agentmemory"
else
    fail "README mentions agentmemory" "missing README mention"
fi

test_summary
