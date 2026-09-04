#!/usr/bin/env bash
# Tests for robust review findings extraction / aggregation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "review aggregation robustness"

REVIEW_SH="$PROJECT_ROOT/scripts/lib/review.sh"
TEST_TMP_DIR="/tmp/octopus-tests-$$"
rm -rf "$TEST_TMP_DIR"
mkdir -p "$TEST_TMP_DIR"
TMP_MD="$TEST_TMP_DIR/review.md"
trap 'rm -rf "$TEST_TMP_DIR"' EXIT

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

test_case "extractor fast path returns only the last non-empty findings array"
cat > "$TEST_TMP_DIR/multiple-json.md" <<'EOF'
# Agent: multiple-json-provider
## Output
{"findings":[{"title":"First finding"}]}
{"findings":[]}
{"findings":[{"title":"Last finding"}]}
## Status: SUCCESS
EOF
multiple_json_out="$(review_extract_findings_array "$TEST_TMP_DIR/multiple-json.md" 2>/dev/null || true)"
if [[ "$(printf '%s' "$multiple_json_out" | jq -r 'length' 2>/dev/null || true)" == "1" ]] &&
   [[ "$(printf '%s' "$multiple_json_out" | jq -r '.[0].title' 2>/dev/null || true)" == "Last finding" ]]; then
    test_pass
else
    test_fail "fast path returned multiple or stale findings arrays: $multiple_json_out"
fi

test_case "extractor rejects non-array findings values"
cat > "$TEST_TMP_DIR/non-array.md" <<'EOF'
# Agent: malformed-provider
## Output
{"findings":"not-an-array"}
## Status: SUCCESS
EOF
non_array_out="$(review_extract_findings_array "$TEST_TMP_DIR/non-array.md" 2>/dev/null || true)"
if [[ "$(printf '%s' "$non_array_out" | jq -r 'type' 2>/dev/null || true)" == "array" ]] &&
   [[ "$(printf '%s' "$non_array_out" | jq -r 'length' 2>/dev/null || true)" == "0" ]]; then
    test_pass
else
    test_fail "non-array findings escaped extraction: $non_array_out"
fi

test_case "findings normalizer accepts one document and deduplicates findings"
single_document='{"findings":[{"file":"CHANGELOG.md","line":1,"category":"docs","title":"Duplicate"},{"file":"CHANGELOG.md","line":1,"category":"docs","title":"Duplicate"}]}'
single_normalized="$(printf '%s' "$single_document" | review_normalize_findings_json 2>/dev/null || true)"
if [[ "$(printf '%s' "$single_normalized" | jq -r '.findings | length' 2>/dev/null || true)" == "1" ]]; then
    test_pass
else
    test_fail "single-document findings were not normalized and deduplicated: $single_normalized"
fi

test_case "findings normalizer rejects non-object entries"
non_object_document='{"findings":[null]}'
if printf '%s' "$non_object_document" | review_normalize_findings_json >/dev/null 2>&1; then
    test_fail "non-object finding was accepted"
else
    test_pass
fi

test_case "findings normalizer preserves synthesis ranking while deduplicating"
ranked_document='{"findings":[{"file":"z-last-path.js","line":9,"severity":"normal","title":"Highest-ranked"},{"file":"a-first-path.js","line":1,"severity":"nit","title":"Lower-ranked"},{"file":"z-last-path.js","line":9,"severity":"normal","title":"Highest-ranked"}]}'
ranked_normalized="$(printf '%s' "$ranked_document" | review_normalize_findings_json 2>/dev/null || true)"
ranked_titles="$(printf '%s' "$ranked_normalized" | jq -r '.findings[].title' 2>/dev/null || true)"
if [[ "$ranked_titles" == $'Highest-ranked\nLower-ranked' ]]; then
    test_pass
else
    test_fail "normalization reordered synthesized findings: $ranked_titles"
fi

test_case "local synthesis preserves first occurrence order within a severity"
same_severity='[{"file":"z-last-path.js","line":9,"severity":"normal","title":"First-seen"},{"file":"a-first-path.js","line":1,"severity":"normal","title":"Second-seen"},{"file":"z-last-path.js","line":9,"severity":"normal","title":"First-seen"}]'
same_severity_titles="$(review_local_synthesis_json "$same_severity" | jq -r '.findings[].title' 2>/dev/null || true)"
if [[ "$same_severity_titles" == $'First-seen\nSecond-seen' ]]; then
    test_pass
else
    test_fail "local synthesis reordered equal-severity findings: $same_severity_titles"
fi

test_case "findings normalizer rejects multiple JSON documents"
multi_document_file="$TEST_TMP_DIR/multi-document-findings.json"
printf '%s\n%s\n' \
    '{"findings":[{"title":"Duplicate"}]}' \
    '{"findings":[{"title":"Duplicate"}]}' > "$multi_document_file"
if review_normalize_findings_json < "$multi_document_file" >/dev/null 2>&1; then
    test_fail "multi-document findings were accepted"
else
    test_pass
fi

test_case "findings count returns one integer or rejects malformed input without output"
valid_count="$(review_findings_count "$single_normalized" 2>/dev/null || true)"
invalid_count_file="$TEST_TMP_DIR/invalid-count.out"
if review_findings_count "$(cat "$multi_document_file")" > "$invalid_count_file" 2>/dev/null; then
    invalid_count_rc=0
else
    invalid_count_rc=$?
fi
non_object_count_file="$TEST_TMP_DIR/non-object-count.out"
if review_findings_count "$non_object_document" > "$non_object_count_file" 2>/dev/null; then
    non_object_count_rc=0
else
    non_object_count_rc=$?
fi
if [[ "$valid_count" == "1" && "$invalid_count_rc" -ne 0 && ! -s "$invalid_count_file" &&
      "$non_object_count_rc" -ne 0 && ! -s "$non_object_count_file" ]]; then
    test_pass
else
    test_fail "count helper returned valid='$valid_count' multi_rc='$invalid_count_rc' non_object_rc='$non_object_count_rc'"
fi

test_case "terminal rendering fails closed on multi-document findings"
multi_render_output="$TEST_TMP_DIR/multi-render.out"
if render_terminal_report "$multi_document_file" > "$multi_render_output" 2>&1; then
    multi_render_rc=0
else
    multi_render_rc=$?
fi
if [[ "$multi_render_rc" -ne 0 ]] &&
   grep -q 'invalid findings artifact' "$multi_render_output" &&
   [[ "$(grep -c 'Duplicate' "$multi_render_output" 2>/dev/null || true)" == "0" ]] &&
   ! grep -q 'syntax error in expression' "$multi_render_output"; then
    test_pass
else
    test_fail "multi-document rendering did not fail closed: $(tr '\n' ' ' < "$multi_render_output")"
fi

test_case "missing repository fallback renders the terminal report once"
original_render_terminal_report="$(declare -f render_terminal_report)"
gh() { return 1; }
render_terminal_report() { printf '%s\n' "rendered-once"; }
missing_repo_file="$TEST_TMP_DIR/missing-repo.json"
printf '%s\n' "$single_normalized" > "$missing_repo_file"
missing_repo_output="$(post_inline_comments 123 "$missing_repo_file" 2>/dev/null || render_terminal_report "$missing_repo_file")"
unset -f gh
unset -f render_terminal_report
eval "$original_render_terminal_report"
if [[ "$(grep -c '^rendered-once$' <<< "$missing_repo_output" 2>/dev/null || true)" == "1" ]]; then
    test_pass
else
    test_fail "missing-repository fallback rendered more than once: $missing_repo_output"
fi

test_case "progress fingerprint ignores unrelated result artifacts"
progress_dir="$TEST_TMP_DIR/progress"
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
    process_dir="$TEST_TMP_DIR/process-tree"
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
timing_err="$TEST_TMP_DIR/timing.err"
if OCTOPUS_REVIEW_STALL_WINDOW=08 OCTOPUS_REVIEW_POLL_SECS=08 \
   review_run_agent_sync_progress codex prompt role review timing-test \
       >/dev/null 2>"$timing_err" &&
   ! grep -q 'value too great for base' "$timing_err"; then
    test_pass
else
    test_fail "leading-zero timing knob triggered Bash octal parsing"
fi

test_case "retry wait stops when provider exits without terminal status"
dead_result="$TEST_TMP_DIR/dead-result.md"
sleep 1 &
dead_provider_pid=$!
review_wait_for_result_status "$dead_result" "$dead_provider_pid" dead-provider "$TEST_TMP_DIR" 02 01 &
waiter_pid=$!
# Block on the waiter's own exit (SIGCHLD-driven) instead of racing a fixed
# poll budget against scheduler jitter — the old 4x1s poll had only ~1-2s of
# margin over the waiter's own ~2s internal cycle and went red intermittently
# on loaded macOS runners. A generous watchdog still bounds the test so a
# real regression (waiter never detects the dead process) fails instead of
# hanging.
(
    sleep 15
    kill -KILL "$waiter_pid" 2>/dev/null
) &
watchdog_pid=$!
if wait "$waiter_pid" 2>/dev/null; then
    waiter_finished=true
else
    waiter_finished=false
fi
kill "$watchdog_pid" 2>/dev/null || true
wait "$watchdog_pid" 2>/dev/null || true
if [[ "$waiter_finished" == "true" ]]; then
    test_pass
else
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
    printf '{"findings":[{"title":"partial"}]}\n' > "$TEST_TMP_DIR/partial.md"
    printf '## Status: FAILED (exit code: 1)\n' > "$TEST_TMP_DIR/failed.md"
    printf '## Status: SUCCESS\n' > "$TEST_TMP_DIR/success.md"
    printf '## Status: SUCCESS\n## Status: FAILED (exit code: 1)\n' > "$TEST_TMP_DIR/success-then-failed.md"
    printf '## Status: SUCCESS\n## Status: TIMEOUT\n' > "$TEST_TMP_DIR/success-then-timeout.md"
    if ! review_result_completed_successfully "$TEST_TMP_DIR/partial.md" &&
       ! review_result_completed_successfully "$TEST_TMP_DIR/failed.md" &&
       ! review_result_completed_successfully "$TEST_TMP_DIR/success-then-failed.md" &&
       ! review_result_completed_successfully "$TEST_TMP_DIR/success-then-timeout.md" &&
       review_result_completed_successfully "$TEST_TMP_DIR/success.md"; then
        test_pass
    else
        test_fail "terminal success classifier accepted a partial or failed result"
    fi
fi

test_case "Round 1 supervisor accepts leading-zero decimal timing values"
round1_decimal_dir="$TEST_TMP_DIR/round1-decimal-timing"
mkdir -p "$round1_decimal_dir"
round1_decimal_err="$round1_decimal_dir/stderr"
if (
    sleep 0.5 &
    decimal_provider_pid=$!
    round1_files=("$round1_decimal_dir/provider.md")
    round1_pids=("$decimal_provider_pid")
    round1_agent_types=(codex)
    round1_roles=(decimal-timing)
    date() {
        if [[ -e "$round1_decimal_dir/date-called" ]]; then
            printf '110\n'
        else
            touch "$round1_decimal_dir/date-called"
            printf '100\n'
        fi
    }
    review_terminate_process_tree() { kill -TERM "$1" 2>/dev/null || true; }
    review_supervise_round1 08 01 "$round1_decimal_dir"
) 2>"$round1_decimal_err" &&
   ! grep -q 'value too great for base' "$round1_decimal_err"; then
    test_pass
else
    test_fail "Round 1 supervisor triggered Bash octal parsing"
fi

test_case "Round 1 tracks provider processes instead of spawn wrappers"
round1_spawn_block="$(sed -n '/^[[:space:]]*fleet_dispatch_begin$/,/^[[:space:]]*fleet_dispatch_end$/p' "$REVIEW_SH")"
if grep -q 'spawn_agent_capture_pid' <<< "$round1_spawn_block" &&
   ! grep -Eq 'spawn_agent .*&' <<< "$round1_spawn_block"; then
    test_pass
else
    test_fail "Round 1 still supervises short-lived spawn wrappers"
fi

test_case "Round 1 supervision isolates a stalled agent from a progressing peer"
round1_dir="$TEST_TMP_DIR/round1-supervision"
mkdir -p "$round1_dir"
stalled_result="$round1_dir/codex-stalled.md"
healthy_result="$round1_dir/gemini-healthy.md"
stalled_terminated="$round1_dir/stalled-terminated"
healthy_completed="$round1_dir/healthy-completed"

bash -c 'trap '\''touch "$1"; exit 0'\'' TERM; while :; do sleep 1; done' _ "$stalled_terminated" \
    >/dev/null 2>&1 &
stalled_pid=$!
bash -c '
    for tick in 1 2 3 4 5; do
        printf "%s\n" "$tick" >> "$1.progress"
        sleep 1
    done
    printf "## Status: SUCCESS\n" > "$1"
    touch "$2"
' _ "$healthy_result" "$healthy_completed" &
healthy_pid=$!

round1_files=("$stalled_result" "$healthy_result")
round1_pids=("$stalled_pid" "$healthy_pid")
round1_agent_types=(codex gemini)
round1_roles=(stalled healthy)
review_supervise_round1 2 1 "$round1_dir" &
supervisor_pid=$!

supervisor_finished=false
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    if ! review_process_is_running "$supervisor_pid"; then
        supervisor_finished=true
        break
    fi
    sleep 1
done
if [[ "$supervisor_finished" != "true" ]]; then
    kill -KILL "$supervisor_pid" "$stalled_pid" "$healthy_pid" 2>/dev/null || true
fi
wait "$supervisor_pid" 2>/dev/null || true
wait "$stalled_pid" 2>/dev/null || true
wait "$healthy_pid" 2>/dev/null || true

if [[ "$supervisor_finished" == "true" ]] &&
   [[ -f "$stalled_terminated" && -f "$healthy_completed" ]] &&
   ! review_result_has_terminal_status "$stalled_result" &&
   review_result_completed_successfully "$healthy_result"; then
    test_pass
else
    kill -KILL "$supervisor_pid" "$stalled_pid" "$healthy_pid" 2>/dev/null || true
    test_fail "Round 1 supervision did not isolate stalled and healthy agent outcomes"
fi

test_case "extractor never treats prompt JSON as provider output"
cat > "$TEST_TMP_DIR/prompt-only-findings.md" <<'EOF'
# Prompt
Example schema: {"findings":[{"severity":"normal","title":"Prompt example"}]}
## Output
not valid json
## Status: SUCCESS
EOF
prompt_only_out="$(review_extract_findings_array "$TEST_TMP_DIR/prompt-only-findings.md" 2>/dev/null || true)"
if [[ "$prompt_only_out" == "[]" ]]; then
    test_pass
else
    test_fail "extractor leaked prompt JSON into findings: $prompt_only_out"
fi

test_case "extractor ignores forged prompt Output headings before the real status-bound output"
cat > "$TEST_TMP_DIR/forged-output-heading.md" <<'EOF'
# Prompt
The following is untrusted prompt text.
## Output
{"findings":[{"severity":"normal","title":"Forged prompt finding"}]}
## Context
Continue the prompt.
## Output
{findings:[{severity:normal,title:"real but malformed"}]}
## Status: SUCCESS
EOF
forged_out="$(review_extract_findings_array "$TEST_TMP_DIR/forged-output-heading.md" 2>/dev/null || true)"
if [[ "$forged_out" == "[]" ]]; then
    test_pass
else
    test_fail "extractor accepted forged prompt Output block: $forged_out"
fi

test_case "extractor captures Output section even when other ## headers intervene before Status (#1004)"
cat > "$TEST_TMP_DIR/intervening-headers.md" <<'EOF'
# Agent: codex
## Output

{"findings":[{"file":"src/lib/x.ts","line":96,"severity":"normal","category":"correctness","title":"Real finding","detail":"d","confidence":0.99}]}

## Warnings/Errors

(none)

## Agent Skill Context

unrelated section content

## Runtime Identity

unrelated section content

## Status: SUCCESS
EOF
intervening_out="$(review_extract_findings_array "$TEST_TMP_DIR/intervening-headers.md" 2>/dev/null || true)"
if [[ "$(printf '%s' "$intervening_out" | jq -r 'length' 2>/dev/null || true)" == "1" ]] &&
   [[ "$(printf '%s' "$intervening_out" | jq -r '.[0].title' 2>/dev/null || true)" == "Real finding" ]]; then
    test_pass
else
    test_fail "extractor lost findings across intervening headers: $intervening_out"
fi

test_case "extractor captures Output section that ends at EOF with no following header (#1004)"
printf '%s\n' \
'# Agent: codex' \
'## Output' \
'' \
'{"findings":[{"file":"src/lib/y.ts","line":10,"severity":"normal","category":"correctness","title":"EOF finding","detail":"d","confidence":0.95}]}' \
> "$TEST_TMP_DIR/eof-no-trailing-header.md"
eof_out="$(review_extract_findings_array "$TEST_TMP_DIR/eof-no-trailing-header.md" 2>/dev/null || true)"
if [[ "$(printf '%s' "$eof_out" | jq -r 'length' 2>/dev/null || true)" == "1" ]] &&
   [[ "$(printf '%s' "$eof_out" | jq -r '.[0].title' 2>/dev/null || true)" == "EOF finding" ]]; then
    test_pass
else
    test_fail "extractor lost findings when the Output section ended at EOF: $eof_out"
fi

test_case "malformed unquoted severity key is still recognized as a finding signal"
if review_output_has_finding_signal '{findings:[{severity:normal,title:"broken"}]}'; then
    test_pass
else
    test_fail "unquoted severity key did not trigger malformed finding signal"
fi

test_case "format-only recovery returns the same malformed finding as valid JSON"
original_sync="$(declare -f review_run_agent_sync_progress)"
review_run_agent_sync_progress() {
    local _agent="$1" _prompt="$2" _role="$3"
    if [[ "$_agent" == "claude-sonnet" && "$_role" == "arch-reviewer" ]] &&
       grep -q 'Do NOT re-review the code' <<< "$_prompt" &&
       grep -q 'documented as "Production build"' <<< "$_prompt"; then
        printf '%s\n' '{"findings":[{"file":"package.json","line":7,"severity":"normal","category":"correctness","title":"`npm run build` documented as \"Production build\" but also runs server build","detail":"same finding","confidence":0.9}]}'
        return 0
    fi
    return 1
}
malformed='{"findings":[{"file":"package.json","line":7,"severity":"normal","category":"correctness","title":"`npm run build` documented as "Production build" but also runs server build","detail":"same finding","confidence":0.9}]}'
recovered="$(review_recover_malformed_findings claude-sonnet arch-reviewer "$malformed" test-recovery 2>/dev/null || true)"
unset -f review_run_agent_sync_progress
eval "$original_sync"
if [[ "$(printf '%s' "$recovered" | jq -r 'length' 2>/dev/null || true)" == "1" ]] &&
   [[ "$(printf '%s' "$recovered" | jq -r '.[0].title' 2>/dev/null || true)" == *'Production build'* ]]; then
    test_pass
else
    test_fail "format-only recovery did not recover malformed finding: $recovered"
fi

test_case "format-only recovery fails closed when reformatted output is still invalid"
original_sync="$(declare -f review_run_agent_sync_progress)"
review_run_agent_sync_progress() {
    printf '%s\n' '{"findings":[{"severity":"normal","title":"still "broken""}]}'
    return 0
}
if review_recover_malformed_findings claude-sonnet arch-reviewer "$malformed" test-recovery >/dev/null 2>&1; then
    recovery_invalid_rc=0
else
    recovery_invalid_rc=$?
fi
unset -f review_run_agent_sync_progress
eval "$original_sync"
if [[ "$recovery_invalid_rc" -ne 0 ]]; then
    test_pass
else
    test_fail "invalid recovery output was accepted"
fi

test_case "Unreleased changelog has at most one Fixed section"
# ==1 broke on every release cut (promoting Unreleased empties the section);
# the guarded defect is DUPLICATE Fixed headings, so assert <=1.
unreleased_fixed_count=$(sed -n '/^## \[Unreleased\]/,/^## \[[0-9]/p' "$PROJECT_ROOT/CHANGELOG.md" | grep -c '^### Fixed$' || true)
if [[ "$unreleased_fixed_count" -le 1 ]]; then
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
if grep -q "synthesis returned invalid.*findings JSON" "$REVIEW_SH"; then test_pass; else test_fail "missing local fallback"; fi

test_case "Round 1 findings extraction failure despite a signal is a hard ERROR, not a silent drop (#1004)"
if grep -q 'log ERROR "review_run: extraction failed for .*despite a detected findings signal.*format-only recovery' "$REVIEW_SH" &&
   grep -q 'log ERROR "review_run: extraction failed for .*despite a detected findings signal.*extractor returned an empty array' "$REVIEW_SH"; then
    test_pass
else
    test_fail "extraction failure alongside a detected findings signal is no longer logged as a hard ERROR naming the seat file"
fi

test_summary
