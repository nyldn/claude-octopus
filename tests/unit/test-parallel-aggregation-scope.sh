#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Parallel aggregation task scope"
source "${AGGREGATION_LIB_ROOT:-$PROJECT_ROOT}/scripts/lib/error-tracking.sh"
source "${AGGREGATION_LIB_ROOT:-$PROJECT_ROOT}/scripts/lib/agent-spec.sh"
export WORKSPACE_DIR="$TEST_TMP_DIR/workspace" OCTOPUS_RUN_ID=aggregation-scope
RESULTS_DIR="$WORKSPACE_DIR/results"
mkdir -p "$RESULTS_DIR"
current="$RESULTS_DIR/codex-t1.md"
old="$RESULTS_DIR/codex-old-t1.md"
printf '## Output\nCURRENT_IMPLEMENTATION\n## Status: SUCCESS\n' > "$current"
printf '## Output\nUNRELATED_EARLIER_IMPLEMENTATION\n## Status: SUCCESS\n' > "$old"
write_agent_status codex ok 10 10 '' 1 "$old"
write_agent_status codex ok 10 10 '' 1 "$current"
tasks="$(jq -nc --arg file "$current" '[{id:"t1",output_file:$file}]')"
log() { :; }
guard_output() { :; }
rank_results_by_signals() { printf '%s\n%s\n' "$old" "$current"; }
score_result_file() { echo 80; }
DRY_RUN=false TIMEOUT=1 GREEN='' NC=''
for implementation in parallel heuristics; do
    source "${AGGREGATION_LIB_ROOT:-$PROJECT_ROOT}/scripts/lib/parallel.sh"
    [[ "$implementation" == parallel ]] || source "${AGGREGATION_LIB_ROOT:-$PROJECT_ROOT}/scripts/lib/heuristics.sh"
    _aggregate_pick_synth_agent() { :; }
    test_case "$implementation aggregation includes only exact current result paths"
    rm -f "$RESULTS_DIR"/aggregate-*.md
    aggregate_results '' '' "$tasks" > /dev/null
    content="$(cat "$RESULTS_DIR"/aggregate-*.md)"
    if [[ "$content" == *CURRENT_IMPLEMENTATION* && "$content" != *UNRELATED_EARLIER* ]]; then
        test_pass
    else
        test_fail "earlier same-provider task entered aggregation: $content"
    fi
    test_case "$implementation empty task scope cannot fall back to earlier outputs"
    rm -f "$RESULTS_DIR"/aggregate-*.md
    aggregate_results '' '' '[]' > /dev/null
    content="$(cat "$RESULTS_DIR"/aggregate-*.md)"
    if [[ "$content" == *'Total Results: 0'* && "$content" != *IMPLEMENTATION* ]]; then
        test_pass
    else
        test_fail "empty current task list included stale results: $content"
    fi
done

test_case "parallel executor passes attempted task identities even when spawning fails"
source "${AGGREGATION_LIB_ROOT:-$PROJECT_ROOT}/scripts/lib/parallel.sh"
AVAILABLE_AGENTS=codex SUPPORTS_DISABLE_CRON_ENV=false MAX_PARALLEL=1
spawn_agent_capture_pid() { return 1; }
aggregate_results() { printf '%s' "${3:-null}" > "$TEST_TMP_DIR/aggregation-tasks.json"; }
printf '{"tasks":[{"id":"t1","agent":"codex","prompt":"implement"}]}' > "$TEST_TMP_DIR/tasks.json"
parallel_execute "$TEST_TMP_DIR/tasks.json" > "$TEST_TMP_DIR/parallel.log" 2>&1 && rc=0 || rc=$?
if [[ "$rc" == 1 ]] && jq -e --arg file "$current" \
    '. == [{id:"t1",output_file:$file}]' "$TEST_TMP_DIR/aggregation-tasks.json" > /dev/null; then
    test_pass
else
    test_fail "executor lost attempted task scope, exit=$rc"
fi
test_case "a failed repeated spawn cannot retain an earlier output at the same path"
if [[ ! -e "$current" ]]; then
    test_pass
else
    test_fail "failed spawn retained a previous answer at its current task path"
fi
test_case "legacy Opus fast alias uses the normalized dispatch result path"
AVAILABLE_AGENTS=claude-opus-fast
printf '{"tasks":[{"id":"t2","agent":"claude-opus-fast","prompt":"implement"}]}' > "$TEST_TMP_DIR/tasks.json"
parallel_execute "$TEST_TMP_DIR/tasks.json" > "$TEST_TMP_DIR/parallel-alias.log" 2>&1 && rc=0 || rc=$?
if [[ "$rc" == 1 ]] && jq -e --arg file "$RESULTS_DIR/claude-opus-t2.md" \
    '.[0].output_file == $file' "$TEST_TMP_DIR/aggregation-tasks.json" > /dev/null; then
    test_pass
else
    test_fail "aggregation expected a different path than the normalized dispatcher"
fi
test_case "dry-run preserves previous outputs"
AVAILABLE_AGENTS=codex DRY_RUN=true
spawn_agent() { :; }
printf 'preserve previous answer\n' > "$current"
printf '{"tasks":[{"id":"t1","agent":"codex","prompt":"preview"}]}' > "$TEST_TMP_DIR/tasks.json"
parallel_execute "$TEST_TMP_DIR/tasks.json" > "$TEST_TMP_DIR/parallel-preview.log" 2>&1
if [[ "$(cat "$current")" == 'preserve previous answer' ]]; then
    test_pass
else
    test_fail "preview removed an existing result"
fi
test_case "failure to remove an old output fails closed before dispatch"
DRY_RUN=false
mkdir "$RESULTS_DIR/codex-blocked.md"
spawn_agent_capture_pid() { touch "$TEST_TMP_DIR/unsafe-spawn"; return 1; }
printf '{"tasks":[{"id":"blocked","agent":"codex","prompt":"implement"}]}' > "$TEST_TMP_DIR/tasks.json"
parallel_execute "$TEST_TMP_DIR/tasks.json" > "$TEST_TMP_DIR/parallel-blocked.log" 2>&1 && rc=0 || rc=$?
if [[ "$rc" == 1 && ! -e "$TEST_TMP_DIR/unsafe-spawn" ]] && \
    jq -e '. == []' "$TEST_TMP_DIR/aggregation-tasks.json" > /dev/null; then
    test_pass
else
    test_fail "undeletable prior output remained in dispatch or aggregation"
fi
test_summary
