#!/bin/bash
# Claude Octopus Freeze Mode Hook (v9.8.0)
# PreToolUse hook on Edit/Write/apply_patch that blocks writes outside a frozen boundary.
# Activated by /octo:freeze command (writes directory to state file).
# Read, Bash, Glob, Grep are unaffected — investigation stays unrestricted.
# Returns JSON decision: {"decision":"allow"} or {"permissionDecision":"deny","message":"..."}
#
# Kill switch: OCTO_FREEZE_MODE=off — disables freeze boundary enforcement
set -euo pipefail
# EXIT trap — emits diagnostic stderr ONLY when the hook exits non-zero, so
# the Claude Code harness error "No stderr output" can never recur. EXIT (not
# ERR) avoids over-firing on intermediate `grep -o`/`cmd | ...` inside $() that
# the hook's logic already handles. See issue #313.
_octo_hook_exit() { local c=$?; if [[ $c -ne 0 ]]; then echo "[hook:$(basename "$0")] exit $c" >&2 2>/dev/null || true; fi; return 0; }
trap _octo_hook_exit EXIT

_HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_HOOK_DIR/../scripts/lib/session-id.sh" 2>/dev/null || true

# Kill switch — freeze mode is opt-in via /octo:freeze; OCTO_FREEZE_MODE=off is the dedicated off-switch
[[ "${OCTO_FREEZE_MODE:-on}" == "off" ]] && exit 0

# Read tool input from stdin
if command -v timeout &>/dev/null; then
    INPUT=$(timeout 3 cat 2>/dev/null || true)
else
    INPUT=$(cat 2>/dev/null || true)
fi
[[ -z "$INPUT" ]] && INPUT='{}'

# Check if freeze mode is active
if declare -f octo_session_state_file >/dev/null 2>&1; then
    STATE_FILE=$(octo_session_state_file "freeze" "txt" "$INPUT")
else
    STATE_FILE="/tmp/octopus-freeze-${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-$$}}.txt"
fi
if [[ ! -f "$STATE_FILE" ]]; then
    : # pass-through — current hook schema treats silence as continue
    exit 0
fi

# The helper checks "Edit" and "Write" file_path values and every apply_patch
# Add/Update/Delete/Move target, using cwd from the hook JSON. Unknown patches
# fail closed. Python resolves symlinks and '..' before comparing path components.
FREEZE_DIR=$(<"$STATE_FILE")
# FREEZE_DIR/src and FREEZE_DIR/src-other are distinct path components.
if ! printf '%s' "$INPUT" | python3 "$_HOOK_DIR/safety-contract.py" freeze "$FREEZE_DIR" 2>/dev/null; then
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Freeze mode could not validate the file operation. Check that Python 3 is installed and the safety helper is available before retrying."}}'
fi
exit 0
