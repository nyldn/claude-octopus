#!/bin/bash
# Claude Octopus Careful Mode Hook (v9.8.0)
# PreToolUse hook on Bash that warns before destructive command patterns.
# Activated by /octo:careful command (writes state file).
# Returns JSON decision: {"decision":"allow"} or {"permissionDecision":"ask","message":"..."}
#
# Kill switch: OCTO_CAREFUL_MODE=off — disables all destructive command checks
set -euo pipefail
# EXIT trap — emits diagnostic stderr ONLY when the hook exits non-zero, so
# the Claude Code harness error "No stderr output" can never recur. EXIT (not
# ERR) avoids over-firing on intermediate `grep -o`/`cmd | ...` inside $() that
# the hook's logic already handles. See issue #313.
_octo_hook_exit() { local c=$?; if [[ $c -ne 0 ]]; then echo "[hook:$(basename "$0")] exit $c" >&2 2>/dev/null || true; fi; return 0; }
trap _octo_hook_exit EXIT


# Kill switch — respect user's choice to disable careful mode entirely
# (careful mode is opt-in via /octo:careful; OCTO_CAREFUL_MODE=off is the dedicated off-switch)
[[ "${OCTO_CAREFUL_MODE:-on}" == "off" ]] && { echo '{"decision":"allow"}'; exit 0; }

# Read tool input from stdin
if command -v timeout &>/dev/null; then
    INPUT=$(timeout 3 cat 2>/dev/null || true)
else
    INPUT=$(cat 2>/dev/null || true)
fi
[[ -z "$INPUT" ]] && INPUT='{}'

# Only gate Bash commands
TOOL_NAME=$(echo "$INPUT" | grep -o '"tool_name":"[^"]*"' 2>/dev/null | head -1 | cut -d'"' -f4 || true)
if [[ "$TOOL_NAME" != "Bash" ]]; then
    echo '{"decision":"allow"}'
    exit 0
fi

# Check if careful mode is active
STATE_FILE="/tmp/octopus-careful-${CLAUDE_SESSION_ID:-$$}.txt"
if [[ ! -f "$STATE_FILE" ]]; then
    echo '{"decision":"allow"}'
    exit 0
fi

# Extract command from input — use jq if available, fall back to grep
# Note: grep-based extraction truncates at escaped quotes, so we also check raw INPUT
if command -v jq &>/dev/null; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // .command // ""' 2>/dev/null || echo "")
else
    COMMAND=$(echo "$INPUT" | grep -o '"command":"[^"]*"' 2>/dev/null | head -1 | cut -d'"' -f4 || true)
fi
# Also check raw input as fallback for escaped-quote edge cases
CHECK_TEXT="${COMMAND}
${INPUT}"
if [[ -z "$COMMAND" && -z "$INPUT" ]]; then
    echo '{"decision":"allow"}'
    exit 0
fi

# ── Destructive pattern checks ────────────────────────────────────────

# 1. rm -rf — but allow safe exceptions (node_modules, dist, .next, __pycache__, build, coverage, .turbo)
if echo "$CHECK_TEXT" | grep -qE 'rm\s+-[a-zA-Z]*r[a-zA-Z]*f|rm\s+-r\s+-f|rm\s+-f\s+-r|rm\s+--recursive\s+--force'; then
    # Check if the target is a safe exception
    safe=false
    for safe_dir in node_modules dist .next __pycache__ build coverage .turbo; do
        if echo "$CHECK_TEXT" | grep -qE "rm\s+.*${safe_dir}(\s|$|/)"; then
            safe=true
            break
        fi
    done
    if [[ "$safe" == "false" ]]; then
        echo '{"permissionDecision":"ask","message":"⚠️ Destructive command detected: rm -rf. This recursively force-deletes files. Confirm you want to proceed."}'
        exit 0
    fi
fi

# 2. SQL destructive operations
if echo "$CHECK_TEXT" | grep -qiE 'DROP\s+TABLE|DROP\s+DATABASE|TRUNCATE'; then
    matched=$(echo "$CHECK_TEXT" | grep -oiE 'DROP\s+TABLE|DROP\s+DATABASE|TRUNCATE' | head -1)
    echo "{\"permissionDecision\":\"ask\",\"message\":\"⚠️ Destructive SQL detected: ${matched}. This permanently destroys data. Confirm you want to proceed.\"}"
    exit 0
fi

# 3. git push --force / -f
if echo "$CHECK_TEXT" | grep -qE 'git\s+push\s+.*--force|git\s+push\s+.*-f'; then
    echo '{"permissionDecision":"ask","message":"⚠️ Destructive command detected: git push --force. This rewrites remote history and can cause data loss for collaborators. Confirm you want to proceed."}'
    exit 0
fi

# 4. git reset --hard
if echo "$CHECK_TEXT" | grep -qE 'git\s+reset\s+--hard'; then
    echo '{"permissionDecision":"ask","message":"⚠️ Destructive command detected: git reset --hard. This discards all uncommitted changes. Confirm you want to proceed."}'
    exit 0
fi

# 5. git checkout . / git restore .
if echo "$CHECK_TEXT" | grep -qE 'git\s+checkout\s+\.|git\s+restore\s+\.'; then
    echo '{"permissionDecision":"ask","message":"⚠️ Destructive command detected: git checkout/restore. This discards all unstaged changes. Confirm you want to proceed."}'
    exit 0
fi

# 6. kubectl delete
if echo "$CHECK_TEXT" | grep -qE 'kubectl\s+delete'; then
    echo '{"permissionDecision":"ask","message":"⚠️ Destructive command detected: kubectl delete. This removes Kubernetes resources. Confirm you want to proceed."}'
    exit 0
fi

# 7. docker rm -f / docker system prune
if echo "$CHECK_TEXT" | grep -qE 'docker\s+rm\s+-f|docker\s+system\s+prune'; then
    matched=$(echo "$CHECK_TEXT" | grep -oE 'docker\s+(rm\s+-f|system\s+prune)' | head -1)
    echo "{\"permissionDecision\":\"ask\",\"message\":\"⚠️ Destructive command detected: ${matched}. This forcefully removes Docker resources. Confirm you want to proceed.\"}"
    exit 0
fi

# All checks passed
echo '{"decision":"allow"}'
exit 0
