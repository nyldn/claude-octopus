#!/usr/bin/env bash
# Unit tests for shared quota fast-fail watcher helpers.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/quota-watcher.sh"

test_suite "quota watcher helper"

log() { :; }

test_case "quota_watcher_has_match detects quota text in stderr"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
err_file="$tmp_dir/agent.err"
out_file="$tmp_dir/agent.out"
printf '%s\n' "RetryableQuotaError: exhausted your capacity" > "$err_file"
touch "$out_file"
if quota_watcher_has_match "$err_file" "$out_file"; then
    test_pass
else
    test_fail "quota pattern was not detected"
fi

test_case "start_quota_watcher invokes callback and stops target"
flag_file="$tmp_dir/callback.flag"
test_quota_callback() {
    local target_pid="$1"
    printf '%s\n' "$target_pid" > "$flag_file"
    kill "$target_pid" 2>/dev/null || true
}

( trap 'exit 0' TERM; while true; do sleep 1; done ) &
target_pid=$!
watcher_pid=$(start_quota_watcher "$target_pid" "$err_file" "$out_file" test_quota_callback "quota test")
printf '%s\n' "TerminalQuotaError" > "$out_file"

for _ in 1 2 3 4 5; do
    [[ -s "$flag_file" ]] && break
    sleep 1
done
stop_quota_watcher "$watcher_pid"
kill "$target_pid" 2>/dev/null || true
wait "$target_pid" 2>/dev/null || true

if [[ -s "$flag_file" ]]; then
    test_pass
else
    test_fail "quota watcher did not invoke callback"
fi

test_summary
