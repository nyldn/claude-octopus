#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$PROJECT_ROOT/tests/helpers/test-framework.sh"
source "$PROJECT_ROOT/scripts/lib/lifecycle.sh"
test_suite "Lifecycle kernel lock admission"
fixture="$TEST_TMP_DIR/lifecycle-lock"
mkdir -p "$fixture"
lock_host="test"
owner="owner-test-${BASHPID:-$$}"

check() {
    test_case "$1"
    if ( "$2" ); then test_pass; else test_fail "$1"; fi
}
helper_statuses() {
    local rc=0
    _octo_lifecycle_mkdir "$fixture/status"
    _octo_lifecycle_mkdir "$fixture/status" || rc=$?
    [[ "$rc" == 75 ]] || return 1
    rc=0; _octo_lifecycle_mkdir "$fixture/absent/lock" || rc=$?
    [[ "$rc" == 1 ]]
}
check "kernel distinguishes existing-directory contention and infrastructure failure" helper_statuses

false_utility() {
    local target="$fixture/false-utility" rc=0 sleeps=0
    command mkdir "$target.lock" "$target.lock/$owner"
    mkdir() { return 0; }
    sleep() { sleeps=$((sleeps + 1)); }
    _octo_lifecycle_lock "$target" "other-claim" || rc=$?
    [[ "$rc" == 1 && "$sleeps" == 49 && -d "$target.lock/$owner" && ! -e "$target.lock/other-claim" ]]
}
check "false-success shell utility cannot admit a second live owner" false_utility

infrastructure_prompt() {
    local calls=0 rc=0 sleeps=0
    _octo_lifecycle_mkdir() { calls=$((calls + 1)); return 1; }
    sleep() { sleeps=$((sleeps + 1)); }
    _octo_lifecycle_lock "$fixture/infrastructure" "$owner" || rc=$?
    [[ "$rc" == 1 && "$calls" == 1 && "$sleeps" == 0 ]]
}
check "creation infrastructure failure stops promptly" infrastructure_prompt

bounded_contention() {
    local calls=0 sleeps=0 rc=0
    _octo_lifecycle_mkdir() { calls=$((calls + 1)); return 75; }
    sleep() { sleeps=$((sleeps + 1)); }
    command mkdir "$fixture/bounded.lock" "$fixture/bounded.lock/$owner"
    _octo_lifecycle_lock "$fixture/bounded" "other-claim" || rc=$?
    [[ "$rc" == 1 && "$calls" == 50 && "$sleeps" == 49 ]]
}
check "contention retains fifty attempts and forty-nine waits" bounded_contention

vanished_directory() {
    local calls=0 sleeps=0 target="$fixture/vanished"
    eval "$(declare -f _octo_lifecycle_mkdir | sed '1s/_octo_lifecycle_mkdir/_real_mkdir/')"
    _octo_lifecycle_mkdir() {
        calls=$((calls + 1))
        [[ "$calls" != 1 ]] || return 75
        _real_mkdir "$@"
    }
    sleep() { sleeps=$((sleeps + 1)); }
    _octo_lifecycle_lock "$target" "$owner"
    [[ "$calls" == 3 && "$sleeps" == 0 && -d "$target.lock/$owner" ]]
}
check "vanished contention path retries without stealing or delaying" vanished_directory

released_during_inspection() {
    local target="$fixture/inspection-release" rc=0 race_fired=0
    command mkdir "$target.lock"
    # Schedule a real holder release after the absence probe. DEBUG also reaches
    # the owner scan once directory classification no longer uses shell probes.
    set -T
    trap 'case "$BASH_COMMAND" in
        *"[[ -d \"\$lock\""*|*"for candidate in "*|*"_octo_lifecycle_reclaim \"\$lock\""*)
            trap - DEBUG
            command rmdir "$target.lock" || return 1
            race_fired=1 ;;
    esac' DEBUG
    _octo_lifecycle_lock "$target" "$owner" || rc=$?
    trap - DEBUG
    [[ "$race_fired" == 1 && "$rc" == 0 && -d "$target.lock/$owner" ]] || return 1
    _octo_lifecycle_unlock "$target.lock" "$owner" ""
    [[ ! -e "$target.lock" ]]
}
check "holder release during contention inspection retries successfully" released_during_inspection

unsafe_lock_objects() {
    local kind target rc
    command mkdir "$fixture/foreign-target"
    printf keep > "$fixture/foreign-target/user-data"
    for kind in file symlink dangling; do
        target="$fixture/unsafe-$kind"
        case "$kind" in
            file) printf keep > "$target.lock" ;;
            symlink) ln -s "$fixture/foreign-target" "$target.lock" ;;
            dangling) ln -s "$fixture/missing-target" "$target.lock" ;;
        esac
        rc=0
        _octo_lifecycle_lock "$target" "$owner" || rc=$?
        [[ "$rc" == 1 && ! -e "$target.lock/$owner" ]] || return 1
        if [[ "$kind" == file ]]; then
            [[ -f "$target.lock" && "$(cat "$target.lock")" == keep ]] || return 1
        else
            [[ -L "$target.lock" ]] || return 1
        fi
    done
    [[ "$(ls -A "$fixture/foreign-target")" == user-data && "$(cat "$fixture/foreign-target/user-data")" == keep ]]
}
check "file and live or dangling symlink lock objects fail closed without mutation" unsafe_lock_objects

replaced_lock_directory() {
    local target="$fixture/replaced-lock" foreign="$fixture/foreign-owners"
    local rc=0 race_fired=0 stale_pid stale
    ( exit 0 ) & stale_pid=$!
    wait "$stale_pid"
    stale="owner-$lock_host-$stale_pid"
    command mkdir "$target.lock" "$foreign" "$foreign/$stale"
    set -T
    trap 'case "$BASH_COMMAND" in
        *"[[ ! -e \"\$lock\""*)
            trap - DEBUG
            command rmdir "$target.lock" || return 1
            ln -s "$foreign" "$target.lock" || return 1
            race_fired=1 ;;
    esac' DEBUG
    _octo_lifecycle_lock "$target" "$owner" || rc=$?
    trap - DEBUG
    [[ "$race_fired" == 1 && "$rc" == 1 && -L "$target.lock" && -d "$foreign/$stale" ]]
}
check "a lock replaced by a symlink cannot reclaim foreign owner metadata" replaced_lock_directory

owner_failure() {
    local target="$fixture/owner-failure" rc=0
    eval "$(declare -f _octo_lifecycle_mkdir | sed '1s/_octo_lifecycle_mkdir/_real_mkdir/')"
    _octo_lifecycle_mkdir() {
        if [[ "$1" == "$target.lock/$owner" ]]; then
            command mkdir "$target.lock/foreign"
            return 75
        fi
        _real_mkdir "$@"
    }
    _octo_lifecycle_lock "$target" "$owner" || rc=$?
    [[ "$rc" == 1 && -d "$target.lock/foreign" && ! -e "$target.lock/$owner" ]]
}
check "failed owner admission preserves foreign metadata" owner_failure

missing_python() {
    local target="$fixture/no-python" tools="$fixture/tools" rc=0 name
    command mkdir "$tools"
    for name in mkdir rmdir sleep; do ln -s "$(command -v "$name")" "$tools/$name"; done
    PATH="$tools" _octo_lifecycle_lock "$target" "$owner" || rc=$?
    [[ "$rc" == 1 && ! -e "$target.lock" ]]
}
check "missing Python refuses durable ownership instead of falling back to utility mkdir" missing_python

owner_kernel() {
    local target="$fixture/kernel-owner"
    mkdir() { return 0; }
    _octo_lifecycle_lock "$target" "$owner"
    [[ -d "$target.lock/$owner" ]]
    _octo_lifecycle_unlock "$target.lock" "$owner" ""
    [[ ! -e "$target.lock" ]]
}
check "both transaction and owner directories come from kernel admission" owner_kernel

missing_runtime_record() {
    local tools="$fixture/record-tools" rc=0 name
    local OCTO_LIFECYCLE_STATE_FILE="$fixture/no-runtime-record.json"
    local OCTOPUS_HOST="claude" CLAUDE_PLUGIN_ROOT="$fixture"
    local OCTOPUS_CONTEXT_PROFILE="core" OCTOPUS_HOOK_PROFILE="core"
    command mkdir "$tools"
    for name in jq dirname mkdir sh hostname; do ln -s "$(command -v "$name")" "$tools/$name"; done
    PATH="$tools" octo_lifecycle_record_install || rc=$?
    [[ "$rc" == 6 && ! -e "$OCTO_LIFECYCLE_STATE_FILE" && ! -e "$OCTO_LIFECYCLE_STATE_FILE.lock" ]]
}
check "receipt recording without Python reports lock failure and publishes no state" missing_runtime_record

test_summary
