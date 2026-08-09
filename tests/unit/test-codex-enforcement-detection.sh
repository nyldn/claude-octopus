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
empty_adapted="$(adapt_body_for_codex "$empty_contract")"
if body_has_enforcement "$empty_contract"; then
    test_fail "empty contract heading was treated as enforcement"
elif grep -q 'This generated Codex skill preserves an enforced workflow contract' <<< "$empty_adapted"; then
    test_pass
else
    test_fail "empty contract did not receive generated enforcement"
fi

test_case "Execution Contract heading inside a fenced example is ignored"
fenced_contract="$TEST_TMP_DIR/fenced-contract.md"
write_fixture "$fenced_contract" $'## Example\n\n```markdown\n## Execution Contract\n\nYou MUST run the command.\n```\n\n## Workflow\n\nRun the workflow.'
fenced_adapted="$(adapt_body_for_codex "$fenced_contract")"
if body_has_enforcement "$fenced_contract"; then
    test_fail "fenced example was treated as the real execution contract"
elif grep -q 'This generated Codex skill preserves an enforced workflow contract' <<< "$fenced_adapted"; then
    test_pass
else
    test_fail "fenced example did not receive generated enforcement"
fi

test_case "legacy marker outside an enforcement section does not suppress generated enforcement"
unrelated_marker="$TEST_TMP_DIR/unrelated-marker.md"
write_fixture "$unrelated_marker" $'## Notes\n\nThe release CANNOT SKIP the changelog.\n\n## Workflow\n\nRun the workflow.'
unrelated_adapted="$(adapt_body_for_codex "$unrelated_marker")"
if body_has_enforcement "$unrelated_marker"; then
    test_fail "unrelated legacy marker was treated as enforcement"
elif grep -q 'This generated Codex skill preserves an enforced workflow contract' <<< "$unrelated_adapted"; then
    test_pass
else
    test_fail "fixture with unrelated marker did not receive generated enforcement"
fi

test_case "real Execution Contract with mandatory content is detected"
real_contract="$TEST_TMP_DIR/real-contract.md"
write_fixture "$real_contract" $'## Execution Contract\n\nYou MUST run the command.\n\n**PROHIBITED:** Do not simulate it.\n\n## Workflow\n\nRun the workflow.'
real_adapted="$(adapt_body_for_codex "$real_contract")"
real_contract_count="$(grep -c '^## Execution Contract' <<< "$real_adapted" || true)"
if ! body_has_enforcement "$real_contract"; then
    test_fail "mandatory contract content was not detected"
elif grep -q 'This generated Codex skill preserves an enforced workflow contract' <<< "$real_adapted"; then
    test_fail "real contract received a duplicate generated enforcement block"
elif [[ "$real_contract_count" -eq 1 ]]; then
    test_pass
else
    test_fail "adapted output contained $real_contract_count execution-contract headings"
fi

test_summary
