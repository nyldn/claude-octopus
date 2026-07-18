#!/usr/bin/env bash
# Regression tests for workflow terminal-state and skill metadata contracts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_TMP_DIR="/tmp/octopus-tests-$$"
trap 'rm -rf "$TEST_TMP_DIR"' EXIT

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Workflow Meta Contracts"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

DELIVER="$PROJECT_ROOT/skills/flow-deliver/SKILL.md"
DISCOVER="$PROJECT_ROOT/skills/flow-discover/SKILL.md"
VERIFY_GATE="$PROJECT_ROOT/skills/skill-verification-gate/SKILL.md"
ENFORCEMENT="$PROJECT_ROOT/skills/blocks/enforcement-patterns.md"

delivery_block=$(sed -n '/^## Post-Delivery: Route to Ship/,/^\*\*Ready to validate!/p' "$DELIVER")
if grep -q "route according to the user's explicit" <<< "$delivery_block" &&
   grep -q '^\- \*\*Ship requested:\*\*' <<< "$delivery_block" &&
   grep -q '^\- \*\*Branch wrap-up requested:\*\*' <<< "$delivery_block" &&
   grep -q '^\- \*\*Review only:\*\*' <<< "$delivery_block" &&
   grep -q 'Do not update the project' <<< "$delivery_block" &&
   grep -q 'Run this block only when the user explicitly requested shipping' <<< "$delivery_block" &&
   ! grep -q '^Suggest:' <<< "$delivery_block"; then
    pass "Review-only delivery stops without entering the shipping state"
else
    fail "Review-only delivery stops without entering the shipping state" \
        "Post-Delivery must explicitly keep review-only requests out of shipping"
fi

discover_block=$(sed -n '/^## Post-Discovery: State Update/,/^## /p' "$DISCOVER")
synthesis_line=$(grep -n 'if \[\[ ! -s' <<< "$discover_block" | head -1 | cut -d: -f1 || true)
exit_line=$(grep -n '^[[:space:]]*exit 1$' <<< "$discover_block" | head -1 | cut -d: -f1 || true)
present_line=$(grep -n 'sed -n' <<< "$discover_block" | head -1 | cut -d: -f1 || true)
project_line=$(grep -n 'update_project' <<< "$discover_block" | head -1 | cut -d: -f1 || true)
complete_line=$(grep -n 'update_state' <<< "$discover_block" | head -1 | cut -d: -f1 || true)

if [[ -n "$synthesis_line" && -n "$exit_line" && -n "$present_line" && -n "$project_line" && -n "$complete_line" ]] &&
   (( synthesis_line < exit_line && exit_line < present_line && present_line < project_line && project_line < complete_line )); then
    pass "Discovery verifies, presents, and persists synthesis before completion"
else
    fail "Discovery verifies, presents, and persists synthesis before completion" \
        "Post-Discovery operations are missing or out of order"
fi

iron_law_count=$(grep -c '^NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE$' "$VERIFY_GATE" || true)
if [[ "$iron_law_count" -eq 1 ]]; then
    pass "Verification gate states its Iron Law exactly once"
else
    fail "Verification gate states its Iron Law exactly once" \
        "found $iron_law_count copies"
fi

if awk '
    /^```/ {
        if (!inside && $0 == "```") bad = 1
        inside = !inside
    }
    END { exit (bad || inside) ? 1 : 0 }
' "$ENFORCEMENT"; then
    pass "Enforcement pattern examples use language-tagged fences"
else
    fail "Enforcement pattern examples use language-tagged fences" \
        "found an untagged fenced code block"
fi

trigger_only_contracts=(
    'skill-intent-contract|Use when starting a complex or ambiguous task that risks scope drift'
    'skill-native-escalation-routing|Use when choosing native or multi-LLM handling for init, review, or security requests'
    'skill-review-response|Use when a reviewer, CI bot, or another AI leaves feedback to address'
    'skill-staged-review|Use when a PR or feature needs both specification and code-quality review'
    'skill-verification-gate|Use when about to declare work complete, fixed, passing, or done'
    'skill-verify|Use when a nontrivial change needs end-to-end verification before committing or shipping'
)

metadata_ok=true
for contract in "${trigger_only_contracts[@]}"; do
    skill=${contract%%|*}
    expected=${contract#*|}
    description=$(sed -n 's/^description: *"\(.*\)"$/\1/p' \
        "$PROJECT_ROOT/skills/$skill/SKILL.md" | head -1 || true)
    if [[ "$description" != "$expected" ]]; then
        metadata_ok=false
        break
    fi
done

if [[ "$metadata_ok" == true ]]; then
    pass "Trigger-only skill descriptions state when to use the skill"
else
    fail "Trigger-only skill descriptions state when to use the skill" \
        "$skill description must be the exact trigger-only contract"
fi

test_summary
