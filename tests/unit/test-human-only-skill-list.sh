#!/usr/bin/env bash
# The human-only skill list must be derived from skill frontmatter, not retyped.
#
# Six skills declare `invocation: human_only`. The only thing that acts on that
# intent is a prose reminder injected by hooks/context-reinforcement.sh, and its
# list was hardcoded — it named five, omitting octopus-ui-ux-design, so a skill
# that declared itself human-only was never reinforced as such.
#
# Note what this is NOT: `disable-model-invocation: true` would be the native
# mechanism, but four of these skills are named in command bodies
# (commands/parallel.md, factory.md, research.md, security.md) and are reached
# by the model on the user's behalf when it runs those commands. Disabling model
# invocation would break those routes. "Human-only" here means "do not fire from
# prompt-keyword auto-routing", which is advisory by nature — so the fix is to
# stop the advisory drifting from the declaration, not to change mechanisms.
set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -P "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Human-only skill list stays in sync with frontmatter"

HOOK="$PROJECT_ROOT/hooks/context-reinforcement.sh"

# The declared set: every skill whose frontmatter asks not to be auto-triggered.
declared=$(grep -l "^invocation: human_only" "$PROJECT_ROOT"/.claude/skills/*/SKILL.md 2>/dev/null \
    | while IFS= read -r f; do sed -n 's/^name: *//p' "$f" | head -1; done | sort)

test_case "at least one skill declares invocation: human_only"
if [[ -n "$declared" ]]; then
    test_pass
else
    test_fail "no skill declares human_only — this suite would be vacuous; delete it or restore the declarations"
fi

test_case "the hook emits a human-only line"
emitted=$(echo '{}' | bash "$HOOK" 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d['hookSpecificOutput']['additionalContext'])
except Exception:
    pass
" 2>/dev/null || true)
if grep -q "Human-only skills" <<< "$emitted"; then
    test_pass
else
    test_fail "hook output carries no human-only line; got: $(head -c 200 <<< "$emitted")"
fi

# The real assertion. Every declaring skill must appear in what the hook emits.
# The hook lists exact skill names, so both directions can be checked precisely.
# Substring matching would have hidden the original bug: "deep-research" reads
# plausibly but matches no skill, because that skill is named octopus-research.
hook_names=$(grep -o "Human-only skills[^:]*: *[^.]*" <<< "$emitted" \
    | sed 's/.*: *//' | tr ',' '\n' | tr -d ' ' | grep -v '^$' | sort)

test_case "every skill declaring human_only is named in the hook output"
missing=$(comm -23 <(echo "$declared") <(echo "$hook_names"))
if [[ -z "$missing" ]]; then
    test_pass
else
    test_fail "declared human-only but absent from the hook reminder: $(echo $missing)"
fi

# The other direction: a name in the hook that no skill declares is either a
# typo or an entry that outlived its skill.
test_case "the hook names no skill that stopped declaring human_only"
stray=$(comm -13 <(echo "$declared") <(echo "$hook_names"))
if [[ -z "$stray" ]]; then
    test_pass
else
    test_fail "hook names skills that do not declare human_only: $(echo $stray)"
fi

test_case "the hook uses real skill names, not directory names"
bad=""
while IFS= read -r n; do
    [[ -n "$n" ]] || continue
    grep -rqx "name: $n" "$PROJECT_ROOT"/.claude/skills/*/SKILL.md || bad="$bad $n"
done <<< "$hook_names"
if [[ -z "$bad" ]]; then
    test_pass
else
    test_fail "not resolvable to any skill's frontmatter name:$bad"
fi

# The key must stay meaningful. build-factory-skills.sh strips `invocation` from
# generated output, so nothing downstream reads it — this suite is the only
# thing that makes the declaration load-bearing.
test_case "the declaration is documented as advisory, not as a native gate"
if grep -q "disable-model-invocation" "$HOOK" || grep -qi "advisory\|auto-trigger" "$HOOK"; then
    test_pass
else
    test_fail "the hook should state what human-only actually enforces, so the next reader does not assume it is a hard gate"
fi

test_summary
