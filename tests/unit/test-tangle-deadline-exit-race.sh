#!/usr/bin/env bash
# Deterministic worker exit during deadline ledger inspection, without signaling
# real processes. The production watcher must still reject unverified live PIDs.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SOURCE_ROOT="${1:-$PROJECT_ROOT}"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Tangle deadline identity exit race"

run_deadline_case() (
    local scenario="$1" fixture="$TEST_TMP_DIR/$1"
    mkdir -p "$fixture/workspace/.octo/agents" "$fixture/results"
    source "$SOURCE_ROOT/scripts/lib/workflows.sh"
    WORKSPACE_DIR="$fixture/workspace"
    RESULTS_DIR="$fixture/results"
    OCTOPUS_TANGLE_DEADLINE=1
    CYAN="" NC=""
    local pids=(424242) task_ids=(deadline-race) clock=100 polls=0
    printf 0 > "$fixture/clock"
    log() { printf '%s %s\n' "$1" "$2" >> "$fixture/log"; }
    date() {
        if [[ "${1:-}" == +%s ]]; then
            clock=$(<"$fixture/clock")
            printf '%s' "$((clock + 2))" > "$fixture/clock"
            printf '%s\n' "$clock"
        else
            command date "$@"
        fi
    }
    # Initialization sets deadline=1; the next virtual reading exceeds it.
    tangle_process_is_active_non_zombie() { [[ ! -e "$fixture/exited" ]]; }
    sleep() {
        polls=$((polls + 1))
        ((polls < 4)) || exit 85
    }
    octopus_pid_verified_rows() {
        case "$scenario" in
            exited|completed) : > "$fixture/exited" ;;
            ledger-failure) : > "$fixture/exited"; return 1 ;;
        esac
        case "$scenario" in
            completed|active-late-marker)
                printf '0\n' > "$WORKSPACE_DIR/.octo/agents/deadline-race.done" ;;
            verified|kill-failure|retire-failure)
                printf '424242:codex:deadline-race:owned-identity\n' ;;
        esac
    }
    review_kill_process_tree_frozen() {
        printf '%s:%s\n' "$1" "$2" >> "$fixture/kills"
        [[ "$scenario" != kill-failure ]] || return 1
        : > "$fixture/exited"
    }
    octopus_pid_retire() {
        printf '%s:%s:%s\n' "$1" "$2" "$3" >> "$fixture/retire"
        [[ "$scenario" != retire-failure ]]
    }
    local rc=0 marker="$WORKSPACE_DIR/.octo/agents/deadline-race.done"
    tangle_wait_for_subtasks deadline-race > "$fixture/output" 2>&1 || rc=$?
    case "$scenario" in
        exited)
            [[ "$rc" == 0 && -f "$marker" && "$(<"$marker")" == timeout &&
               ! -e "$fixture/kills" && ! -e "$fixture/retire" ]] ;;
        completed)
            [[ "$rc" == 0 && "$(<"$marker")" == 0 && ! -e "$fixture/kills" ]] ;;
        verified)
            [[ "$rc" == 0 && "$(<"$marker")" == timeout &&
               "$(<"$fixture/kills")" == '424242:owned-identity' &&
               "$(<"$fixture/retire")" == '424242:deadline-race:owned-identity' ]] ;;
        active-late-marker)
            [[ "$rc" == 1 && "$(<"$marker")" == 0 && ! -e "$fixture/kills" ]] ;;
        active|ledger-failure)
            [[ "$rc" == 1 && ! -e "$marker" && ! -e "$fixture/kills" ]] ;;
        kill-failure)
            [[ "$rc" == 1 && ! -e "$marker" && ! -e "$fixture/retire" ]] ;;
        retire-failure)
            [[ "$rc" == 1 && ! -e "$marker" && -e "$fixture/retire" ]] ;;
    esac
)

for scenario in exited completed active active-late-marker verified ledger-failure kill-failure retire-failure; do
    test_case "deadline inspection: $scenario"
    if run_deadline_case "$scenario"; then
        test_pass
    else
        test_fail "deadline state contract failed for $scenario"
    fi
done
test_summary
