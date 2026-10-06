#!/usr/bin/env bash
# A successful mkdir status alone must not admit a second research creator.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Research lock admission"

research_parallel_admission_fixture() (
    source "$PROJECT_ROOT/scripts/lib/research-evidence.sh" || return 1
    local fixture="$TEST_TMP_DIR/research-admission"
    WORKSPACE_DIR="$fixture/workspace" RESULTS_DIR="$fixture/results"
    OCTOPUS_RESEARCH_RUN_ID="" OCTOPUS_RESEARCH_RESUME=false
    OCTOPUS_RESEARCH_EVIDENCE=true OCTOPUS_RESEARCH_INTENSITY=quick
    unset RESEARCH_RUN_DIR RESEARCH_RUN_ID RESEARCH_TASK_GROUP RESEARCH_PROMPT
    unset RESEARCH_INTENSITY RESEARCH_PROVIDER_RESULTS_DIR
    command mkdir -p "$WORKSPACE_DIR" "$RESULTS_DIR" || return 1
    local run_dir="$WORKSPACE_DIR/research-runs/flow-1700000003"
    local contended_attempts=0

    wait_for_marker() {
        local tries=0
        while [[ ! -e "$1" && ! -e "${2:-$1}" ]]; do
            tries=$((tries + 1))
            [[ "$tries" -le 500 ]] || return 1
            sleep 0.01
        done
    }

    mkdir() {
        local status=0
        command mkdir "$@" || status=$?
        # Reproduce the observed mkdir implementation's false-success EEXIST
        # race. The directory and its existing owner are real filesystem data.
        if [[ "$*" == *".run-create.lock" && "$status" -ne 0 \
            && -d "$run_dir/.run-create.lock" ]]; then
            contended_attempts=$((contended_attempts + 1))
            if [[ "$contended_attempts" -ge 3 ]]; then
                : > "$fixture/contender-retried"
            fi
            return 0
        fi
        return "$status"
    }

    mv() {
        if [[ "${child_label:-}" == "creator" && "$*" == *".prompt."* ]]; then
            : > "$fixture/creator-ready"
            wait_for_marker "$fixture/release-creator" || return 1
        fi
        command mv "$@"
    }

    (
        child_label=creator
        research_probe_single_begin "probe-1700000003-0" "creator topic" || exit 1
        research_probe_single_record "probe-1700000003-0" codex completed || exit 1
    ) > "$fixture/creator.log" 2>&1 &
    local creator_pid=$! creator_status=0 contender_status=0 barrier_status=0
    wait_for_marker "$fixture/creator-ready" || barrier_status=1
    local owner_before="" owner_after=""
    IFS= read -r owner_before < "$run_dir/.run-create.lock/owner" || barrier_status=1
    (
        child_label=contender
        research_probe_single_begin "probe-1700000003-1" "contender topic" || exit 1
        research_probe_single_record "probe-1700000003-1" codex completed || exit 1
        : > "$fixture/contender-finished"
    ) > "$fixture/contender.log" 2>&1 &
    local contender_pid=$!
    wait_for_marker "$fixture/contender-retried" "$fixture/contender-finished" || barrier_status=1
    if [[ -r "$run_dir/.run-create.lock/owner" ]]; then
        IFS= read -r owner_after < "$run_dir/.run-create.lock/owner" || barrier_status=1
    fi
    : > "$fixture/release-creator"
    wait "$creator_pid" || creator_status=$?
    wait "$contender_pid" || contender_status=$?

    [[ "$barrier_status" -eq 0 && "$creator_status" -eq 0 && "$contender_status" -eq 0 \
        && -n "$owner_before" && "$owner_after" == "$owner_before" \
        && "$(cat "$run_dir/prompt.txt")" == "creator topic" \
        && ! -e "$run_dir/.run-create.lock" && ! -e "$run_dir/.manifest.lock" \
        && ! -e "$run_dir/.events.lock" ]] \
        && jq -e '.prompt == "creator topic" and .task_group == "1700000003" and .intensity == "quick"' \
            "$run_dir/manifest.json" >/dev/null \
        && jq -s -e 'map(select(.event == "run.started")) | length == 1' \
            "$run_dir/events.jsonl" >/dev/null \
        && jq -s -e 'map(select(.event == "provider.completed")) | length == 2' \
            "$run_dir/events.jsonl" >/dev/null
)

test_case "parallel creator admission preserves the owner and published run"
if research_parallel_admission_fixture; then
    test_pass
else
    test_fail "a contender replaced the owner, prompt, manifest, or provider event history"
fi

research_invalid_owner_fixture() (
    source "$PROJECT_ROOT/scripts/lib/research-evidence.sh" || return 1
    local kind="$1" fixture="$TEST_TMP_DIR/research-owner-$1"
    local lock="$fixture/lock" status=0 noclobber_before="${-//[^C]/}"
    command mkdir -p "$lock" || return 1
    case "$kind" in
        directory) command mkdir "$lock/owner" || return 1 ;;
        symlink)
            printf 'preserve\n' > "$fixture/target"
            ln -s "$fixture/target" "$lock/owner" || return 1
            ;;
        dangling) ln -s "$fixture/target" "$lock/owner" || return 1 ;;
        write-failure) printf() { return 1; } ;;
    esac
    # Force false mkdir success; bounded retries must not remove this lock or
    # follow its owner symlink. Avoid spending two seconds on inert backoff.
    mkdir() { return 0; }
    sleep() { :; }
    research_lock_acquire "$lock" >/dev/null 2>&1 || status=$?
    [[ "$status" -eq 1 && -d "$lock" && "${-//[^C]/}" == "$noclobber_before" ]] || return 1
    case "$kind" in
        directory) [[ -d "$lock/owner" ]] ;;
        symlink) [[ -L "$lock/owner" && "$(cat "$fixture/target")" == "preserve" ]] ;;
        dangling) [[ -L "$lock/owner" && ! -e "$fixture/target" ]] ;;
        write-failure) [[ -f "$lock/owner" && ! -s "$lock/owner" ]] ;;
    esac
)

for owner_kind in directory symlink dangling write-failure; do
    test_case "failed $owner_kind owner claim preserves lock and caller options"
    if research_invalid_owner_fixture "$owner_kind"; then
        test_pass
    else
        test_fail "failed owner admission altered the lock, target, or caller options"
    fi
done

test_summary
