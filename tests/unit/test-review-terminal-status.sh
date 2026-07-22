#!/usr/bin/env bash
# Regression: embedded status text must not end provider supervision early.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/octo-review-terminal.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

log() { :; }
source "$ROOT_DIR/scripts/lib/review.sh"

cat > "$TMP_DIR/running.md" <<'EOF'
# Prompt
Prior context:
## Status: SUCCESS
# Completed: yesterday

## Output
provider still writing
EOF

cat > "$TMP_DIR/success.md" <<'EOF'
# Prompt
## Status: FAILED (exit code: 1)
# Completed: yesterday

## Output
{"findings":[]}
## Status: SUCCESS
# Completed: now
EOF

cat > "$TMP_DIR/failed.md" <<'EOF'
# Prompt
## Status: SUCCESS
# Completed: yesterday

## Output
(no output)
## Status: FAILED (exit code: 1)
# Completed: now
EOF

! review_result_has_terminal_status "$TMP_DIR/running.md" || {
    echo "FAIL: embedded completion text ended a running provider" >&2
    exit 1
}
review_result_has_terminal_status "$TMP_DIR/success.md" || {
    echo "FAIL: completed success was not terminal" >&2
    exit 1
}
review_result_completed_successfully "$TMP_DIR/success.md" || {
    echo "FAIL: completed success was classified as failed" >&2
    exit 1
}
! review_result_completed_successfully "$TMP_DIR/failed.md" || {
    echo "FAIL: embedded success masked the final failure" >&2
    exit 1
}

export OCTOPUS_REVIEW_RESULT_FLUSH_GRACE_SECS=3
delayed="$TMP_DIR/delayed.md"
(
    sleep 1
    printf '## Status: SUCCESS\n# Completed: now\n' > "$delayed"
) &
delayed_writer=$!
delayed_start=$(date +%s)
review_wait_for_result_status "$delayed" 999999 "delayed wrapper" "$TMP_DIR" 5 1
delayed_elapsed=$(( $(date +%s) - delayed_start ))
wait "$delayed_writer"
[[ "$delayed_elapsed" -ge 1 ]] && review_result_completed_successfully "$delayed" || {
    echo "FAIL: retry waiter did not allow wrapper footer flush" >&2
    exit 1
}

round_delayed="$TMP_DIR/round-delayed.md"
(
    sleep 1
    printf '## Status: SUCCESS\n# Completed: now\n' > "$round_delayed"
) &
round_writer=$!
round1_files=("$round_delayed")
round1_pids=(999998)
round1_agent_types=(openrouter-kimi-k3)
round1_roles=(diversity-reviewer)
round_start=$(date +%s)
review_supervise_round1 5 1 "$TMP_DIR"
round_elapsed=$(( $(date +%s) - round_start ))
wait "$round_writer"
[[ "$round_elapsed" -ge 1 ]] && review_result_completed_successfully "$round_delayed" || {
    echo "FAIL: Round 1 supervisor did not allow wrapper footer flush" >&2
    exit 1
}

echo "PASS: review supervision requires the final completion footer"
