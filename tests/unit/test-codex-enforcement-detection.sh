#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT/scripts/build-codex-skills.sh"

test_suite "Codex skill enforcement detection"

write_fixture() {
    local path="$1"
    local body="$2"

    {
        printf '%s\n' '---'
        printf '%s\n' 'name: enforcement-fixture'
        printf '%s\n' 'execution_mode: enforced'
        printf '%s\n' '---'
        printf '%s\n' "$body"
    } > "$path"
}

test_case "empty Execution Contract heading does not suppress generated enforcement"
empty_contract="$TEST_TMP_DIR/empty-contract.md"
write_fixture "$empty_contract" $'## Execution Contract\n\n## Workflow\n\nRun the workflow.'
if body_has_enforcement "$empty_contract"; then
    test_fail "empty contract heading was treated as enforcement"
else
    test_pass
fi

test_case "Execution Contract heading inside a fenced example is ignored"
fenced_contract="$TEST_TMP_DIR/fenced-contract.md"
write_fixture "$fenced_contract" $'## Example\n\n```markdown\n## Execution Contract\n\nYou MUST run the command.\n```\n\n## Workflow\n\nRun the workflow.'
if body_has_enforcement "$fenced_contract"; then
    test_fail "fenced example was treated as the real execution contract"
else
    test_pass
fi

test_case "real Execution Contract with mandatory content is detected"
real_contract="$TEST_TMP_DIR/real-contract.md"
write_fixture "$real_contract" $'## Execution Contract\n\nYou MUST run the command.\n\n**PROHIBITED:** Do not simulate it.\n\n## Workflow\n\nRun the workflow.'
if body_has_enforcement "$real_contract"; then
    test_pass
else
    test_fail "mandatory contract content was not detected"
fi

test_summary
