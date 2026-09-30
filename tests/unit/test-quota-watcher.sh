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

test_case "quota_watcher_has_match detects the codex usage-limit error line"
printf '%s\n' "ERROR: You've hit your usage limit. Upgrade to Pro (https://chatgpt.com/explore/pro), visit https://chatgpt.com/codex/settings/usage to purchase more credits or try again at 10:25 PM." > "$out_file"
: > "$err_file"
if quota_watcher_has_match "$err_file" "$out_file"; then
    test_pass
else
    test_fail "codex usage-limit error line was not detected"
fi

test_case "quota_watcher_has_match ignores the codex message quoted in grep output"
printf '%s\n' "scripts/lib/quota-watcher.sh:22:#   \"ERROR: You've hit your usage limit\" — codex CLI" > "$out_file"
if quota_watcher_has_match "$err_file" "$out_file"; then
    test_fail "a grepped quote of the codex message matched as a live quota error"
else
    test_pass
fi

test_case "quota_watcher_mark_after_exit marks a provider that failed on a quota error"
export WORKSPACE_DIR="$tmp_dir/workspace"
printf '%s\n' "ERROR: You've hit your usage limit. Try again at 10:25 PM." > "$err_file"
: > "$out_file"
quota_watcher_mark_after_exit 1 "$err_file" "$out_file" codex
if octo_quota_is_dead codex; then
    test_pass
else
    test_fail "codex was not marked quota-dead after a failed exit with the usage-limit error"
fi

test_case "quota_watcher_mark_after_exit leaves a successful exit unmarked"
octo_quota_clear_dead codex
quota_watcher_mark_after_exit 0 "$err_file" "$out_file" codex
if octo_quota_is_dead codex; then
    test_fail "a zero exit was marked quota-dead"
else
    test_pass
fi

test_case "quota_watcher_mark_after_exit leaves a failure without a quota signature unmarked"
printf '%s\n' "error: unexpected argument '--foo' found" > "$err_file"
quota_watcher_mark_after_exit 2 "$err_file" "$out_file" codex
if octo_quota_is_dead codex; then
    test_fail "a non-quota failure was marked quota-dead"
else
    test_pass
fi
unset WORKSPACE_DIR

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
