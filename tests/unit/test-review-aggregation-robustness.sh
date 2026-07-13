#!/usr/bin/env bash
# Tests for robust review findings extraction / aggregation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "review aggregation robustness"

REVIEW_SH="$PROJECT_ROOT/scripts/lib/review.sh"
TMP_TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/octo-review-robustness.XXXXXX")"
TMP_MD="$TMP_TEST_DIR/review.md"
trap 'rm -rf "$TMP_TEST_DIR"' EXIT

cat > "$TMP_MD" <<'EOF'
# Agent: claude-sonnet
## Output
```
The provider echoed prompt text first.
Example: {"findings": []}
Now the actual answer:
{"findings":[{"file":"api/terminal.js","line":12,"severity":"normal","category":"security","title":"Broken regex","detail":"The regex is wrong","confidence":0.9}]}
The provider then echoed the prompt example again: {"findings": []}
```

## Status: SUCCESS
EOF

test_case "extractor helper is present"
if grep -q "review_extract_findings_array" "$REVIEW_SH"; then test_pass; else test_fail "missing helper"; fi

test_case "round1 snapshot is written"
if grep -q "review-round1-findings" "$REVIEW_SH"; then test_pass; else test_fail "missing round1 snapshot"; fi

test_case "extractor prefers the last non-empty findings array"
log() { :; }
source "$REVIEW_SH" >/dev/null 2>&1 || true
if out=$(review_extract_findings_array "$TMP_MD" 2>/dev/null); then
    if count=$(printf '%s' "$out" | jq 'length' 2>/dev/null) && title=$(printf '%s' "$out" | jq -r '.[0].title' 2>/dev/null); then
        if [[ "$count" == "1" && "$title" == "Broken regex" ]]; then
            test_pass
        else
            test_fail "unexpected extraction output: $out"
        fi
    else
        test_fail "extractor returned invalid JSON: $out"
    fi
else
    test_fail "extractor failed to recover findings"
fi

test_case "extractor rejects non-array findings values"
cat > "$TMP_TEST_DIR/non-array.md" <<'EOF'
# Agent: malformed-provider
## Output
{"findings":"not-an-array"}
## Status: SUCCESS
EOF
non_array_out="$(review_extract_findings_array "$TMP_TEST_DIR/non-array.md" 2>/dev/null || true)"
if [[ "$(printf '%s' "$non_array_out" | jq -r 'type' 2>/dev/null || true)" == "array" ]] &&
   [[ "$(printf '%s' "$non_array_out" | jq -r 'length' 2>/dev/null || true)" == "0" ]]; then
    test_pass
else
    test_fail "non-array findings escaped extraction: $non_array_out"
fi

test_case "progress fingerprint ignores unrelated result artifacts"
progress_dir="$TMP_TEST_DIR/progress"
mkdir -p "$progress_dir"
printf 'target-v1\n' > "$progress_dir/target.out"
printf 'other-v1\n' > "$progress_dir/other.out"
since_epoch=$(( $(date +%s) - 1 ))
target_fp_before="$(review_progress_fingerprint_since "$since_epoch" "$progress_dir" 'target.out')"
printf 'other-v2-with-more-bytes\n' > "$progress_dir/other.out"
target_fp_after_unrelated="$(review_progress_fingerprint_since "$since_epoch" "$progress_dir" 'target.out')"
printf 'target-v2-with-more-bytes\n' > "$progress_dir/target.out"
target_fp_after_target="$(review_progress_fingerprint_since "$since_epoch" "$progress_dir" 'target.out')"
if [[ "$target_fp_before" == "$target_fp_after_unrelated" && "$target_fp_before" != "$target_fp_after_target" ]]; then
    test_pass
else
    test_fail "fingerprint was not scoped to the requested artifact pattern"
fi

test_case "process-tree termination reaches TERM-ignoring grandchildren"
if ! declare -F review_terminate_process_tree >/dev/null 2>&1; then
    test_fail "missing recursive process-tree termination helper"
else
    process_dir="$TMP_TEST_DIR/process-tree"
    mkdir -p "$process_dir"
    cat > "$process_dir/grandchild.sh" <<'PROCESS_GRANDCHILD'
trap '' TERM
while :; do sleep 1; done
PROCESS_GRANDCHILD
    cat > "$process_dir/child.sh" <<'PROCESS_CHILD'
trap '' TERM
bash "$1/grandchild.sh" &
echo "$!" > "$1/grandchild.pid"
wait
PROCESS_CHILD
    cat > "$process_dir/root.sh" <<'PROCESS_ROOT'
trap '' TERM
bash "$1/child.sh" "$1" &
echo "$!" > "$1/child.pid"
wait
PROCESS_ROOT
    bash "$process_dir/root.sh" "$process_dir" &
    root_pid=$!
    for _ in 1 2 3 4 5; do
        [[ -s "$process_dir/child.pid" && -s "$process_dir/grandchild.pid" ]] && break
        sleep 1
    done
    child_pid="$(cat "$process_dir/child.pid" 2>/dev/null || true)"
    grandchild_pid="$(cat "$process_dir/grandchild.pid" 2>/dev/null || true)"

    review_terminate_process_tree "$root_pid" 1
    wait "$root_pid" 2>/dev/null || true

    process_is_running() {
        local pid="$1"
        [[ -n "$pid" ]] || return 1
        ps -o stat= -p "$pid" 2>/dev/null | grep -Eqv '^[[:space:]]*Z'
    }
    if [[ -n "$child_pid" && -n "$grandchild_pid" ]] &&
       ! process_is_running "$root_pid" &&
       ! process_is_running "$child_pid" &&
       ! process_is_running "$grandchild_pid"; then
        test_pass
    else
        kill -KILL "$root_pid" "$child_pid" "$grandchild_pid" 2>/dev/null || true
        test_fail "recursive termination left a process alive"
    fi
fi

test_case "timing knobs accept leading-zero decimal values"
run_agent_sync() { printf 'ok\n'; }
timing_err="$TMP_TEST_DIR/timing.err"
if OCTOPUS_REVIEW_STALL_WINDOW=08 OCTOPUS_REVIEW_POLL_SECS=08 \
   review_run_agent_sync_progress codex prompt role review timing-test \
       >/dev/null 2>"$timing_err" &&
   ! grep -q 'value too great for base' "$timing_err"; then
    test_pass
else
    test_fail "leading-zero timing knob triggered Bash octal parsing"
fi

test_case "retry wait stops when provider exits without terminal status"
dead_result="$TMP_TEST_DIR/dead-result.md"
sleep 1 &
dead_provider_pid=$!
review_wait_for_result_status "$dead_result" "$dead_provider_pid" dead-provider "$TMP_TEST_DIR" 02 01 &
waiter_pid=$!
waiter_finished=false
for _ in 1 2 3 4; do
    if ! kill -0 "$waiter_pid" 2>/dev/null; then
        waiter_finished=true
        break
    fi
    sleep 1
done
if [[ "$waiter_finished" == "true" ]]; then
    wait "$waiter_pid" 2>/dev/null || true
    test_pass
else
    kill -KILL "$waiter_pid" 2>/dev/null || true
    wait "$waiter_pid" 2>/dev/null || true
    test_fail "waiter remained alive after provider exited"
fi

test_case "retry wait accepts only terminal status markers"
wait_helper_body="$(sed -n '/^review_wait_for_result_status()/,/^}/p' "$REVIEW_SH")"
terminal_helper_body="$(sed -n '/^review_result_has_terminal_status()/,/^}/p' "$REVIEW_SH")"
if grep -q 'review_result_has_terminal_status' <<< "$wait_helper_body" &&
   grep -q "Status: (SUCCESS|FAILED|TIMEOUT)" <<< "$terminal_helper_body"; then
    test_pass
else
    test_fail "retry wait still accepts arbitrary status markers"
fi

test_case "result success requires anchored terminal SUCCESS marker"
if ! declare -F review_result_completed_successfully >/dev/null 2>&1; then
    test_fail "missing terminal success classifier"
else
    printf '{"findings":[{"title":"partial"}]}\n' > "$TMP_TEST_DIR/partial.md"
    printf '## Status: FAILED (exit code: 1)\n' > "$TMP_TEST_DIR/failed.md"
    printf '## Status: SUCCESS\n' > "$TMP_TEST_DIR/success.md"
    printf '## Status: SUCCESS\n## Status: FAILED (exit code: 1)\n' > "$TMP_TEST_DIR/success-then-failed.md"
    printf '## Status: SUCCESS\n## Status: TIMEOUT\n' > "$TMP_TEST_DIR/success-then-timeout.md"
    if ! review_result_completed_successfully "$TMP_TEST_DIR/partial.md" &&
       ! review_result_completed_successfully "$TMP_TEST_DIR/failed.md" &&
       ! review_result_completed_successfully "$TMP_TEST_DIR/success-then-failed.md" &&
       ! review_result_completed_successfully "$TMP_TEST_DIR/success-then-timeout.md" &&
       review_result_completed_successfully "$TMP_TEST_DIR/success.md"; then
        test_pass
    else
        test_fail "terminal success classifier accepted a partial or failed result"
    fi
fi

test_case "Round 1 supervision tracks progress per agent"
if grep -q 'round1_last_progress' "$REVIEW_SH" &&
   grep -q 'round1_settled' "$REVIEW_SH" &&
   grep -Eq 'basename.*(_rf|round1_files)' "$REVIEW_SH"; then
    test_pass
else
    test_fail "Round 1 still uses a fleet-wide stall fingerprint"
fi

test_case "Unreleased changelog has one Fixed section"
unreleased_fixed_count=$(sed -n '/^## \[Unreleased\]/,/^## \[[0-9]/p' "$PROJECT_ROOT/CHANGELOG.md" | grep -c '^### Fixed$' || true)
if [[ "$unreleased_fixed_count" == "1" ]]; then
    test_pass
else
    test_fail "Unreleased contains $unreleased_fixed_count Fixed sections"
fi

test_case "review agents run without absolute timeout"
if grep -q "export TIMEOUT=0" "$REVIEW_SH" && grep -q "review_run_agent_sync_progress" "$REVIEW_SH"; then
    test_pass
else
    test_fail "review no-wall-timeout wiring missing"
fi

test_case "old review timeout envs are removed"
if grep -q "OCTOPUS_REVIEW_VERIFIER_TIMEOUT\|OCTOPUS_REVIEW_SYNTHESIS_TIMEOUT\|OCTOPUS_REVIEW_TIMEOUT" "$REVIEW_SH"; then
    test_fail "old review timeout env still present"
else
    test_pass
fi

test_case "review uses stall watchdog"
if grep -q "OCTOPUS_REVIEW_STALL_WINDOW" "$REVIEW_SH"; then test_pass; else test_fail "missing review stall window"; fi

test_case "invalid synthesis has local fallback"
if grep -q "synthesis returned invalid findings JSON" "$REVIEW_SH"; then test_pass; else test_fail "missing local fallback"; fi

test_summary
