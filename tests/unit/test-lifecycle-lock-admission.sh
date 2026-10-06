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
