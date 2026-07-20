#!/usr/bin/env bash
# Regression: embedded status text must not end provider supervision early.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/octo-review-terminal.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

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

echo "PASS: review supervision requires the final completion footer"
