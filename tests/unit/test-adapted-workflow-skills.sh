#!/usr/bin/env bash
# Contracts for the four skills adapted from mattpocock/skills (MIT).
#
# Names are ours, deliberately: skill-pressure-test, skill-authoring,
# skill-work-slicing, skill-intake. The upstream names (grilling,
# writing-great-skills, to-tickets, triage) are not surfaced anywhere a user or
# the router sees. Attribution lives in each skill body, which is a licence
# obligation and a different thing from borrowing an identifier.
#
# These cases pin the load-bearing ideas — the parts that would be easy to
# smooth away in a later edit and that were the reason for adopting at all.
set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -P "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Adapted workflow skills"

PLUGIN_JSON="$PROJECT_ROOT/.claude-plugin/plugin.json"
SKILLS="skill-pressure-test skill-authoring skill-work-slicing skill-intake"

# ── shared structural contract ───────────────────────────────────────────────
for s in $SKILLS; do
    f="$PROJECT_ROOT/.claude/skills/$s/SKILL.md"

    test_case "$s: source exists under .claude/skills"
    if [[ -f "$f" ]]; then test_pass; else test_fail "missing $f"; continue; fi

    test_case "$s: name is the first frontmatter line and matches the directory"
    if [[ "$(sed -n '2p' "$f")" == "name: $s" ]]; then
        test_pass
    else
        test_fail "line 2 must be 'name: $s', got: $(sed -n '2p' "$f")"
    fi

    test_case "$s: description is a single quoted line"
    n=$(grep -c '^description:' "$f" || true)
    d=$(sed -n 's/^description: *"\(.*\)"$/\1/p' "$f")
    if [[ "$n" == "1" && -n "$d" ]]; then test_pass; else test_fail "need one double-quoted single-line description; got $n line(s): '$d'"; fi

    test_case "$s: registered in plugin.json"
    if jq -e --arg p "./skills/$s" '.skills[] | select(. == $p)' "$PLUGIN_JSON" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "add \"./skills/$s\" to the skills array"
    fi

    test_case "$s: credits the MIT source"
    if grep -qi "mattpocock/skills" "$f" && grep -qi "MIT" "$f"; then
        test_pass
    else
        test_fail "adapted work must name its source and licence"
    fi

    # The identifier is what gets surfaced and invoked, so that is what must be
    # ours. Ordinary English in a description is not a borrowed identifier —
    # "triage states" is the plain word for the thing, and stripping it would
    # cost discoverability to no benefit. Checked on the name line only.
    test_case "$s: the invocable name is ours, not the upstream one"
    if grep -qE '^name: *(grilling|writing-great-skills|to-tickets|triage)$' "$f"; then
        test_fail "upstream identifier used as this skill's name"
    else
        test_pass
    fi

    test_case "$s: stays advisory (no orchestrate.sh compliance contract needed)"
    if grep -q "orchestrate\.sh" "$f"; then
        test_fail "mentioning orchestrate.sh triggers the MANDATORY COMPLIANCE + PROHIBITED contract"
    else
        test_pass
    fi
done

PT="$PROJECT_ROOT/.claude/skills/skill-pressure-test/SKILL.md"
AU="$PROJECT_ROOT/.claude/skills/skill-authoring/SKILL.md"
WS="$PROJECT_ROOT/.claude/skills/skill-work-slicing/SKILL.md"
IN="$PROJECT_ROOT/.claude/skills/skill-intake/SKILL.md"

# ── skill-pressure-test ──────────────────────────────────────────────────────
# One question at a time is the whole method; batching makes it a questionnaire.
test_case "pressure-test: asks one question at a time"
if [[ -f "$PT" ]] && grep -qiE "one at a time|one question" "$PT"; then test_pass; else test_fail "must require one question at a time"; fi

# The load-bearing line: facts are the agent's job, decisions are the user's.
# This is the same split the intent contract's agency triad encodes.
test_case "pressure-test: looks up facts, puts decisions to the user"
if [[ -f "$PT" ]] && grep -qi "fact" "$PT" && grep -qiE "decision.*your|decisions are|yours" "$PT"; then
    test_pass
else
    test_fail "must distinguish facts it should look up from decisions only the user can make"
fi

test_case "pressure-test: offers a recommended answer with each question"
if [[ -f "$PT" ]] && grep -qiE "recommend" "$PT"; then test_pass; else test_fail "each question should carry a recommended answer"; fi

test_case "pressure-test: does not act before shared understanding is confirmed"
if [[ -f "$PT" ]] && grep -qiE "do not act|don't act|before .*confirm" "$PT"; then test_pass; else test_fail "must not start work until the user confirms"; fi

# ── skill-authoring ──────────────────────────────────────────────────────────
test_case "authoring: names predictability as the goal"
if [[ -f "$AU" ]] && grep -qi "predictab" "$AU"; then test_pass; else test_fail "the root virtue is predictability of process"; fi

test_case "authoring: requires checkable completion criteria"
if [[ -f "$AU" ]] && grep -qi "completion criteri" "$AU" && grep -qiE "checkable|can the agent tell" "$AU"; then
    test_pass
else
    test_fail "must require completion criteria the agent can actually evaluate"
fi

test_case "authoring: records the native explicit-invocation contract"
if [[ -f "$AU" ]] \
    && grep -q "disable-model-invocation: true" "$AU" \
    && grep -q '\.claude/skills/<name>/SKILL\.md' "$AU"; then
    test_pass
else
    test_fail "must require the native invocation gate and direct source loading for explicit command composition"
fi

test_case "authoring: points at the repo's own structural standard"
if [[ -f "$AU" ]] && grep -q "PLUGIN-ASSEMBLY-STANDARD" "$AU"; then test_pass; else test_fail "must reference docs/PLUGIN-ASSEMBLY-STANDARD.md rather than restating it"; fi

# ── skill-work-slicing ───────────────────────────────────────────────────────
test_case "work-slicing: slices vertically, not by layer"
if [[ -f "$WS" ]] && grep -qi "vertical" "$WS" && grep -qiE "not .*horizontal|NOT a horizontal" "$WS"; then
    test_pass
else
    test_fail "a slice must cut through every layer, not be one layer's worth of work"
fi

test_case "work-slicing: each slice declares what blocks it"
if [[ -f "$WS" ]] && grep -qi "block" "$WS"; then test_pass; else test_fail "slices must declare blocking edges"; fi

# bd is write-blocked on pending Dolt migrations, and the repo rule forbids
# migrating from a non-designated clone. The skill must degrade honestly rather
# than appear to file work it cannot file.
test_case "work-slicing: handles the bd write block without pretending to file"
if [[ -f "$WS" ]] && grep -q "bd" "$WS" && grep -qiE "write-blocked|writes are blocked|cannot write|ready-to-run" "$WS"; then
    test_pass
else
    test_fail "must state what happens when bd writes are unavailable and emit ready-to-run commands instead"
fi

test_case "work-slicing: does not tell anyone to run the bd migration"
if [[ -f "$WS" ]] && grep -qiE "do not run the migration|single.designated migrator|not migrate" "$WS"; then
    test_pass
else
    test_fail "the repo rule is that only the designated migrator migrates; the skill must not invite a second clone to do it"
fi

# ── skill-intake ─────────────────────────────────────────────────────────────
test_case "intake: treats a PR as an issue with attached code"
if [[ -f "$IN" ]] && grep -qiE "pull request|PR" "$IN" && grep -qi "issue" "$IN"; then test_pass; else test_fail "must cover PRs on the same state machine as issues"; fi

test_case "intake: defines states and the moves between them"
if [[ -f "$IN" ]] && grep -qiE "needs-info|needs-triage|state" "$IN"; then test_pass; else test_fail "must define the triage states"; fi

test_case "intake: routes to this repo's own trackers, not an invented one"
if [[ -f "$IN" ]] && grep -qE "gh issue|\bbd\b" "$IN"; then test_pass; else test_fail "must use gh and/or bd, the trackers this repo actually has"; fi

test_summary
