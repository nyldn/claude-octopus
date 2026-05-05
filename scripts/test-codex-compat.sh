#!/bin/bash
# test-codex-compat.sh - Tests for Codex CLI compatibility (Direction A)
# Run with: ./scripts/test-codex-compat.sh

set -o pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0
FAIL=0
SKIP=0

test_cmd() {
    local name="$1"
    local cmd="$2"
    local expect_exit="${3:-0}"

    echo -n "  $name... "
    output=$(bash -c "$cmd" 2>&1)
    exit_code=$?

    if [[ "$expect_exit" == "0" ]]; then
        if [[ $exit_code -eq 0 ]]; then
            echo -e "${GREEN}PASS${NC}"
            ((PASS++))
            return 0
        else
            echo -e "${RED}FAIL${NC} (exit code: $exit_code)"
            echo "    Output: ${output:0:200}"
            ((FAIL++))
            return 1
        fi
    else
        if [[ $exit_code -ne 0 ]]; then
            echo -e "${GREEN}PASS${NC} (expected failure)"
            ((PASS++))
            return 0
        else
            echo -e "${RED}FAIL${NC} (expected failure, got success)"
            ((FAIL++))
            return 1
        fi
    fi
}

test_output() {
    local name="$1"
    local cmd="$2"
    local expect_pattern="$3"

    echo -n "  $name... "
    output=$(bash -c "$cmd" 2>&1)
    exit_code=$?

    if echo "$output" | grep -qE "$expect_pattern"; then
        echo -e "${GREEN}PASS${NC}"
        ((PASS++))
        return 0
    else
        echo -e "${RED}FAIL${NC}"
        echo "    Expected pattern: $expect_pattern"
        echo "    Output: ${output:0:200}"
        ((FAIL++))
        return 1
    fi
}

echo ""
echo "========================================"
echo "  Codex Compatibility Test Suite"
echo "========================================"
echo ""

# ============================================
# 1. BUILD SCRIPT
# ============================================
echo "--- 1. Build Script (build-codex-skills.sh) ---"

test_cmd "build script syntax check" \
    "bash -n '$SCRIPT_DIR/build-codex-skills.sh'"

test_cmd "build script runs successfully" \
    "cd '$PLUGIN_ROOT' && bash scripts/build-codex-skills.sh"

test_output "build script generates 50+ skills" \
    "cd '$PLUGIN_ROOT' && bash scripts/build-codex-skills.sh" \
    "5[0-9] skills generated"

test_cmd "check mode passes after build" \
    "cd '$PLUGIN_ROOT' && bash scripts/build-codex-skills.sh --check"

# ============================================
# 2. OUTPUT STRUCTURE
# ============================================
echo ""
echo "--- 2. Output Structure (.codex/skills/) ---"

test_cmd ".codex/skills/ directory exists" \
    "test -d '$PLUGIN_ROOT/.codex/skills'"

test_output "50 skill directories created" \
    "ls -d '$PLUGIN_ROOT/.codex/skills'/*/ | wc -l | tr -d ' '" \
    "^5[0-9]$"

test_cmd "each skill dir has SKILL.md" \
    "cd '$PLUGIN_ROOT' && for d in .codex/skills/*/; do [[ -f \"\${d}SKILL.md\" ]] || exit 1; done"

# ============================================
# 3. SKILL.MD FORMAT
# ============================================
echo ""
echo "--- 3. SKILL.md Format Validation ---"

test_cmd "all SKILL.md files start with frontmatter delimiter" \
    "cd '$PLUGIN_ROOT' && for f in .codex/skills/*/SKILL.md; do head -1 \"\$f\" | grep -q '^---$' || exit 1; done"

test_cmd "all SKILL.md have name field" \
    "cd '$PLUGIN_ROOT' && for f in .codex/skills/*/SKILL.md; do head -5 \"\$f\" | grep -q '^name:' || exit 1; done"

test_cmd "all SKILL.md have description field" \
    "cd '$PLUGIN_ROOT' && for f in .codex/skills/*/SKILL.md; do head -5 \"\$f\" | grep -q '^description:' || exit 1; done"

test_cmd "all SKILL.md have host preamble" \
    "cd '$PLUGIN_ROOT' && for f in .codex/skills/*/SKILL.md; do grep -q 'Host: Codex CLI' \"\$f\" || exit 1; done"

# Name length validation (max 64 chars)
test_cmd "all skill names are 64 chars or less" \
    "cd '$PLUGIN_ROOT' && for f in .codex/skills/*/SKILL.md; do name=\$(head -5 \"\$f\" | grep '^name:' | sed 's/^name: *//'); [[ \${#name} -le 64 ]] || exit 1; done"

# Name charset validation (a-zA-Z0-9_- only)
test_cmd "all skill names use valid charset" \
    "cd '$PLUGIN_ROOT' && for f in .codex/skills/*/SKILL.md; do name=\$(head -5 \"\$f\" | grep '^name:' | sed 's/^name: *//'); echo \"\$name\" | grep -qE '^[a-zA-Z0-9_-]+$' || exit 1; done"

# Description length validation (max 1024 chars)
test_cmd "all descriptions are 1024 chars or less" \
    "cd '$PLUGIN_ROOT' && for f in .codex/skills/*/SKILL.md; do desc=\$(head -5 \"\$f\" | grep '^description:' | sed 's/^description: *\"\\{0,1\\}//;s/\"\\{0,1\\}$//'); [[ \${#desc} -le 1024 ]] || exit 1; done"

# ============================================
# 4. HOST DETECTION
# ============================================
echo ""
echo "--- 4. Host Detection (OCTOPUS_HOST) ---"

ALL_SRC="$SCRIPT_DIR/orchestrate.sh $SCRIPT_DIR/lib/*.sh"

test_output "Codex host detected via CODEX_HOME" \
    "grep -l 'CODEX_HOME' $ALL_SRC | head -1 | xargs grep 'OCTOPUS_HOST.*codex'" \
    "codex"

test_output "Gemini host detected via GEMINI_HOME" \
    "grep -l 'GEMINI_HOME' $ALL_SRC | head -1 | xargs grep 'OCTOPUS_HOST.*gemini'" \
    "gemini"

test_output "Claude host detection preserved" \
    "grep 'OCTOPUS_HOST=\"claude\"' '$SCRIPT_DIR/orchestrate.sh'" \
    "claude"

test_output "Factory host detection preserved" \
    "grep 'OCTOPUS_HOST=\"factory\"' '$SCRIPT_DIR/orchestrate.sh'" \
    "factory"

test_output "Standalone fallback preserved" \
    "grep 'OCTOPUS_HOST=\"standalone\"' '$SCRIPT_DIR/orchestrate.sh'" \
    "standalone"

# ============================================
# 5. GRACEFUL DEGRADATION
# ============================================
echo ""
echo "--- 5. Graceful Degradation ---"

test_output "CC task management gated on OCTOPUS_HOST" \
    "grep 'OCTOPUS_HOST.*claude.*factory' '$SCRIPT_DIR/orchestrate.sh'" \
    "OCTOPUS_HOST"

test_output "Non-Claude hosts get empty CLAUDE_TASK_ID" \
    "grep -A5 'Non-Claude host' '$SCRIPT_DIR/orchestrate.sh'" \
    'CLAUDE_TASK_ID=\"\"'

test_output "Non-Claude hosts get empty CLAUDE_CODE_CONTROL" \
    "grep -A5 'Non-Claude host' '$SCRIPT_DIR/orchestrate.sh'" \
    'CLAUDE_CODE_CONTROL=\"\"'

test_output "Codex host skips CC version detection" \
    "grep 'skipping Claude Code version detection' '$SCRIPT_DIR/lib/providers.sh'" \
    "skipping Claude Code version"

test_output "Session ID falls back to CODEX_SESSION_ID" \
    "grep 'CODEX_SESSION_ID' '$SCRIPT_DIR/orchestrate.sh'" \
    "CODEX_SESSION_ID"

# ============================================
# 6. REGRESSION: orchestrate.sh SYNTAX
# ============================================
echo ""
echo "--- 6. Regression: Syntax Checks ---"

test_cmd "orchestrate.sh syntax valid" \
    "bash -n '$SCRIPT_DIR/orchestrate.sh'"

for lib_file in "$SCRIPT_DIR"/lib/*.sh; do
    local_name=$(basename "$lib_file")
    test_cmd "$local_name syntax valid" \
        "bash -n '$lib_file'"
done

test_cmd "build-codex-skills.sh syntax valid" \
    "bash -n '$SCRIPT_DIR/build-codex-skills.sh'"

# ============================================
# SUMMARY
# ============================================
echo ""
echo "========================================"
TOTAL=$((PASS + FAIL + SKIP))
echo -e "  Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}, ${YELLOW}${SKIP} skipped${NC} / ${TOTAL} total"
echo "========================================"
echo ""

exit $FAIL
