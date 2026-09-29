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

TEST_ROOT="$(mktemp -d)"
HOME="$TEST_ROOT/home"
RESULTS_DIR="$TEST_ROOT/results"
LOGS_DIR="$TEST_ROOT/logs"
OCTOPUS_RESEARCH_ROOT="$TEST_ROOT/research-runs"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$HOME" "$RESULTS_DIR" "$LOGS_DIR" "$TEST_ROOT/workspace/src"
WORKSPACE="$(cd "$TEST_ROOT/workspace" && pwd -P)"
printf 'import { run } from "./run";\nexport const handler = run;\n' > "$WORKSPACE/src/app.ts"
PROJECT_ROOT="$WORKSPACE"

CALLS="$TEST_ROOT/agent-calls"
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
        cat "$FIRST_REPLY"
    else
        printf '%s' "$2" > "$REPAIR_PROMPT"
        cat "$REPAIR_REPLY"
    fi
}

GOOD_LINE='The app exports its handler from run (src/app.ts:2).'
ELIDED_LINE='The app exports its handler from run (:2).'

run_scenario() {
    local name="$1" first="$2" repair="$3"
    printf '%s\n' "$first" > "$FIRST_REPLY"
    printf '%s\n' "$repair" > "$REPAIR_REPLY"
    rm -f "$CALLS" "$REPAIR_PROMPT"
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
    OCTOPUS_RESEARCH_EVIDENCE=true
    OCTOPUS_RESEARCH_RUN_ID="run-$name"
    OCTOPUS_RESEARCH_RESUME=false
    research_run_begin "$task_group" "Where does the app export its handler?" "quick" >/dev/null 2>&1
    research_collect_sources "$task_group" >/dev/null 2>&1
    scenario_status=0
    synthesize_probe_results "$task_group" "Where does the app export its handler?" 1 >/dev/null 2>&1 || scenario_status=$?
    agent_calls=$(wc -l < "$CALLS" | tr -d ' ')
    unset OCTOPUS_RESEARCH_EVIDENCE OCTOPUS_RESEARCH_RUN_ID OCTOPUS_RESEARCH_RESUME
    unset RESEARCH_RUN_DIR RESEARCH_RUN_ID RESEARCH_TASK_GROUP RESEARCH_PROMPT RESEARCH_INTENSITY
}

run_scenario "fixed" "$ELIDED_LINE" "$GOOD_LINE"

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

run_scenario "clean" "$GOOD_LINE" "$GOOD_LINE"

test_case "a synthesis that passes verification is published without a repair call"
if [[ "$scenario_status" -eq 0 && "$agent_calls" -eq 1 && -f "$synthesis_file" ]]; then
    test_pass
else
    test_fail "expected no repair for a passing synthesis (status=$scenario_status calls=$agent_calls)"
fi

test_summary
