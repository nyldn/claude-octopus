#!/usr/bin/env bash
# Contract tests for the agency-triad allocation folded into skill-intent-contract
# (issue #700).
#
# #700 asked for a standalone pre-workflow skill. After narrowing, what remained
# was a three-question elicitation plus one rule — which duplicates a question
# skill-intent-contract already asks, in the place #700 wanted it asked. It was
# folded in rather than shipped as a 59th skill competing for discovery.
#
# The risk rubric is in scope and not deferred: the repo classifies complexity
# (estimate_complexity) and uncertainty (classify_cynefin) but nothing anywhere
# classifies risk, so the intermediate-risk rule would have no input without it.
set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -P "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "intent-contract agency allocation (issue #700)"

SKILL="$PROJECT_ROOT/.claude/skills/skill-intent-contract/SKILL.md"
META_CONTRACTS="$PROJECT_ROOT/tests/unit/test-workflow-meta-contracts.sh"
ORCHESTRATE="$PROJECT_ROOT/scripts/orchestrate.sh"

test_case "the intent-contract skill source exists"
if [[ -f "$SKILL" ]]; then
    test_pass
else
    test_fail "missing $SKILL"
    test_summary
    exit 1
fi

# The description is one of six strings locked verbatim by
# test-workflow-meta-contracts.sh. The fold is only cheap because the body is
# unpinned; changing the description breaks a pinned contract.
test_case "the pinned description is unchanged"
pinned=$(grep -o "skill-intent-contract|[^']*" "$META_CONTRACTS" | head -1 | cut -d'|' -f2-)
actual=$(sed -n 's/^description: *"\{0,1\}\(.*\)"\{0,1\}$/\1/p' "$SKILL" | head -1 | sed 's/"$//')
if [[ -n "$pinned" && "$actual" == "$pinned" ]]; then
    test_pass
else
    test_fail "description drifted from the pinned contract. pinned='$pinned' actual='$actual'"
fi

# The triad is the whole contribution. One axis cannot express "AI takes
# initiative, human keeps decision rights", which is the allocation the cited
# Lubars & Tan finding says people actually want.
test_case "all three agency dimensions are elicited separately"
missing=""
for dim in "initiative" "control" "decision rights"; do
    grep -qi "$dim" "$SKILL" || missing="$missing; $dim"
done
if [[ -z "$missing" ]]; then
    test_pass
else
    test_fail "agency triad incomplete, missing:${missing}"
fi

# An allocation that does not resolve to a real setting is prose. These four are
# the values orchestrate.sh actually branches on.
test_case "the triad resolves to the four real AUTONOMY_MODE values"
missing=""
for mode in "supervised" "semi-autonomous" "loop-until-approved" "autonomous"; do
    grep -q -- "$mode" "$SKILL" || missing="$missing; $mode"
done
if [[ -z "$missing" ]]; then
    test_pass
else
    test_fail "must map onto the real AUTONOMY_MODE values, missing:${missing}"
fi

# Guards against the mapping drifting away from the implementation.
test_case "those four values still match orchestrate.sh"
missing=""
for mode in "supervised" "semi-autonomous" "loop-until-approved" "autonomous"; do
    grep -q "\"$mode\"" "$ORCHESTRATE" || missing="$missing; $mode"
done
if [[ -z "$missing" ]]; then
    test_pass
else
    test_fail "AUTONOMY_MODE values drifted in orchestrate.sh, missing:${missing} — update the skill to match"
fi

test_case "contract-only not-applicable never becomes a runtime AUTONOMY_MODE"
if grep -q 'contract-only sentinel' "$SKILL" &&
   grep -q 'must not be passed to the workflow engine' "$SKILL" &&
   ! grep -q '"not-applicable"' "$ORCHESTRATE"; then
    test_pass
else
    test_fail "not-applicable must remain persisted contract metadata, not a fifth runtime mode"
fi

test_case "states where collapsing the triad onto one mode loses information"
if grep -qiE "loses information|cannot express|collapse[sd]? .*(onto|into) one|does not distinguish" "$SKILL"; then
    test_pass
else
    test_fail "must say explicitly that AUTONOMY_MODE cannot represent the three dimensions independently"
fi

# Nothing in the repo classifies risk, so the rubric ships here.
test_case "carries a risk rubric defined by consequence, not by complexity"
hits=0
for term in "irreversib" "consequence" "accountab"; do
    grep -qi "$term" "$SKILL" && hits=$((hits + 1))
done
if [[ "$hits" -ge 2 ]]; then
    test_pass
else
    test_fail "risk must be defined by irreversibility / consequence / accountability, not reused from complexity scoring"
fi

# The rule that inverts. Easy to lose precisely because it is counter-intuitive.
test_case "encodes the intermediate-risk inversion"
if grep -qi "intermediate" "$SKILL" && grep -qiE "second opinion|avoid AI|gatekeeper" "$SKILL"; then
    test_pass
else
    test_fail "must encode that intermediate-risk high-uncertainty work avoids AI entirely, 'neither as a gatekeeper nor as a second opinion'"
fi

test_case "surfaces the tension rather than resolving it silently"
if grep -qi "tension" "$SKILL"; then
    test_pass
else
    test_fail "the inversion contradicts the paper's broader claim; the skill must say so rather than pick a side quietly"
fi

test_case "every allocation row records the complete ordered contract"
allocation_table=$(sed -n '/^| Risk \/ complexity |/,/^$/p' "$SKILL")
if grep -Fq '| Low / low | AI | AI | AI | executor | AI-assisted | not-needed | `autonomous` |' <<< "$allocation_table" &&
   grep -Fq '| Low / high | shared | human | human | collaborator | AI-assisted | not-needed | `loop-until-approved` |' <<< "$allocation_table" &&
   grep -Fq '| High / low | human | human | human | executor | AI-assisted | not-needed | `supervised` |' <<< "$allocation_table" &&
   grep -Fq '| High / high | human | human | human | challenger | AI-assisted | not-needed | `supervised` |' <<< "$allocation_table"; then
    test_pass
else
    test_fail "allocation rows must keep ordered roles, execution disposition, escalation, and runtime mode together"
fi

test_case "intermediate-risk escalation records an ordered resolution before execution"
escalation=$(sed -n '/^For intermediate risk/,/^### Step 1:/p' "$SKILL")
pending_disposition_line=$(grep -n 'Execution disposition.*pending-user-decision' <<< "$escalation" | head -1 | cut -d: -f1 || true)
pending_decision_line=$(grep -n 'Escalation decision.*pending' <<< "$escalation" | head -1 | cut -d: -f1 || true)
stop_line=$(grep -n 'stop before execution' <<< "$escalation" | head -1 | cut -d: -f1 || true)
rewrite_line=$(grep -n 'rewrite the Task Allocation fields' <<< "$escalation" | head -1 | cut -d: -f1 || true)
human_only_line=$(grep -n 'human-only.*must not be passed to the workflow engine' <<< "$escalation" | head -1 | cut -d: -f1 || true)
if [[ -n "$pending_disposition_line" && -n "$pending_decision_line" && -n "$stop_line" && -n "$rewrite_line" && -n "$human_only_line" ]] &&
   (( pending_disposition_line <= pending_decision_line && pending_decision_line <= stop_line && stop_line < rewrite_line && rewrite_line < human_only_line )); then
    test_pass
else
    test_fail "intermediate-risk path must record pending state, stop, rewrite the contract, then resolve human-only handling"
fi

# Deferring the complexity axis is what keeps this a fold and not a second,
# disagreeing classifier.
test_case "defers complexity scoring to the existing classifiers"
if grep -q "estimate_complexity" "$SKILL" && grep -q "classify_cynefin" "$SKILL"; then
    test_pass
else
    test_fail "must defer to estimate_complexity and classify_cynefin (scripts/lib/routing.sh) rather than re-scoring complexity"
fi

test_summary
