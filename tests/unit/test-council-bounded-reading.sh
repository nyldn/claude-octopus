#!/usr/bin/env bash
# Council seats are told to read only what the review needs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Council bounded seat reading"

# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/council.sh"
unset OCTOPUS_COUNCIL_BOUNDED_READING
COUNCIL_GOAL=review COUNCIL_DOMAIN=code COUNCIL_STYLE=balanced COUNCIL_DEPTH=quick
COUNCIL_RUN_DIR="$TEST_TMP_DIR/bounded"
mkdir -p "$COUNCIL_RUN_DIR"/{responses,critiques,revisions}
printf '%s\n' 'Research fixture' > "$COUNCIL_RUN_DIR/research.md"
printf '%s\n' 'Attached context fixture' > "$COUNCIL_RUN_DIR/attachment.md"
printf '%s\n' 'Peer response fixture' > "$COUNCIL_RUN_DIR/responses/01-code-reviewer.md"
printf '%s\n' 'Peer critique fixture' > "$COUNCIL_RUN_DIR/critiques/01-code-reviewer.md"
printf '%s\n' 'Peer revision fixture' > "$COUNCIL_RUN_DIR/revisions/01-code-reviewer.md"
COUNCIL_CONTEXT_FILES=("$COUNCIL_RUN_DIR/attachment.md")
LINE='Do not list, search or explore the rest of the repository.'

prompt_for() { COUNCIL_TASK="$1" council_prompt_for_member "$2" "$3" 2>/dev/null; }

test_case "every phase's seat prompt limits reading to supplied and cited files"
missing=""
for phase in independent-advice cross-critique revision-after-critique chair-synthesis; do
    p="$(prompt_for "Review chunk 1" backend-architect "$phase")"
    grep -qF "$LINE" <<< "$p" || missing+="$phase "
done
if [[ -z "$missing" ]]; then test_pass; else test_fail "missing in: $missing"; fi

test_case "the instruction follows the task and precedes research, attached files, peer responses and critiques"
p="$(prompt_for "Review chunk 1" backend-architect revision-after-critique)"
if awk -v rule="$LINE" '
    $0 == "COUNCIL_TASK" { task = NR }
    index($0, rule) { reading = NR }
    $0 == "Research fixture" { research = NR }
    $0 == "Attached context fixture" { attachment = NR }
    $0 == "Peer response fixture" { response = NR }
    $0 == "Peer critique fixture" { critique = NR }
    END {
        exit !(task && task < reading && reading < research && reading < attachment &&
               reading < response && reading < critique)
    }
' <<< "$p"; then
    test_pass
else
    test_fail "the reading instruction or a populated context block was missing or out of order"
fi

test_case "the instruction text is identical across chunks and personas"
a="$(prompt_for "Review chunk 1" backend-architect independent-advice | grep -F "$LINE" || true)"
b="$(prompt_for "Review chunk 17 of something else" security-auditor cross-critique | grep -F "$LINE" || true)"
if [[ -n "$a" && "$a" == "$b" ]]; then test_pass; else test_fail "a=[$a] b=[$b]"; fi

test_case "OCTOPUS_COUNCIL_BOUNDED_READING=0 drops the instruction"
p="$(OCTOPUS_COUNCIL_BOUNDED_READING=0 prompt_for "Review" backend-architect independent-advice)"
if grep -qFx 'Attached context fixture' <<< "$p" && ! grep -qF "$LINE" <<< "$p"; then
    test_pass
else
    test_fail "instruction still present"
fi

test_summary
