#!/usr/bin/env bash
# Council seats are told to read only what the review needs.
#
# Codex and agy seats spent most of their fresh input tokens listing and reading
# the repository on every review. The seat prompt now limits reading to the
# files and diffs the council supplies, plus a cited file opened to check a
# specific finding. The instruction is fixed text ahead of the task-specific
# blocks, so it stays in the cached prompt prefix.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Council bounded seat reading"

# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/council.sh"
COUNCIL_GOAL=review COUNCIL_DOMAIN=code COUNCIL_STYLE=balanced COUNCIL_DEPTH=quick
COUNCIL_RUN_DIR="$(mktemp -d "${TEST_TMP_DIR:-/tmp}/bounded.XXXXXX")"
LINE='Do not list, search or explore the rest of the repository.'

prompt_for() { COUNCIL_TASK="$1" council_prompt_for_member "$2" "$3" 2>/dev/null; }

test_case "every phase's seat prompt limits reading to supplied and cited files"
missing=""
for phase in independent-advice critique revision chair-synthesis; do
    p="$(prompt_for "Review chunk 1" backend-architect "$phase")"
    grep -qF "$LINE" <<< "$p" || missing+="$phase "
done
if [[ -z "$missing" ]]; then test_pass; else test_fail "missing in: $missing"; fi

test_case "the instruction comes before the task-specific blocks"
p="$(prompt_for "Review chunk 1" backend-architect independent-advice)"
rule_line="$(grep -nF "$LINE" <<< "$p" | cut -d: -f1)"
task_line="$(grep -n '^COUNCIL_TASK$' <<< "$p" | head -1 | cut -d: -f1)"
verdict_line="$(grep -n '^End your response with a single line' <<< "$p" | cut -d: -f1)"
if [[ -n "$rule_line" && "$rule_line" -gt "$task_line" && "$rule_line" -lt "$verdict_line" ]] &&
   ! grep -q 'Review chunk 1' <<< "$(sed -n "${rule_line},\$p" <<< "$p" | head -3)"; then
    test_pass
else
    test_fail "rule=$rule_line task=$task_line verdict=$verdict_line"
fi

test_case "the instruction text is identical across chunks and personas"
a="$(prompt_for "Review chunk 1" backend-architect independent-advice | grep -F "$LINE")"
b="$(prompt_for "Review chunk 17 of something else" security-auditor critique | grep -F "$LINE")"
if [[ -n "$a" && "$a" == "$b" ]]; then test_pass; else test_fail "a=[$a] b=[$b]"; fi

test_case "OCTOPUS_COUNCIL_BOUNDED_READING=0 drops the instruction"
p="$(OCTOPUS_COUNCIL_BOUNDED_READING=0 prompt_for "Review" backend-architect independent-advice)"
if [[ -n "$p" ]] && ! grep -qF "$LINE" <<< "$p"; then
    test_pass
else
    test_fail "instruction still present"
fi

test_summary
