#!/usr/bin/env bash
# Contract tests for skill-agent-topology (issue #699).
#
# The skill audits an existing multi-agent setup and decides whether its
# coordination cost is earned. Most of what #699 asked for already existed
# (workflow comparison in commands/auto.md and skill-decision-support; the
# cost/benefit norm in skills/blocks/frontier-model-routing.md), so what ships
# here is only the part that did not: the boundary-counting diagnostic.
#
# These cases pin the load-bearing content, not prose style. Each one guards a
# decision that was argued through in review and would be easy to lose in a
# later edit.
set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -P "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "skill-agent-topology contract (issue #699)"

SKILL="$PROJECT_ROOT/.claude/skills/skill-agent-topology/SKILL.md"
PLUGIN_JSON="$PROJECT_ROOT/.claude-plugin/plugin.json"

test_case "the skill source exists under .claude/skills"
if [[ -f "$SKILL" ]]; then
    test_pass
else
    test_fail "missing $SKILL — skills/ is generated, author the source here"
fi

# Everything below needs the file; bail out coherently rather than emitting a
# cascade of identical failures.
if [[ ! -f "$SKILL" ]]; then
    test_summary
    exit 1
fi

# validate-release.sh:413 reads the name with `sed -n '2p'`, so it must be the
# first frontmatter line or release validation reads an empty name.
test_case "name is the first frontmatter line and matches the directory"
if [[ "$(sed -n '2p' "$SKILL")" == "name: skill-agent-topology" ]]; then
    test_pass
else
    test_fail "line 2 must be exactly 'name: skill-agent-topology', got: $(sed -n '2p' "$SKILL")"
fi

test_case "description is a single quoted line"
desc_lines=$(grep -c '^description:' "$SKILL" || true)
desc=$(sed -n 's/^description: *"\(.*\)"$/\1/p' "$SKILL")
if [[ "$desc_lines" == "1" && -n "$desc" ]]; then
    test_pass
else
    test_fail "need exactly one double-quoted single-line description; found $desc_lines line(s), parsed '$desc'"
fi

test_case "the skill is registered in plugin.json"
if jq -e '.skills[] | select(. == "./skills/skill-agent-topology")' "$PLUGIN_JSON" >/dev/null 2>&1; then
    test_pass
else
    test_fail "add \"./skills/skill-agent-topology\" to the skills array, or test-docs-sync.sh will fail"
fi

test_case "body carries the assembly-standard sections"
missing=""
for section in "When To Use" "When Not To Use" "Inputs" "Workflow" \
               "Stop Or Checkpoint Rules" "Output Contract" "Verification"; do
    grep -qi "^#\+ .*${section}" "$SKILL" || missing="$missing; $section"
done
if [[ -z "$missing" ]]; then
    test_pass
else
    test_fail "missing sections per docs/PLUGIN-ASSEMBLY-STANDARD.md${missing}"
fi

# The whole point of the diagnostic. Without collapse as a real outcome it is a
# rubber stamp that can only ever recommend keeping or adding agents.
test_case "collapsing to a single agent is a first-class recommendation"
if grep -qi "single.expert" "$SKILL" && grep -qi "collapse" "$SKILL"; then
    test_pass
else
    test_fail "the single-expert null must appear as a candidate outcome, and 'collapse' must be a recommendation the skill can return"
fi

# There is already a working "is this agent adding anything" gate. Inventing a
# second, disagreeing metric would be worse than reusing it.
test_case "cites the existing overlap gate rather than inventing a metric"
if grep -q "council_persona_overlap_score" "$SKILL"; then
    test_pass
else
    test_fail "must cite council_persona_overlap_score (scripts/lib/council.sh) as the existing precedent"
fi

# #699's own caveat 1. The studied committee deliberated in free text with no
# independent evidence; Octo's providers bring different models and real search.
# Without this stated, the skill's first honest run indicts /octo:debate and
# /octo:council, which is precisely the misreading the issue warned against.
test_case "states that cross-provider debate is not the studied committee"
if grep -qi "independent evidence" "$SKILL" && grep -qiE "debate|council" "$SKILL"; then
    test_pass
else
    test_fail "must state that providers bringing independent evidence are not the free-text committee the study penalised"
fi

# Decided in review: cite the framing, ship no coefficients. #701 documents two
# providers fabricating an "85% confidence threshold" attributed to named
# authors; hardcoding one simulation's numbers invites the same failure and
# reads as authority over the user's situation.
test_case "ships no numeric effect sizes from the cited study"
if grep -qE '(-|−|\+)[0-9]+\.[0-9]+\*|[0-9]+% more efficient|p < \.[0-9]+' "$SKILL"; then
    test_fail "numeric coefficients must not be shipped; cite the direction, not the numbers"
else
    test_pass
fi

# ...but the direction must survive, or the diagnostic has no tiebreaker and
# degrades into a worksheet.
test_case "keeps the ordinal direction that sets the burden of proof"
if grep -qiE "burden of proof|default is (to )?not|start(s)? from one" "$SKILL"; then
    test_pass
else
    test_fail "must state that the burden of proof falls on adding a boundary"
fi

test_case "names what carries context across a boundary it recommends keeping"
if grep -qi "carries.*context\|context.*across" "$SKILL"; then
    test_pass
else
    test_fail "when the diagnostic keeps a boundary it must name what carries context across it"
fi

# test-mandatory-compliance.sh requires MANDATORY COMPLIANCE + PROHIBITED in any
# skill body mentioning orchestrate.sh. This skill is advisory, so the cheaper
# and more honest route is not to mention it.
test_case "stays advisory: no orchestrate.sh mention, so no compliance contract needed"
if grep -q "orchestrate\.sh" "$SKILL"; then
    test_fail "mentioning orchestrate.sh triggers the MANDATORY COMPLIANCE + PROHIBITED contract; refer to /octo: commands instead"
else
    test_pass
fi

test_summary
