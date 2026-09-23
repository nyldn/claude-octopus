#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
log() { :; }
source "$PROJECT_ROOT/scripts/lib/heartbeat.sh"

test_suite "Provider stall watchdog"

_pid_is_live() {
    local pid="$1" stat=""
    [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    stat="$(ps -o stat= -p "$pid" 2>/dev/null | tr -d '[:space:]')"
    [[ -n "$stat" && "$stat" != Z* ]]
}

test_case "portable supervisor supports true unbounded timeout zero"
SECONDS=0
if OCTOPUS_PRESERVE_CALLER_PROCESS_GROUP=true \
   run_with_timeout --portable-supervisor 0 /bin/sh -c 'sleep 1; printf done' \
       > "$TEST_TMP_DIR/unbounded.out" 2>/dev/null; then
    if [[ "$(cat "$TEST_TMP_DIR/unbounded.out")" == done && "$SECONDS" -ge 1 && "$SECONDS" -lt 5 ]]; then
        test_pass
    else
        test_fail "unbounded supervised call returned unexpected output or duration"
    fi
else
    test_fail "portable supervisor rejected timeout=0"
fi

test_case "unbounded supervisor preserves shell-function exit status"
unbounded_provider_exit() { exit 37; }
rc=0
OCTOPUS_PRESERVE_CALLER_PROCESS_GROUP=true \
    run_with_timeout --portable-supervisor 0 unbounded_provider_exit || rc=$?
unset -f unbounded_provider_exit
if [[ "$rc" -eq 37 ]]; then
    test_pass
else
    test_fail "unbounded shell function returned rc=$rc instead of 37"
fi

test_case "unbounded supervisor preserves exec-based provider status"
unbounded_provider_exec() { exec /bin/sh -c 'exit 23'; }
rc=0
OCTOPUS_PRESERVE_CALLER_PROCESS_GROUP=true \
    run_with_timeout --portable-supervisor 0 unbounded_provider_exec || rc=$?
unset -f unbounded_provider_exec
if [[ "$rc" -eq 23 ]]; then
    test_pass
else
    test_fail "unbounded exec-based provider returned rc=$rc instead of 23"
fi

test_case "unbounded supervisor contains descendants after provider completion"
child_file="$TEST_TMP_DIR/unbounded-child.pid"
provider="$TEST_TMP_DIR/unbounded-descendant-provider.sh"
cat > "$provider" <<'EOF'
#!/bin/sh
child_file="$1"
/bin/sh -c 'trap "" TERM; exec sleep 30' &
printf '%s\n' "$!" > "$child_file"
EOF
chmod +x "$provider"
rc=0
OCTOPUS_PRESERVE_CALLER_PROCESS_GROUP=true \
    run_with_timeout --portable-supervisor 0 "$provider" "$child_file" || rc=$?
child_pid="$(cat "$child_file" 2>/dev/null || true)"
sleep 0.2
if [[ "$rc" -eq 0 && -n "$child_pid" ]] && ! _pid_is_live "$child_pid"; then
    test_pass
else
    [[ -n "$child_pid" ]] && kill -KILL "$child_pid" 2>/dev/null || true
    test_fail "unbounded provider descendant survived normal completion (rc=$rc child=${child_pid:-missing})"
fi

test_case "silent provider is classified as stalled instead of wall-clock timeout"
raw="$TEST_TMP_DIR/stalled.raw"
err="$TEST_TMP_DIR/stalled.err"
hint="$TEST_TMP_DIR/stalled.in"
rc=0
SECONDS=0
OCTOPUS_PROVIDER_STALL_WINDOW=2 OCTOPUS_PROVIDER_STALL_POLL_SECS=1 \
    octopus_capture_provider_output "prompt" 0 "$hint" "$raw" "$err" \
        /bin/sh -c 'sleep 30' || rc=$?
if [[ "$rc" -eq 76 && "$SECONDS" -ge 2 && "$SECONDS" -lt 10 ]]; then
    test_pass
else
    test_fail "expected rc=76 after short inactivity; got rc=$rc elapsed=${SECONDS}s"
fi

test_case "observable provider output resets the stall window"
raw="$TEST_TMP_DIR/progress.raw"
err="$TEST_TMP_DIR/progress.err"
hint="$TEST_TMP_DIR/progress.in"
rc=0
OCTOPUS_PROVIDER_STALL_WINDOW=2 OCTOPUS_PROVIDER_STALL_POLL_SECS=1 \
    octopus_capture_provider_output "prompt" 0 "$hint" "$raw" "$err" \
        /bin/sh -c 'printf a; sleep 1; printf b; sleep 1; printf c; sleep 1; printf done' || rc=$?
if [[ "$rc" -eq 0 && "$(cat "$raw")" == abcdone ]]; then
    test_pass
else
    test_fail "progressing provider was stalled or output was lost (rc=$rc)"
fi

test_case "poll interval is capped so progress is checked before stalling"
if [[ "$(_octo_bounded_stall_poll_secs 2 30)" == 2 ]] &&
   [[ "$(_octo_bounded_stall_poll_secs 2 1)" == 1 ]] &&
   [[ "$(_octo_bounded_stall_poll_secs 2 2)" == 2 ]]; then
    test_pass
else
    test_fail "poll interval was not bounded by the stall window"
fi

test_case "completed silent provider is not classified as stalled"
raw="$TEST_TMP_DIR/completed-silent.raw"
err="$TEST_TMP_DIR/completed-silent.err"
hint="$TEST_TMP_DIR/completed-silent.in"
rc=0
OCTOPUS_PROVIDER_STALL_WINDOW=1 OCTOPUS_PROVIDER_STALL_POLL_SECS=1 \
    octopus_capture_provider_output "prompt" 0 "$hint" "$raw" "$err" \
        /bin/sh -c 'sleep 0.2' || rc=$?
if [[ "$rc" -eq 0 ]]; then
    test_pass
else
    test_fail "completed provider was classified as stalled (rc=$rc)"
fi

test_case "provider completion during the final activity sample wins over stall classification"
raw="$TEST_TMP_DIR/final-completion.raw"
err="$TEST_TMP_DIR/final-completion.err"
hint="$TEST_TMP_DIR/final-completion.in"
release="$TEST_TMP_DIR/final-completion.release"
done_marker="$TEST_TMP_DIR/final-completion.done"
signature_calls="$TEST_TMP_DIR/final-completion.calls"
provider="$TEST_TMP_DIR/final-completion-provider.sh"
cat > "$provider" <<'EOF'
#!/bin/sh
release="$1"
done_marker="$2"
while [ ! -e "$release" ]; do sleep 0.01; done
: > "$done_marker"
EOF
chmod +x "$provider"
original_activity_signature="$(declare -f _octo_capture_activity_signature)"
_octo_capture_activity_signature() {
    local calls=0
    [[ ! -f "$signature_calls" ]] || calls="$(cat "$signature_calls")"
    calls=$((calls + 1))
    printf '%s\n' "$calls" > "$signature_calls"
    if [[ "$calls" -eq 3 ]]; then
        : > "$release"
        while [[ ! -e "$done_marker" ]]; do sleep 0.01; done
        local wait_attempts=0
        while [[ ! -s "$rc_file" && "$wait_attempts" -lt 200 ]]; do
            sleep 0.01
            wait_attempts=$((wait_attempts + 1))
        done
    fi
    printf '%s\n' stable
}
rc=0
OCTOPUS_PROVIDER_STALL_WINDOW=1 OCTOPUS_PROVIDER_STALL_POLL_SECS=1 \
    octopus_capture_provider_output "prompt" 0 "$hint" "$raw" "$err" \
        "$provider" "$release" "$done_marker" || rc=$?
eval "$original_activity_signature"
if [[ "$rc" -eq 0 ]]; then
    test_pass
else
    test_fail "provider completion at the stall boundary was misclassified (rc=$rc)"
fi

test_case "progress in the final poll interval resets the stall window"
raw="$TEST_TMP_DIR/final-poll.raw"
err="$TEST_TMP_DIR/final-poll.err"
hint="$TEST_TMP_DIR/final-poll.in"
rc=0
OCTOPUS_PROVIDER_STALL_WINDOW=3 OCTOPUS_PROVIDER_STALL_POLL_SECS=2 \
    octopus_capture_provider_output "prompt" 0 "$hint" "$raw" "$err" \
        /bin/sh -c 'sleep 2.2; printf progress; sleep 1; printf done' || rc=$?
if [[ "$rc" -eq 0 && "$(cat "$raw")" == progressdone ]]; then
    test_pass
else
    test_fail "progress after the scheduled probe was missed (rc=$rc)"
fi

test_case "silent provider worktree writes reset the stall window"
repo="$TEST_TMP_DIR/progress-repo"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email test@example.invalid
git -C "$repo" config user.name Test
printf 'base\n' > "$repo/progress.txt"
git -C "$repo" add progress.txt
git -C "$repo" commit -qm base
writer="$TEST_TMP_DIR/worktree-writer.sh"
cat > "$writer" <<'EOF'
#!/bin/sh
repo="$1"
sleep 1
printf 'one\n' >> "$repo/progress.txt"
sleep 1
printf 'two\n' >> "$repo/progress.txt"
sleep 1
printf 'three\n' >> "$repo/progress.txt"
sleep 1
EOF
chmod +x "$writer"
raw="$TEST_TMP_DIR/worktree.raw"
err="$TEST_TMP_DIR/worktree.err"
hint="$TEST_TMP_DIR/worktree.in"
rc=0
OCTOPUS_PROVIDER_STALL_WINDOW=2 OCTOPUS_PROVIDER_STALL_POLL_SECS=1 OCTOPUS_PROVIDER_STALL_WORKTREE="$repo" \
    octopus_capture_provider_output "prompt" 0 "$hint" "$raw" "$err" \
        "$writer" "$repo" || rc=$?
if [[ "$rc" -eq 0 && "$(wc -l < "$repo/progress.txt" | tr -d ' ')" -eq 4 ]]; then
    test_pass
else
    test_fail "observable worktree progress did not keep provider healthy (rc=$rc)"
fi

test_case ".octo housekeeping does not reset the stall window"
repo="$TEST_TMP_DIR/octo-state-repo"
mkdir -p "$repo/.octo"
git -C "$repo" init -q
git -C "$repo" config user.email test@example.invalid
git -C "$repo" config user.name Test
printf '.octo/\n' > "$repo/.gitignore"
printf 'base\n' > "$repo/.octo/events.log"
git -C "$repo" add .gitignore
git -C "$repo" add -f .octo/events.log
git -C "$repo" commit -qm base
state_writer="$TEST_TMP_DIR/octo-state-writer.sh"
cat > "$state_writer" <<'EOF'
#!/bin/sh
repo="$1"
while :; do
    date +%s >> "$repo/.octo/events.log"
    sleep 1
done
EOF
chmod +x "$state_writer"
raw="$TEST_TMP_DIR/octo-state.raw"
err="$TEST_TMP_DIR/octo-state.err"
hint="$TEST_TMP_DIR/octo-state.in"
rc=0
OCTOPUS_PROVIDER_STALL_WINDOW=2 OCTOPUS_PROVIDER_STALL_POLL_SECS=1 OCTOPUS_PROVIDER_STALL_WORKTREE="$repo" \
    octopus_capture_provider_output "prompt" 0 "$hint" "$raw" "$err" \
        "$state_writer" "$repo" || rc=$?
if [[ "$rc" -eq 76 ]]; then
    test_pass
else
    test_fail ".octo state writes prevented stall detection (rc=$rc)"
fi

test_case "explicit wall-clock timeout still caps a progressing provider"
raw="$TEST_TMP_DIR/bounded.raw"
err="$TEST_TMP_DIR/bounded.err"
hint="$TEST_TMP_DIR/bounded.in"
rc=0
OCTOPUS_PROVIDER_STALL_WINDOW=10 OCTOPUS_PROVIDER_STALL_POLL_SECS=1 \
    octopus_capture_provider_output "prompt" 2 "$hint" "$raw" "$err" \
        /bin/sh -c 'while :; do printf x; sleep 1; done' || rc=$?
if [[ "$rc" -eq 124 ]]; then
    test_pass
else
    test_fail "explicit wall-clock timeout did not cap progressing provider (rc=$rc)"
fi

test_case "stall cleanup terminates provider descendants"
raw="$TEST_TMP_DIR/tree.raw"
err="$TEST_TMP_DIR/tree.err"
hint="$TEST_TMP_DIR/tree.in"
child_file="$TEST_TMP_DIR/tree-child.pid"
provider="$TEST_TMP_DIR/stalling-provider.sh"
cat > "$provider" <<'EOF'
#!/bin/sh
child_file="$1"
/bin/sh -c 'trap "" TERM; exec sleep 30' &
printf '%s\n' "$!" > "$child_file"
sleep 30
EOF
chmod +x "$provider"
rc=0
OCTOPUS_PROVIDER_STALL_WINDOW=2 OCTOPUS_PROVIDER_STALL_POLL_SECS=1 \
    octopus_capture_provider_output "prompt" 0 "$hint" "$raw" "$err" \
        "$provider" "$child_file" || rc=$?
child_pid="$(cat "$child_file" 2>/dev/null || true)"
sleep 0.2
if [[ "$rc" -eq 76 && -n "$child_pid" ]] && ! _pid_is_live "$child_pid"; then
    test_pass
else
    [[ -n "$child_pid" ]] && kill -KILL "$child_pid" 2>/dev/null || true
    test_fail "stalled provider descendant survived cleanup (rc=$rc child=${child_pid:-missing})"
fi

test_case "invalid stall configuration fails before provider launch"
marker="$TEST_TMP_DIR/should-not-run"
rc=0
OCTOPUS_PROVIDER_STALL_WINDOW=invalid OCTOPUS_PROVIDER_STALL_POLL_SECS=1 \
    octopus_capture_provider_output "prompt" 0 "$TEST_TMP_DIR/invalid.in" \
        "$TEST_TMP_DIR/invalid.raw" "$TEST_TMP_DIR/invalid.err" \
        /bin/sh -c "touch '$marker'" || rc=$?
if [[ "$rc" -eq 2 && ! -e "$marker" ]]; then
    test_pass
else
    test_fail "invalid stall config did not fail closed (rc=$rc)"
fi

test_summary
