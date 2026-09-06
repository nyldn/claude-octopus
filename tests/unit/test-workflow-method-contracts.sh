#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -P "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../helpers/test-framework.sh
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Workflow method adaptation contracts"

ARCH="$PROJECT_ROOT/.claude/skills/skill-architecture/SKILL.md"
TDD="$PROJECT_ROOT/.claude/skills/skill-tdd/SKILL.md"
DEBUG="$PROJECT_ROOT/.claude/skills/skill-debug/SKILL.md"
PLAN="$PROJECT_ROOT/.claude/skills/skill-writing-plans/SKILL.md"
SLICE="$PROJECT_ROOT/.claude/skills/skill-work-slicing/SKILL.md"
DOMAIN="$PROJECT_ROOT/skills/blocks/domain-modeling.md"
CASES="$PROJECT_ROOT/data/evals/workflow-skill-cases.json"

test_case "architecture uses evidence, deletion test, caller example, and host-only default"
if grep -qi 'recent churn' "$ARCH" &&
   grep -qi 'concrete caller' "$ARCH" &&
   grep -qi 'zero additional provider dispatches' "$ARCH" &&
   grep -qi 'correlated alternatives' "$ARCH" &&
   grep -qi 'unknown family means unknown independence' "$ARCH"; then
    test_pass
else
    test_fail "architecture simplification or competing-design contract is incomplete"
fi

test_case "routine TDD is host-native and consolidation requires mutant evidence"
if grep -qi 'zero additional provider dispatches' "$TDD" &&
   # shellcheck disable=SC2016 # Match a literal Markdown field name.
   grep -q '`mutant`' "$TDD" && grep -qi 'five isolated runs' "$TDD" &&
   ! grep -q 'orchestrate\.sh' "$TDD"; then
    test_pass
else
    test_fail "TDD still mandates dispatch or lacks behavior-led consolidation"
fi

test_case "host-native debug and TDD do not carry Codex enforced-dispatch metadata"
DEBUG_CODEX="$PROJECT_ROOT/skills/skill-debug/SKILL.md"
TDD_CODEX="$PROJECT_ROOT/skills/skill-tdd/SKILL.md"
if ! grep -q '^execution_mode: enforced$' "$DEBUG" &&
   ! grep -q '^execution_mode: enforced$' "$TDD" &&
   ! grep -q 'This generated Codex skill preserves an enforced workflow contract' "$DEBUG_CODEX" &&
   ! grep -q 'This generated Codex skill preserves an enforced workflow contract' "$TDD_CODEX"; then
    test_pass
else
    test_fail "host-native methods still advertise an enforced Codex dispatch contract"
fi

test_case "debugging requires the symptom, bounded replay, and original scenario"
if grep -qi "user's observable symptom" "$DEBUG" &&
   grep -qi 'synchronization barrier' "$DEBUG" &&
   grep -qi 'original scenario' "$DEBUG" &&
   grep -qi 'inconclusive' "$DEBUG"; then
    test_pass
else
    test_fail "debug feedback-loop evidence is incomplete"
fi

test_case "domain definitions separate transport, access, billing, and contributions"
if grep -q '| provider |' "$DOMAIN" && grep -q '| entitlement |' "$DOMAIN" &&
   grep -q '| billing mode |' "$DOMAIN" && grep -q '| contribution |' "$DOMAIN" &&
   grep -qi 'does not prove' "$DOMAIN"; then
    test_pass
else
    test_fail "shared definitions collapse distinct routing evidence"
fi

test_case "planning records decision dependencies and safe claim semantics"
if grep -qi 'dependency graph' "$PLAN" && grep -qi 'atomic operation' "$PLAN" &&
   grep -qi 'read ownership back' "$PLAN" && grep -qi 'fabricate IDs' "$PLAN" &&
   grep -qi 'dependency cycle' "$SLICE"; then
    test_pass
else
    test_fail "decision dependency or claim rules are incomplete"
fi

test_case "prototype is explicit, bounded, and registered"
prototype="$PROJECT_ROOT/.claude/skills/skill-prototype/SKILL.md"
if grep -q '^disable-model-invocation: true$' "$prototype" &&
   grep -qi 'deadline' "$prototype" && grep -qi 'read-only plan mode' "$prototype" &&
   jq -e '.skills | index("./skills/skill-prototype")' "$PROJECT_ROOT/.claude-plugin/plugin.json" >/dev/null; then
    test_pass
else
    test_fail "prototype invocation, budget, or registration contract is missing"
fi

test_case "portable acceptance fixture covers every approved case exactly once"
if jq -e '(.cases | length) == 38 and
          ([.cases[].id] | unique | length) == 38 and
          ([.cases[].id] | index("F01")) != null and
          ([.cases[].id] | index("R8-06")) != null and
          ([.cases[].id] | index("X04")) != null' "$CASES" >/dev/null; then
    test_pass
else
    test_fail "acceptance scenario fixture is incomplete or duplicated"
fi

test_case "test consolidation records comparable samples and keeps distinct coverage"
ledger="$PROJECT_ROOT/data/evals/workflow-test-consolidation.json"
if jq -e '.removed_tests == [] and .decision == "keep all existing tests" and
          (.measurements | length) == 3 and
          all(.measurements[]; (.baseline_ms | length) == 5 and
                               (.candidate_ms | length) == 5 and
                               (.review_trigger | type) == "boolean")' "$ledger" >/dev/null; then
    test_pass
else
    test_fail "consolidation decision lacks measured behavior evidence"
fi

test_case "shared references are shipped source files, not generated skill edits"
missing=""
for file in architecture-simplification.md debug-feedback-loop.md domain-modeling.md; do
    [[ -f "$PROJECT_ROOT/skills/blocks/$file" ]] || missing="$missing $file"
done
if [[ -z "$missing" ]]; then test_pass; else test_fail "missing references:$missing"; fi

test_summary
