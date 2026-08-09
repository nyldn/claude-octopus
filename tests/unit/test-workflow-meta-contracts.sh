#!/usr/bin/env bash
# Regression tests for workflow terminal-state and skill metadata contracts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_TMP_DIR="/tmp/octopus-tests-$$"
trap 'rm -rf "$TEST_TMP_DIR"' EXIT

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Workflow Meta Contracts"

DELIVER="$PROJECT_ROOT/skills/flow-deliver/SKILL.md"
DEVELOP="$PROJECT_ROOT/skills/flow-develop/SKILL.md"
DISCOVER="$PROJECT_ROOT/skills/flow-discover/SKILL.md"
DOCTOR="$PROJECT_ROOT/skills/skill-doctor/SKILL.md"
SECURITY_AUDIT="$PROJECT_ROOT/skills/octopus-security-audit/SKILL.md"
UI_UX_DESIGN="$PROJECT_ROOT/skills/octopus-ui-ux-design/SKILL.md"
VERIFY_GATE="$PROJECT_ROOT/skills/skill-verification-gate/SKILL.md"
ENFORCEMENT="$PROJECT_ROOT/skills/blocks/enforcement-patterns.md"

delivery_block=$(sed -n '/^## Post-Delivery: Route to Ship/,/^\*\*Ready to validate!/p' "$DELIVER")
test_case "Review-only delivery stops without entering the shipping state"
if grep -q "route according to the user's explicit" <<< "$delivery_block" &&
   grep -q '^\- \*\*Ship requested:\*\*' <<< "$delivery_block" &&
   grep -q '^\- \*\*Branch wrap-up requested:\*\*' <<< "$delivery_block" &&
   grep -q '^\- \*\*Review only:\*\*' <<< "$delivery_block" &&
   grep -q 'Do not update the project' <<< "$delivery_block" &&
   grep -q 'Run this block only when the user explicitly requested shipping' <<< "$delivery_block" &&
   grep -q 'Skill(skill: "skill-ship"' <<< "$delivery_block" &&
   ! grep -q '^Suggest:' <<< "$delivery_block"; then
    test_pass
else
    test_fail "Post-Delivery must explicitly keep review-only requests out of shipping"
fi

develop_block=$(sed -n '/^## Post-Development: Checkpoint/,/^## /p' "$DEVELOP")
test_line=$(grep -n 'fresh targeted tests' <<< "$develop_block" | head -1 | cut -d: -f1 || true)
checkpoint_line=$(grep -n '^git tag ' <<< "$develop_block" | head -1 | cut -d: -f1 || true)
develop_complete_line=$(grep -n 'update_state' <<< "$develop_block" | head -1 | cut -d: -f1 || true)

test_case "Development verifies and checkpoints before completion state"
if [[ -n "$test_line" && -n "$checkpoint_line" && -n "$develop_complete_line" ]] &&
   (( test_line < checkpoint_line && checkpoint_line < develop_complete_line )); then
    test_pass
else
    test_fail "Post-Development must require fresh targeted tests and a checkpoint before update_state"
fi

discover_block=$(sed -n '/^## Post-Discovery: State Update/,/^## /p' "$DISCOVER")
synthesis_line=$(grep -n 'if \[\[ ! -s' <<< "$discover_block" | head -1 | cut -d: -f1 || true)
exit_line=$(grep -n '^[[:space:]]*exit 1$' <<< "$discover_block" | head -1 | cut -d: -f1 || true)
present_line=$(grep -nF 'cat "$SYNTHESIS_FILE"' <<< "$discover_block" | head -1 | cut -d: -f1 || true)
project_line=$(grep -n 'update_project' <<< "$discover_block" | head -1 | cut -d: -f1 || true)
complete_line=$(grep -n 'update_state' <<< "$discover_block" | head -1 | cut -d: -f1 || true)

test_case "Discovery verifies, presents, and persists synthesis before completion"
if [[ -n "$synthesis_line" && -n "$exit_line" && -n "$present_line" && -n "$project_line" && -n "$complete_line" ]] &&
   (( synthesis_line < exit_line && exit_line < present_line && present_line < project_line && project_line < complete_line )) &&
   grep -Fq 'cat "$SYNTHESIS_FILE"' <<< "$discover_block" &&
   ! grep -Eq 'head -100|sed -n .1,100p.|See synthesis file' <<< "$discover_block" &&
   grep -q 'if ! .*update_project' <<< "$(tr '\n' ' ' <<< "$discover_block")"; then
    test_pass
else
    test_fail "Post-Discovery must persist the complete synthesis and fail closed before update_state"
fi

test_case "Discovery terminal state requires PROJECT.md persistence"
discover_terminal=$(sed -n '/^## Terminal State/,/^\*\*Ready to research!/p' "$DISCOVER")
if grep -q '\.octo/PROJECT\.md' <<< "$discover_terminal"; then
    test_pass
else
    test_fail "Discover terminal state omitted PROJECT.md persistence"
fi

test_case "Doctor quick-reference commands use the resolved plugin root"
doctor_quick_ref=$(sed -n '/^## Quick Reference/,$p' "$DOCTOR")
if grep -q '\$OCTO_PLUGIN_ROOT/scripts/orchestrate\.sh.*doctor auth --verbose' <<< "$doctor_quick_ref" &&
   grep -q '\$OCTO_PLUGIN_ROOT/scripts/orchestrate\.sh.*doctor --json' <<< "$doctor_quick_ref" &&
   ! grep -q '`bash scripts/orchestrate\.sh' <<< "$doctor_quick_ref"; then
    test_pass
else
    test_fail "Doctor quick reference bypasses its plugin-root resolver"
fi

test_case "Security audit documents the configured Fable fallback and retry opt-out"
if grep -q 'OCTOPUS_FABLE5_FALLBACK_MODEL' "$SECURITY_AUDIT" &&
   grep -q 'OCTOPUS_FABLE5_NO_RETRY=1' "$SECURITY_AUDIT" &&
   grep -q 'claude-opus-5' "$SECURITY_AUDIT"; then
    test_pass
else
    test_fail "Security audit Fable guidance drifted from runtime configuration"
fi

test_case "UI/UX workflow resolves dials and stops on failed preflight"
ui_flat=$(tr '\n' ' ' < "$UI_UX_DESIGN")
if grep -q 'explicit user answer takes precedence' "$UI_UX_DESIGN" &&
   grep -q 'skip the Dials question' <<< "$ui_flat" &&
   grep -q 'Only continue to Step 4 when preflight returns `READY`' <<< "$ui_flat"; then
    test_pass
else
    test_fail "UI/UX dial or preflight branches are incomplete"
fi

test_case "UI/UX examples and critique obey the design-taste contract"
variant_a=$(sed -n '/Variant A:/,/Variant B:/p' "$UI_UX_DESIGN")
critique=$(sed -n '/^Critique dimensions:/,/^For each issue found/p' "$UI_UX_DESIGN")
if ! grep -qE 'Inter|cream|terracotta|#F5F0EB|#E07A5F' <<< "$variant_a" &&
   grep -q 'all five dimensions' "$UI_UX_DESIGN" &&
   [[ "$(grep -cE '^[1-5]\. (ACCESSIBILITY|PRACTICALITY|FIT|GAPS|SLOP)' <<< "$critique")" -eq 5 ]]; then
    test_pass
else
    test_fail "UI/UX example or five-dimension critique contradicts its hard constraints"
fi

test_case "UI/UX persistence writes and verifies branch-scoped lineage"
persistence=$(sed -n '/^### STEP 8: Present Results and Persist/,/^\*\*Offer next steps:/p' "$UI_UX_DESIGN")
if grep -q 'git_revision:' <<< "$persistence" &&
   grep -q 'supersedes:' <<< "$persistence" &&
   grep -q 'DESIGN_BODY' <<< "$persistence" &&
   grep -Fq '[[ ! -s "$FILEPATH" ]]' <<< "$persistence" &&
   grep -q 'matches the current Git branch' <<< "$(tr '\n' ' ' <<< "$persistence")" &&
   grep -q 'detached HEAD' <<< "$persistence"; then
    test_pass
else
    test_fail "UI/UX persisted-design contract lacks a complete write, verification, or branch filter"
fi

iron_law_count=$(grep -c '^NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE$' "$VERIFY_GATE" || true)
test_case "Verification gate states its Iron Law exactly once"
if [[ "$iron_law_count" -eq 1 ]]; then
    test_pass
else
    test_fail "found $iron_law_count copies"
fi

test_case "Enforcement pattern examples use language-tagged fences"
if awk '
    /^```/ {
        if (!inside && $0 == "```") bad = 1
        inside = !inside
    }
    END { exit (bad || inside) ? 1 : 0 }
' "$ENFORCEMENT"; then
    test_pass
else
    test_fail "found an untagged fenced code block"
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

test_case "Trigger-only skill descriptions state when to use the skill"
if [[ "$metadata_ok" == true ]]; then
    test_pass
else
    test_fail "$skill description must be the exact trigger-only contract"
fi

test_summary
