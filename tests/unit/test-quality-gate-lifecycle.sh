#!/usr/bin/env bash
# Regression: failed tangle gates are scoped and explicitly acknowledgeable.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$ROOT_DIR/hooks/quality-gate.sh"
TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/octo-quality-gate.XXXXXX")"
trap 'rm -rf "$TEST_HOME"' EXIT

WORKSPACE_A="$TEST_HOME/workspace-a"
WORKSPACE_B="$TEST_HOME/workspace-b"
RESULTS="$TEST_HOME/.claude-octopus/results"
mkdir -p "$WORKSPACE_A" "$WORKSPACE_B" "$RESULTS"
WORKSPACE_A="$(cd "$WORKSPACE_A" && pwd -P)"
WORKSPACE_B="$(cd "$WORKSPACE_B" && pwd -P)"
REPORT="$RESULTS/tangle-validation-test.md"

cat > "$REPORT" <<EOF
# TANGLE Phase Validation Report
## Gate ID: tangle-test
## Workspace: $WORKSPACE_A
## Session: session-a
### Quality Gate: FAILED
EOF

matching_output="$(cd "$WORKSPACE_A" && HOME="$TEST_HOME" CLAUDE_SESSION_ID=session-a bash "$HOOK")"
grep -Fq '"decision": "block"' <<<"$matching_output" || {
  echo "FAIL: matching failed gate did not block" >&2
  exit 1
}

other_workspace_output="$(cd "$WORKSPACE_B" && HOME="$TEST_HOME" CLAUDE_SESSION_ID=session-a bash "$HOOK")"
[[ -z "$other_workspace_output" ]] || {
  echo "FAIL: gate leaked into another workspace" >&2
  exit 1
}

other_session_output="$(cd "$WORKSPACE_A" && HOME="$TEST_HOME" CLAUDE_SESSION_ID=session-b bash "$HOOK")"
[[ -z "$other_session_output" ]] || {
  echo "FAIL: gate leaked into another session" >&2
  exit 1
}

other_workspace_status="$(cd "$WORKSPACE_B" && HOME="$TEST_HOME" CLAUDE_SESSION_ID=session-a bash "$HOOK" --status)"
grep -Fq 'No active quality gate for this workspace/session.' <<<"$other_workspace_status" || {
  echo "FAIL: gate status displayed an unrelated report as active" >&2
  printf '%s\n' "$other_workspace_status" >&2
  exit 1
}

ack_output="$(cd "$WORKSPACE_A" && HOME="$TEST_HOME" CLAUDE_SESSION_ID=session-a bash "$HOOK" --ack "$REPORT")"
grep -Fq 'Acknowledged quality gate tangle-test' <<<"$ack_output" || {
  echo "FAIL: acknowledgement command failed" >&2
  exit 1
}

acknowledged_output="$(cd "$WORKSPACE_A" && HOME="$TEST_HOME" CLAUDE_SESSION_ID=session-a bash "$HOOK")"
[[ -z "$acknowledged_output" ]] || {
  echo "FAIL: acknowledged gate continued blocking" >&2
  exit 1
}

printf '\nChanged after review.\n' >> "$REPORT"
changed_output="$(cd "$WORKSPACE_A" && HOME="$TEST_HOME" CLAUDE_SESSION_ID=session-a bash "$HOOK")"
grep -Fq '"decision": "block"' <<<"$changed_output" || {
  echo "FAIL: changed report incorrectly reused stale acknowledgement" >&2
  exit 1
}

grep -Fq '## Gate ID:' "$ROOT_DIR/scripts/lib/testing.sh" || {
  echo "FAIL: validation reports do not record a gate ID" >&2
  exit 1
}
grep -Fq '## Workspace:' "$ROOT_DIR/scripts/lib/testing.sh" || {
  echo "FAIL: validation reports do not record workspace scope" >&2
  exit 1
}
grep -Fq '## Session:' "$ROOT_DIR/scripts/lib/testing.sh" || {
  echo "FAIL: validation reports do not record session scope" >&2
  exit 1
}

echo "PASS: quality gate lifecycle is scoped and acknowledgeable"
