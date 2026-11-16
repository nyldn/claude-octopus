#!/bin/bash
# post-compact.sh must exit 0 for every completed_phases shape it can meet.
# workflows.sh records a count; older snapshots record a list. join() on a
# number made jq exit 5 and set -e failed the PostCompact hook.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "PostCompact snapshot shapes"

PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$PLUGIN_DIR/hooks/post-compact.sh"
FAKE_HOME="$(mktemp -d)"
trap 'rm -rf "$FAKE_HOME"' EXIT
mkdir -p "$FAKE_HOME/.claude-octopus/.octo"
SNAPSHOT="$FAKE_HOME/.claude-octopus/.octo/pre-compact-snapshot.json"

run_hook() {
    printf '{"phase":"develop","workflow":"embrace","completed_phases":%s,"blockers":%s}\n' "$1" "$2" > "$SNAPSHOT"
    HOME="$FAKE_HOME" bash "$HOOK" < /dev/null 2>&1
}

check() {
    local name="$1" completed="$2" blockers="$3" expected="$4" output rc=0
    test_case "$name"
    output=$(run_hook "$completed" "$blockers") || rc=$?
    if [[ $rc -ne 0 ]]; then
        test_fail "hook exited $rc: $output"
    elif [[ -n "$expected" && "$output" != *"$expected"* ]]; then
        test_fail "missing '$expected' in: $output"
    elif [[ -z "$expected" && "$output" == *"Completed:"* ]]; then
        test_fail "unexpected Completed line: $output"
    else
        test_pass
    fi
}

check "zero count prints no Completed line" 0 '[]' ""
check "positive count" 3 '[]' "Completed: 3 phase(s)"
check "list of phases" '["discover","define"]' '[]' "Completed: discover, define"
check "missing field" null '[]' ""
check "string blockers" '[]' '"provider offline"' "Blockers: provider offline"

test_summary
