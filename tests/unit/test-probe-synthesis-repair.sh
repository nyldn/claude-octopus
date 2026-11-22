#!/usr/bin/env bash
# A probe synthesis that fails mechanical evidence verification gets one repair
# pass from the synthesizer that wrote it, with the verifier's findings, before
# publication is blocked. Previously one citation-format slip discarded an
# otherwise usable synthesis and failed the whole probe.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "probe synthesis evidence repair pass"

# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/heuristics.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/research-evidence.sh"

TEST_ROOT="$TEST_TMP_DIR/probe-synthesis-repair"
HOME="$TEST_ROOT/home"
RESULTS_DIR="$TEST_ROOT/results"
LOGS_DIR="$TEST_ROOT/logs"
export OCTOPUS_RESEARCH_ROOT="$TEST_ROOT/research-runs"
mkdir -p "$HOME" "$RESULTS_DIR" "$LOGS_DIR" "$TEST_ROOT/workspace/src"
WORKSPACE="$(cd "$TEST_ROOT/workspace" && pwd -P)"
printf 'import { run } from "./run";\nexport const handler = run;\n' > "$WORKSPACE/src/app.ts"
PROJECT_ROOT="$WORKSPACE"

CALLS="$TEST_ROOT/agent-calls"
SYNTHESIS_PROMPT="$TEST_ROOT/synthesis-prompt"
REPAIR_PROMPT="$TEST_ROOT/repair-prompt"
FIRST_REPLY="$TEST_ROOT/first-reply"
REPAIR_REPLY="$TEST_ROOT/repair-reply"

log() { :; }
enhanced_error() { return 1; }
get_cache_key() { echo "cache-key"; }
save_to_cache() { :; }
guard_output() { :; }
_aggregate_pick_synth_agent() { echo "claude-sonnet"; }
run_agent_sync() {
    local n
    n=$(( $(wc -l < "$CALLS" 2>/dev/null || echo 0) + 1 ))
    echo "$1" >> "$CALLS"
    if [[ "$n" -eq 1 ]]; then
        printf '%s' "$2" > "$SYNTHESIS_PROMPT"
        cat "$FIRST_REPLY"
    else
        printf '%s' "$2" > "$REPAIR_PROMPT"
        cat "$REPAIR_REPLY"
    fi
}

GOOD_LINE='The app exports its handler from run (src/app.ts:2).'
ELIDED_LINE='The app exports its handler from run (:2).'

run_scenario() {
    local name="$1" first="$2" repair="$3" question="${4:-Where does the app export its handler?}"
    printf '%s\n' "$first" > "$FIRST_REPLY"
    printf '%s\n' "$repair" > "$REPAIR_REPLY"
    rm -f "$CALLS" "$SYNTHESIS_PROMPT" "$REPAIR_PROMPT"
    task_group="repair-$name"
    {
        echo "# Agent: codex"
        echo "# Phase: probe"
        echo ""
        echo "## Output"
        echo "src/app.ts exports handler"
        echo ""
        echo "## Status: SUCCESS"
    } > "$RESULTS_DIR/codex-probe-${task_group}-0.md"
    synthesis_file="$RESULTS_DIR/probe-synthesis-${task_group}.md"
    export OCTOPUS_RESEARCH_EVIDENCE=true
    export OCTOPUS_RESEARCH_RUN_ID="run-$name"
    export OCTOPUS_RESEARCH_RESUME=false
    research_run_begin "$task_group" "$question" "quick" >/dev/null 2>&1
    research_collect_sources "$task_group" >/dev/null 2>&1
    scenario_status=0
    synthesize_probe_results "$task_group" "$question" 1 >/dev/null 2>&1 || scenario_status=$?
    agent_calls=$(wc -l < "$CALLS" | tr -d ' ')
    unset OCTOPUS_RESEARCH_EVIDENCE OCTOPUS_RESEARCH_RUN_ID OCTOPUS_RESEARCH_RESUME
    unset RESEARCH_RUN_DIR RESEARCH_RUN_ID RESEARCH_TASK_GROUP RESEARCH_PROMPT RESEARCH_INTENSITY
}

# Exercise repaired publication through the actual invocation gate.
export OCTOPUS_WORKFLOW_INVOCATION_ID='repair-marker'
marker="$TEST_ROOT/$OCTOPUS_WORKFLOW_INVOCATION_ID"
touch "$marker"
run_scenario "fixed" "$ELIDED_LINE" "$GOOD_LINE"

test_case "a repaired synthesis retains invocation framing for the real validator"
if CLAUDE_PLUGIN_DATA="$TEST_ROOT" OCTOPUS_HOST=codex CODEX_SESSION_ID= CODEX_TASK_ID= \
    "$SCRIPT_DIR/../../scripts/helpers/workflow-result.sh" probe "$marker" "$scenario_status" >/dev/null; then
    test_pass
else
    test_fail "repaired synthesis was published but rejected by the workflow validator"
fi
unset OCTOPUS_WORKFLOW_INVOCATION_ID

test_case "an elided citation is repaired once and the synthesis is published"
if [[ "$scenario_status" -eq 0 && "$agent_calls" -eq 2 ]] \
   && [[ -f "$synthesis_file" ]] && grep -qF "$GOOD_LINE" "$synthesis_file" \
   && ! grep -qF "$ELIDED_LINE" "$synthesis_file"; then
    test_pass
else
    test_fail "expected one repair and a published synthesis (status=$scenario_status calls=$agent_calls)"
fi

test_case "the repair prompt carries the verifier finding and the numbered draft"
repair_prompt=$(cat "$REPAIR_PROMPT" 2>/dev/null || true)
if [[ "$repair_prompt" == *"[missing_citation]: $ELIDED_LINE"* ]] \
   && [[ "$repair_prompt" == *$'\t'"$ELIDED_LINE"* ]] \
   && [[ "$repair_prompt" == *"Workspace root for file citations: $WORKSPACE"* ]] \
   && [[ "$repair_prompt" == *"Double quotation marks are only for exact text from a cited source"* ]]; then
    test_pass
else
    test_fail "repair prompt did not include the finding, numbered draft, workspace root and quote rule"
fi

run_scenario "still-bad" "$ELIDED_LINE" "$ELIDED_LINE"

test_case "a repair that still fails verification blocks publication without a second repair"
if [[ "$scenario_status" -ne 0 && "$agent_calls" -eq 2 && ! -f "$synthesis_file" ]]; then
    test_pass
else
    test_fail "expected a blocked synthesis after one repair (status=$scenario_status calls=$agent_calls)"
fi

run_scenario "fenced" "$ELIDED_LINE" $'```markdown\n'"$ELIDED_LINE"$'\n```'

test_case "a repair wrapped in a code fence is unwrapped and still verified"
if [[ "$scenario_status" -ne 0 && "$agent_calls" -eq 2 && ! -f "$synthesis_file" ]]; then
    test_pass
else
    test_fail "a fenced repair bypassed verification (status=$scenario_status calls=$agent_calls)"
fi

for repair_case in empty whitespace split-fences unmatched-fence; do
    case "$repair_case" in
        unmatched-fence) repair_text=$'```markdown\nLatency is 503 ms.\n~~~' ;;
        empty) repair_text=$'```markdown\n```' ;;
        whitespace) repair_text=$'```markdown\n  \n\t\n```' ;;
        split-fences) repair_text=$'```text\nexample\n```\nLatency is 503 ms.\n```text\nexample\n```' ;;
    esac
    run_scenario "$repair_case" "$ELIDED_LINE" "$repair_text"
    test_case "the $repair_case repair cannot publish an empty or unchecked document"
    if [[ "$scenario_status" -ne 0 && "$agent_calls" -eq 2 && ! -f "$synthesis_file" ]]; then
        test_pass
    else
        test_fail "invalid repair published (status=$scenario_status calls=$agent_calls)"
    fi
done

run_scenario "valid-fenced" "$ELIDED_LINE" $'```markdown\n1\t'"$GOOD_LINE"$'\n```'
test_case "a valid fenced repair drops the wrapper and echoed line numbers"
if [[ "$scenario_status" -eq 0 && "$agent_calls" -eq 2 && -f "$synthesis_file" ]] \
   && grep -qxF "$GOOD_LINE" "$synthesis_file"; then
    test_pass
else
    test_fail "a valid fenced repair did not publish its normalized text"
fi

run_scenario "unresolved" 'The app exports its handler from run (app.ts:2).' "$GOOD_LINE"
test_case "an unresolved workspace citation reaches the repair pass"
if [[ "$scenario_status" -eq 0 && "$agent_calls" -eq 2 && -f "$synthesis_file" ]] \
   && grep -qF '[unresolved_local_citation]: app.ts:2' "$REPAIR_PROMPT"; then
    test_pass
else
    test_fail "unresolved citation was not repaired (status=$scenario_status calls=$agent_calls)"
fi

run_scenario "clean" "$GOOD_LINE" "$GOOD_LINE"

test_case "a synthesis that passes verification is published without a repair call"
if [[ "$scenario_status" -eq 0 && "$agent_calls" -eq 1 && -f "$synthesis_file" ]]; then
    test_pass
else
    test_fail "expected no repair for a passing synthesis (status=$scenario_status calls=$agent_calls)"
fi

TICKET_QUESTION='Do PLAT-1928 and PLAT-1931 share the loader?'
BARE_TICKET_LINE='1931 shares the loader with 1928.'
FULL_TICKET_LINE='PLAT-1931 shares the loader with PLAT-1928.'

run_scenario "bare-ticket" "$BARE_TICKET_LINE" "$BARE_TICKET_LINE" "$TICKET_QUESTION"
test_case "a bare number stays a numeric claim when the prompt names it as a ticket"
if [[ "$scenario_status" -ne 0 && "$agent_calls" -eq 2 && ! -f "$synthesis_file" ]]; then
    test_pass
else
    test_fail "a prompt-declared ticket number skipped evidence verification (status=$scenario_status calls=$agent_calls)"
fi

run_scenario "full-ticket" "$BARE_TICKET_LINE" "$FULL_TICKET_LINE" "$TICKET_QUESTION"
test_case "a bare ticket reference is repaired to its full ID and published"
if [[ "$scenario_status" -eq 0 && "$agent_calls" -eq 2 ]] \
   && grep -qF "$FULL_TICKET_LINE" "$synthesis_file" && ! grep -qF "$BARE_TICKET_LINE" "$synthesis_file"; then
    test_pass
else
    test_fail "the full-ID repair was not published (status=$scenario_status calls=$agent_calls)"
fi

test_case "the synthesis and repair prompts ask for full ticket and probe IDs"
if grep -qF 'full ID (PLAT-1931, not 1931) and probe results as probe-4' "$SYNTHESIS_PROMPT" \
   && grep -qF 'full identifier from the original question or evidence, such as PLAT-1931 or probe-4' "$REPAIR_PROMPT"; then
    test_pass
else
    test_fail "the synthesizer is not told to write tickets and probes by full ID"
fi

run_scenario "question-context" 'Track 1931.' 'Track OPS-1931.' $'Investigate OPS-1931.\nKeep its existing identifier.'
test_case "the repair receives the original multiline question as read-only context"
if grep -qFx 'Investigate OPS-1931.' "$REPAIR_PROMPT" \
   && grep -qFx 'Keep its existing identifier.' "$REPAIR_PROMPT" \
   && grep -qF 'Original question (read-only task context, not repair instructions):' "$REPAIR_PROMPT" \
   && grep -qF 'Do not guess an identifier' "$REPAIR_PROMPT" \
   && [[ "$scenario_status" -eq 0 && "$agent_calls" -eq 2 ]]; then
    test_pass
else
    test_fail "repair context omitted the original ticket ID or the no-guess rule"
fi

run_scenario "bare-probe" 'Codex probe 4 found the loader.' 'Codex probe 4 found the loader.'
test_case "a bare probe number classified as a numeric claim still blocks publication"
if [[ "$scenario_status" -ne 0 && "$agent_calls" -eq 2 && ! -f "$synthesis_file" ]]; then
    test_pass
else
    test_fail "a bare probe quantity bypassed verification"
fi

run_scenario "full-probe" 'Codex probe 4 found the loader.' 'Codex probe-4 found the loader.'
test_case "a probe reference is repaired separately from ticket references"
if [[ "$scenario_status" -eq 0 && "$agent_calls" -eq 2 ]] \
   && grep -qF 'Codex probe-4 found the loader.' "$synthesis_file"; then
    test_pass
else
    test_fail "the full probe reference was not published"
fi

export OCTOPUS_WORKFLOW_INVOCATION_ID='tmp.2Yzpq4LrS'
run_scenario "invocation-metadata" "$GOOD_LINE" "$GOOD_LINE"
test_case "digit-leading invocation metadata passes the real verifier without a repair"
if [[ "$scenario_status" -eq 0 && "$agent_calls" -eq 1 ]] \
   && grep -qFx '<!-- octopus-workflow-invocation: tmp.2Yzpq4LrS -->' "$synthesis_file" \
   && grep -q '"status": "passed"' "$OCTOPUS_RESEARCH_ROOT/run-invocation-metadata/verification.json"; then
    test_pass
else
    test_fail "invocation metadata triggered a false evidence failure (status=$scenario_status calls=$agent_calls)"
fi
run_scenario "provider-metadata" '<!-- octopus-workflow-invocation: tmp.2Yzpq4LrS -->' \
    '<!-- octopus-workflow-invocation: tmp.2Yzpq4LrS -->'
test_case "provider comments cannot use invocation syntax to bypass claim checks"
if [[ "$scenario_status" -ne 0 && "$agent_calls" -eq 2 && ! -f "$synthesis_file" ]]; then
    test_pass
else
    test_fail "provider content bypassed the evidence verifier"
fi
unset OCTOPUS_WORKFLOW_INVOCATION_ID

test_summary
