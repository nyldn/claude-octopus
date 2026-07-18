#!/usr/bin/env bash
# Regression tests for workflow terminal-state and skill metadata contracts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Workflow Meta Contracts"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

DELIVER="$PROJECT_ROOT/skills/flow-deliver/SKILL.md"
DISCOVER="$PROJECT_ROOT/skills/flow-discover/SKILL.md"
VERIFY_GATE="$PROJECT_ROOT/skills/skill-verification-gate/SKILL.md"
ENFORCEMENT="$PROJECT_ROOT/skills/blocks/enforcement-patterns.md"

if grep -A12 '^## Post-Delivery: Route to Ship' "$DELIVER" | grep -q '\*\*Review only:\*\*' &&
   grep -A12 '^## Post-Delivery: Route to Ship' "$DELIVER" | grep -q 'Do not update the project'; then
    pass "Review-only delivery stops without entering the shipping state"
else
    fail "Review-only delivery stops without entering the shipping state" \
        "Post-Delivery must explicitly keep review-only requests out of shipping"
fi

discover_block=$(sed -n '/^## Post-Discovery: State Update/,/^## /p' "$DISCOVER")
synthesis_line=$(grep -n 'if \[\[ ! -s' <<< "$discover_block" | head -1 | cut -d: -f1)
present_line=$(grep -n 'sed -n' <<< "$discover_block" | head -1 | cut -d: -f1)
project_line=$(grep -n 'update_project' <<< "$discover_block" | head -1 | cut -d: -f1)
complete_line=$(grep -n 'update_state' <<< "$discover_block" | head -1 | cut -d: -f1)

if [[ -n "$synthesis_line" && -n "$present_line" && -n "$project_line" && -n "$complete_line" ]] &&
   (( synthesis_line < present_line && present_line < project_line && project_line < complete_line )); then
    pass "Discovery verifies, presents, and persists synthesis before completion"
else
    fail "Discovery verifies, presents, and persists synthesis before completion" \
        "Post-Discovery operations are missing or out of order"
fi

iron_law_count=$(grep -c '^NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE$' "$VERIFY_GATE")
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

trigger_only_skills=(
    skill-intent-contract
    skill-native-escalation-routing
    skill-review-response
    skill-staged-review
    skill-verification-gate
    skill-verify
)

metadata_ok=true
for skill in "${trigger_only_skills[@]}"; do
    description=$(sed -n 's/^description: *"\(.*\)"$/\1/p' \
        "$PROJECT_ROOT/skills/$skill/SKILL.md" | head -1)
    if [[ ! "$description" =~ [Uu]se\ (when|at|before|whenever) ]]; then
        metadata_ok=false
        break
    fi
done

if [[ "$metadata_ok" == true ]]; then
    pass "Trigger-only skill descriptions state when to use the skill"
else
    fail "Trigger-only skill descriptions state when to use the skill" \
        "$skill description must state when to use the skill"
fi

test_summary
