#!/bin/bash
# Test: Command YAML frontmatter validation
# Validates that all command files use 'command:' field (not 'name:')

set -euo pipefail


# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Command YAML frontmatter validation"


echo "================================================================"
echo "  Command YAML Frontmatter Validation Test"
echo "================================================================"
echo ""

FAILED=0
PASSED=0

# Test 1: Check all command files use 'command:' field
echo "Testing: All command files use 'command:' field (not 'name:')..."
COMMANDS_DIR="$PROJECT_ROOT/commands"

if [ ! -d "$COMMANDS_DIR" ]; then
    echo -e "${RED}✗${NC} Commands directory not found: $COMMANDS_DIR"
    exit 1
fi

echo "Testing: Octopus does not shadow Claude Code native /doctor..."
if [ -f "$COMMANDS_DIR/doctor.md" ]; then
    echo -e "${RED}✗${NC} doctor.md must not be registered as an Octopus slash command"
    echo -e "   ${YELLOW}FIX:${NC} Keep Octopus diagnostics in skills/runtime only so native /doctor remains accessible"
    FAILED=$((FAILED + 1))
else
    echo -e "${GREEN}✓${NC} no doctor.md command file present"
    PASSED=$((PASSED + 1))
fi

if jq -e '.commands[]? | select(. == "./commands/doctor.md")' "$PROJECT_ROOT/.claude-plugin/plugin.json" >/dev/null; then
    echo -e "${RED}✗${NC} plugin.json must not register commands/doctor.md"
    FAILED=$((FAILED + 1))
else
    echo -e "${GREEN}✓${NC} plugin.json does not register doctor.md"
    PASSED=$((PASSED + 1))
fi

if grep -R "^command:[[:space:]]*doctor$" "$COMMANDS_DIR" >/dev/null 2>&1; then
    echo -e "${RED}✗${NC} no Octopus command may use frontmatter 'command: doctor'"
    FAILED=$((FAILED + 1))
else
    echo -e "${GREEN}✓${NC} no command frontmatter claims doctor"
    PASSED=$((PASSED + 1))
fi

count_doctor_references() {
    local path="$1"
    [[ -f "$path" && -r "$path" ]] || return 1
    { grep -oF -- '/octo:doctor' "$path" || [[ $? -eq 1 ]]; } | awk 'END { print NR + 0 }'
}

test_case "Doctor reference counter rejects unavailable files"
if count_doctor_references "$TEST_TMP_DIR/missing-doctor-surface" >/dev/null; then
    test_fail "missing Doctor guidance surfaces must not count as zero references"
else
    test_pass
fi

PUBLIC_DOCTOR_SURFACES=(
    "README.md|0"
    "docs/README.md|0"
    "docs/TROUBLESHOOTING.md|0"
    ".claude/skills/skill-copilot-provider/SKILL.md|0"
    ".claude/skills/skill-doctor/SKILL.md|1"
    ".cursor-plugin/commands/octo-doctor.md|1"
    "scripts/lib/review.sh|0"
    "scripts/install-deps.sh|0"
    "skills/skill-copilot-provider/SKILL.md|0"
    "skills/skill-doctor/SKILL.md|1"
    "commands/plan.md|0"
    "commands/resume.md|0"
    "commands/sentinel.md|0"
)

for surface in "${PUBLIC_DOCTOR_SURFACES[@]}"; do
    relative_path="${surface%%|*}"
    expected_count="${surface##*|}"
    test_case "$relative_path uses only supported Doctor guidance"
    if ! actual_count=$(count_doctor_references "$PROJECT_ROOT/$relative_path"); then
        test_fail "$relative_path is missing or unreadable"
    elif [[ "$actual_count" -eq "$expected_count" ]] &&
       { [[ "$expected_count" -eq 0 ]] || grep -Fq '`/octo:doctor` was removed in v9.41.0' "$PROJECT_ROOT/$relative_path"; }; then
        test_pass
    else
        test_fail "$relative_path has $actual_count retired /octo:doctor references; expected $expected_count intentional reference(s)"
    fi
done

test_case "COMMAND-REFERENCE.md explains the retired Doctor command exactly once"
if ! doctor_reference_count=$(count_doctor_references "$PROJECT_ROOT/docs/COMMAND-REFERENCE.md"); then
    test_fail "docs/COMMAND-REFERENCE.md is missing or unreadable"
elif [[ "$doctor_reference_count" -eq 1 ]] &&
   grep -Fq 'intentionally leaves `/octo:doctor` unregistered' "$PROJECT_ROOT/docs/COMMAND-REFERENCE.md"; then
    test_pass
else
    test_fail "docs/COMMAND-REFERENCE.md must explain retired /octo:doctor exactly once"
fi

for cmd_file in "$COMMANDS_DIR"/*.md; do
    if [ ! -f "$cmd_file" ]; then
        continue
    fi

    filename=$(basename "$cmd_file")

    # Check if file has YAML frontmatter
    if ! head -1 "$cmd_file" | grep -q "^---$"; then
        echo -e "${RED}✗${NC} $filename: Missing YAML frontmatter"
        FAILED=$((FAILED + 1))
        continue
    fi

    # Check if it uses 'command:' field
    if grep -q "^command:" "$cmd_file"; then
        echo -e "${GREEN}✓${NC} $filename uses 'command:' field"
        PASSED=$((PASSED + 1))
    else
        # Check if it incorrectly uses 'name:' field
        if grep -q "^name:" "$cmd_file"; then
            echo -e "${RED}✗${NC} $filename uses 'name:' instead of 'command:'"
            echo -e "   ${YELLOW}FIX:${NC} Change 'name:' to 'command:' in YAML frontmatter"
            echo -e "   ${YELLOW}RUN:${NC} ./scripts/fix-command-frontmatter.sh"
            FAILED=$((FAILED + 1))
        else
            echo -e "${RED}✗${NC} $filename: No 'command:' or 'name:' field found"
            FAILED=$((FAILED + 1))
        fi
    fi
done

echo ""
echo "================================================================"
echo "Passed: $PASSED  Failed: $FAILED"

# v9.44: propagate failures — this test previously always exited 0 because it
# tracks its own counters instead of the shared harness's (bug: doctor.md
# regression in 6e0cb4a shipped despite three red ✗ assertions above).
if [ "$FAILED" -gt 0 ]; then
    echo "RESULT: FAIL ($FAILED check(s) failed)"
    exit 1
fi
test_summary
