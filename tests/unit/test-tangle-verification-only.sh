#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "tangle verification-only"
source "$PROJECT_ROOT/scripts/lib/workflows.sh"

TEST_ROOT="$TEST_TMP_DIR/tangle-verification-only"
SOURCE_REPO="$TEST_ROOT/source"
WORKSPACE_DIR="$TEST_ROOT/state"
RESULTS_DIR="$TEST_ROOT/results"
OCTOPUS_VERIFY_WORKTREE_ROOT="$TEST_ROOT/worktrees"
mkdir -p "$SOURCE_REPO" "$WORKSPACE_DIR" "$RESULTS_DIR"
trap 'rm -rf "$TEST_ROOT"' EXIT INT TERM

git -C "$SOURCE_REPO" init -q
git -C "$SOURCE_REPO" config user.email octopus-tests@example.invalid
git -C "$SOURCE_REPO" config user.name "Octopus Tests"
printf 'baseline\n' > "$SOURCE_REPO/baseline.txt"
git -C "$SOURCE_REPO" add baseline.txt
git -C "$SOURCE_REPO" commit -qm baseline

PROJECT_ROOT="$SOURCE_REPO"
AGENT_RESULT='{"baselinePassed":true,"defectReproduced":false,"implementationRequired":false,"evidence":{"commands":["test"],"failingTests":[],"summary":"green"}}'
RUN_AGENT_CALLS_FILE="$TEST_ROOT/run-agent-calls"
: > "$RUN_AGENT_CALLS_FILE"
SPAWN_CALLS=0
log() { :; }
run_agent_sync() {
    printf 'call\n' >> "$RUN_AGENT_CALLS_FILE"
    printf 'temporary write\n' > verification-write.txt
    printf '%s\n' "$AGENT_RESULT"
}
spawn_agent_capture_pid() {
    SPAWN_CALLS=$((SPAWN_CALLS + 1))
    return 99
}

OCTOPUS_VERIFY_RUN_ID="verified-no-change"
status=0
tangle_verify "verify existing fix" || status=$?

test_case "green baseline returns VERIFIED_NO_CHANGE"
if [[ "$status" -eq 0 && "$TANGLE_VERIFICATION_STATUS" == "VERIFIED_NO_CHANGE" ]]; then
    test_pass
else
    test_fail "unexpected status=$status verification=$TANGLE_VERIFICATION_STATUS"
fi

test_case "verification writes are discarded"
if [[ ! -e "$SOURCE_REPO/verification-write.txt" && ! -e "$OCTOPUS_VERIFY_WORKTREE_ROOT/verified-no-change" ]]; then
    test_pass
else
    test_fail "verification worktree or writes leaked"
fi

test_case "verification artifact is structured"
if jq -e '.status == "VERIFIED_NO_CHANGE" and .baselinePassed == true' "$TANGLE_VERIFICATION_RESULT_FILE" >/dev/null; then
    test_pass
else
    test_fail "verification artifact is invalid"
fi

test_case "verification never launches implementers"
run_agent_calls=$(wc -l < "$RUN_AGENT_CALLS_FILE" | tr -d '[:space:]')
if [[ "$run_agent_calls" -eq 1 && "$SPAWN_CALLS" -eq 0 ]]; then
    test_pass
else
    test_fail "unexpected run/spawn calls: $run_agent_calls/$SPAWN_CALLS"
fi

AGENT_RESULT='{"baselinePassed":false,"defectReproduced":true,"implementationRequired":true,"evidence":{"commands":["test"],"failingTests":["example"],"summary":"reproduced"}}'
OCTOPUS_VERIFY_RUN_ID="defect-reproduced"
status=0
tangle_verify "reproduce defect" || status=$?

test_case "reproduced defect does not auto-implement"
if [[ "$status" -eq 2 && "$TANGLE_VERIFICATION_STATUS" == "DEFECT_REPRODUCED" && "$SPAWN_CALLS" -eq 0 ]]; then
    test_pass
else
    test_fail "reproduced defect status was not preserved"
fi


test_case "unsafe verification run IDs are rejected"
for unsafe_id in "../escape" "/absolute" "nested/path" "bad id" ".."; do
    OCTOPUS_VERIFY_RUN_ID="$unsafe_id"
    status=0
    tangle_verify "unsafe id" >/dev/null 2>&1 || status=$?
    if [[ "$status" -eq 0 ]]; then
        test_fail "unsafe run ID was accepted: $unsafe_id"
        break
    fi
done
if [[ "${status:-1}" -ne 0 ]]; then
    test_pass
fi

AGENT_RESULT='{"baselinePassed":true,"defectReproduced":false,"implementationRequired":true,"evidence":{"commands":["test"],"failingTests":[],"summary":"contradictory"}}'
OCTOPUS_VERIFY_RUN_ID="contradictory-result"
status=0
tangle_verify "reject contradictory result" || status=$?

test_case "contradictory verification fails closed"
if [[ "$status" -eq 1 \
    && "$TANGLE_VERIFICATION_STATUS" == "NEEDS_DIAGNOSIS" \
    && "$(jq -r '.error' "$TANGLE_VERIFICATION_RESULT_FILE")" == "invalid verification result" ]]; then
    test_pass
else
    test_fail "contradictory verification was accepted"
fi

AGENT_RESULT='{"baselinePassed":false,"defectReproduced":true,"implementationRequired":true,"evidence":{"commands":[7],"failingTests":[],"summary":"bad command evidence"}}'
OCTOPUS_VERIFY_RUN_ID="non-string-command-evidence"
status=0
tangle_verify "reject non-string command evidence" || status=$?

test_case "non-string command evidence fails closed"
if [[ "$status" -eq 1 \
    && "$TANGLE_VERIFICATION_STATUS" == "NEEDS_DIAGNOSIS" \
    && "$(jq -r '.error' "$TANGLE_VERIFICATION_RESULT_FILE")" == "invalid verification result" ]]; then
    test_pass
else
    test_fail "non-string command evidence was accepted"
fi

AGENT_RESULT='{"baselinePassed":false,"defectReproduced":true,"implementationRequired":true,"evidence":{"commands":["test"],"failingTests":[false],"summary":"bad failing-test evidence"}}'
OCTOPUS_VERIFY_RUN_ID="non-string-failing-test-evidence"
status=0
tangle_verify "reject non-string failing-test evidence" || status=$?

test_case "non-string failing-test evidence fails closed"
if [[ "$status" -eq 1 \
    && "$TANGLE_VERIFICATION_STATUS" == "NEEDS_DIAGNOSIS" \
    && "$(jq -r '.error' "$TANGLE_VERIFICATION_RESULT_FILE")" == "invalid verification result" ]]; then
    test_pass
else
    test_fail "non-string failing-test evidence was accepted"
fi

AGENT_RESULT='not-json'
OCTOPUS_VERIFY_RUN_ID="invalid-result"
status=0
tangle_verify "invalid result" || status=$?

test_case "malformed verification fails closed"
if [[ "$status" -eq 1 && "$TANGLE_VERIFICATION_STATUS" == "NEEDS_DIAGNOSIS" ]]; then
    test_pass
else
    test_fail "malformed verification did not fail closed"
fi

# ── caller traps must survive tangle_verify ──────────────────────────────────
# tangle_cleanup_verification_context used to run `trap - EXIT INT TERM`, which
# discarded orchestrate.sh's own EXIT trap (the one that removes
# $OCTOPUS_TMP_DIR) and leaked a temp directory on every verify run.
test_case "tangle_verify restores the caller's EXIT trap"
trap_probe="$TEST_ROOT/trap-probe"
rm -f "$trap_probe"
(
    trap 'printf caller-trap-ran > "'"$trap_probe"'"' EXIT
    AGENT_RESULT='not-json'
    OCTOPUS_VERIFY_RUN_ID="trap-restore"
    tangle_verify "trap restore probe" >/dev/null 2>&1 || true
) || true
if [[ -f "$trap_probe" && "$(cat "$trap_probe")" == "caller-trap-ran" ]]; then
    test_pass
else
    test_fail "caller EXIT trap was cleared by tangle_verify (temp dirs would leak)"
fi

test_summary
