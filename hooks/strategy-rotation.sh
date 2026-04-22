#!/usr/bin/env bash
# Claude Octopus — Strategy Rotation Hook
# PostToolUse hook that tracks consecutive tool failures and injects
# a strategy rotation prompt when the same tool keeps failing.
#
# Prevents agents from repeating the same failing approach by forcing
# a fundamentally different strategy after N consecutive failures.
#
# Configuration:
#   OCTO_STRATEGY_ROTATION_THRESHOLD  — failures before rotation (default: 2)
#   OCTO_STRATEGY_ROTATION=off        — disable entirely
#
# State file: /tmp/octopus-failures-${CLAUDE_SESSION_ID}.json
# Hook event: PostToolUse (matcher: Bash|Edit|Write)

set -euo pipefail
# EXIT trap — emits diagnostic stderr ONLY when the hook exits non-zero, so
# the Claude Code harness error "No stderr output" can never recur. EXIT (not
# ERR) avoids over-firing on intermediate `grep -o`/`cmd | ...` inside $() that
# the hook's logic already handles. See issue #313.
_octo_hook_exit() { local c=$?; if [[ $c -ne 0 ]]; then echo "[hook:$(basename "$0")] exit $c" >&2 2>/dev/null || true; fi; return 0; }
trap _octo_hook_exit EXIT


# ── Kill switch ──────────────────────────────────────────────────────
[[ "${OCTO_STRATEGY_ROTATION:-on}" == "off" ]] && exit 0

# ── Read stdin (hook protocol — drain to prevent SIGPIPE) ────────────
INPUT=""
if command -v timeout &>/dev/null; then
    INPUT=$(timeout 3 cat 2>/dev/null) || true
else
    INPUT=$(cat 2>/dev/null) || true
fi

# ── Session identification ───────────────────────────────────────────
SESSION="${CLAUDE_SESSION_ID:-$$}"
STATE_FILE="/tmp/octopus-failures-${SESSION}.json"
THRESHOLD="${OCTO_STRATEGY_ROTATION_THRESHOLD:-2}"

# ── Detect tool name from hook input ─────────────────────────────────
TOOL_NAME=""
if [[ -n "$INPUT" ]]; then
    # Try jq first for reliable JSON parsing
    if command -v jq &>/dev/null; then
        TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // .tool // empty' 2>/dev/null) || true
    fi
    # Fallback: grep for tool name patterns
    if [[ -z "$TOOL_NAME" ]]; then
        if printf '%s' "$INPUT" | grep -qi '"tool_name"[[:space:]]*:[[:space:]]*"bash"' 2>/dev/null; then
            TOOL_NAME="Bash"
        elif printf '%s' "$INPUT" | grep -qi '"tool_name"[[:space:]]*:[[:space:]]*"edit"' 2>/dev/null; then
            TOOL_NAME="Edit"
        elif printf '%s' "$INPUT" | grep -qi '"tool_name"[[:space:]]*:[[:space:]]*"write"' 2>/dev/null; then
            TOOL_NAME="Write"
        elif printf '%s' "$INPUT" | grep -qi '"tool"[[:space:]]*:[[:space:]]*"bash"' 2>/dev/null; then
            TOOL_NAME="Bash"
        elif printf '%s' "$INPUT" | grep -qi '"tool"[[:space:]]*:[[:space:]]*"edit"' 2>/dev/null; then
            TOOL_NAME="Edit"
        elif printf '%s' "$INPUT" | grep -qi '"tool"[[:space:]]*:[[:space:]]*"write"' 2>/dev/null; then
            TOOL_NAME="Write"
        fi
    fi
fi

# Normalize tool name to lowercase key (avoid ${,,} for macOS bash 3 compat)
TOOL_KEY=""
TOOL_LOWER=$(printf '%s' "$TOOL_NAME" | tr '[:upper:]' '[:lower:]')
case "$TOOL_LOWER" in
    bash)  TOOL_KEY="bash" ;;
    edit)  TOOL_KEY="edit" ;;
    write) TOOL_KEY="write" ;;
    *)     exit 0 ;;  # Not a tracked tool
esac

# ── Detect failure ───────────────────────────────────────────────────
IS_FAILURE=false
ERROR_SNIPPET=""

if [[ -n "$INPUT" ]]; then
    if command -v jq &>/dev/null; then
        # For Bash tool: check exit_code field
        EXIT_CODE=$(printf '%s' "$INPUT" | jq -r '.exit_code // .exitCode // empty' 2>/dev/null) || true
        if [[ -n "$EXIT_CODE" && "$EXIT_CODE" != "0" && "$EXIT_CODE" != "null" ]]; then
            IS_FAILURE=true
            ERROR_SNIPPET="exit code ${EXIT_CODE}"
        fi

        # For all tools: check for error/failed in result
        if [[ "$IS_FAILURE" != "true" ]]; then
            RESULT_TEXT=$(printf '%s' "$INPUT" | jq -r '.result // .output // .error // empty' 2>/dev/null) || true
            if [[ -n "$RESULT_TEXT" ]]; then
                # Conservative: only match clear error indicators, not warnings
                if printf '%s' "$RESULT_TEXT" | grep -qiE '^error:|^FAIL:|failed to |command not found|permission denied|no such file|syntax error' 2>/dev/null; then
                    IS_FAILURE=true
                    ERROR_SNIPPET=$(printf '%s' "$RESULT_TEXT" | head -c 200)
                fi
            fi
        fi

        # Check explicit error field
        if [[ "$IS_FAILURE" != "true" ]]; then
            HAS_ERROR=$(printf '%s' "$INPUT" | jq -r 'if .error then "yes" else "no" end' 2>/dev/null) || HAS_ERROR="no"
            if [[ "$HAS_ERROR" == "yes" ]]; then
                IS_FAILURE=true
                ERROR_SNIPPET=$(printf '%s' "$INPUT" | jq -r '.error' 2>/dev/null | head -c 200) || true
            fi
        fi
    else
        # No jq: basic pattern matching for failures
        if printf '%s' "$INPUT" | grep -qiE '"exit_code"[[:space:]]*:[[:space:]]*[1-9]' 2>/dev/null; then
            IS_FAILURE=true
            ERROR_SNIPPET="non-zero exit code"
        elif printf '%s' "$INPUT" | grep -qiE '"error"[[:space:]]*:' 2>/dev/null; then
            IS_FAILURE=true
            ERROR_SNIPPET="error in result"
        fi
    fi
fi

# ── Load current state ──────────────────────────────────────────────
# State format: {"bash":{"consecutive":N,"last_error":"..."},...}
STATE="{}"
if [[ -f "$STATE_FILE" ]] && command -v jq &>/dev/null; then
    STATE=$(cat "$STATE_FILE" 2>/dev/null) || STATE="{}"
    [[ -z "$STATE" ]] && STATE="{}"
fi

# Ensure STATE is valid JSON
if command -v jq &>/dev/null; then
    if ! printf '%s' "$STATE" | jq empty 2>/dev/null; then
        STATE="{}"
    fi
fi

# ── Update state ────────────────────────────────────────────────────
if command -v jq &>/dev/null; then
    if [[ "$IS_FAILURE" == "true" ]]; then
        # Increment consecutive count
        CURRENT=$(printf '%s' "$STATE" | jq -r ".${TOOL_KEY}.consecutive // 0" 2>/dev/null) || CURRENT=0
        NEW_COUNT=$((CURRENT + 1))
        SAFE_ERROR=$(printf '%s' "$ERROR_SNIPPET" | jq -Rs '.' 2>/dev/null) || SAFE_ERROR='""'
        STATE=$(printf '%s' "$STATE" | jq \
            --arg key "$TOOL_KEY" \
            --argjson count "$NEW_COUNT" \
            --argjson err "$SAFE_ERROR" \
            '.[$key] = {"consecutive": $count, "last_error": $err}' 2>/dev/null) || true
    else
        # Reset on success
        STATE=$(printf '%s' "$STATE" | jq \
            --arg key "$TOOL_KEY" \
            '.[$key] = {"consecutive": 0, "last_error": ""}' 2>/dev/null) || true
    fi

    # Write state back
    printf '%s' "$STATE" > "$STATE_FILE" 2>/dev/null || true
else
    # Without jq, use a simpler counter file per tool
    COUNTER_FILE="/tmp/octopus-failures-${SESSION}-${TOOL_KEY}.count"
    if [[ "$IS_FAILURE" == "true" ]]; then
        CURRENT=0
        [[ -f "$COUNTER_FILE" ]] && CURRENT=$(cat "$COUNTER_FILE" 2>/dev/null) || CURRENT=0
        [[ -z "$CURRENT" ]] && CURRENT=0
        NEW_COUNT=$((CURRENT + 1))
        printf '%s' "$NEW_COUNT" > "$COUNTER_FILE" 2>/dev/null || true
    else
        printf '0' > "$COUNTER_FILE" 2>/dev/null || true
        exit 0
    fi
fi

# ── Check threshold ─────────────────────────────────────────────────
CONSECUTIVE=0
if command -v jq &>/dev/null; then
    CONSECUTIVE=$(printf '%s' "$STATE" | jq -r ".${TOOL_KEY}.consecutive // 0" 2>/dev/null) || CONSECUTIVE=0
else
    COUNTER_FILE="/tmp/octopus-failures-${SESSION}-${TOOL_KEY}.count"
    [[ -f "$COUNTER_FILE" ]] && CONSECUTIVE=$(cat "$COUNTER_FILE" 2>/dev/null) || CONSECUTIVE=0
    [[ -z "$CONSECUTIVE" ]] && CONSECUTIVE=0
fi

# Only emit rotation guidance when threshold is met
if [[ "$CONSECUTIVE" -ge "$THRESHOLD" ]]; then
    # Map tool key to display name (avoid ${^} for macOS bash 3 compat)
    TOOL_DISPLAY="$TOOL_KEY"
    [[ "$TOOL_KEY" == "bash" ]] && TOOL_DISPLAY="Bash"
    [[ "$TOOL_KEY" == "edit" ]] && TOOL_DISPLAY="Edit"
    [[ "$TOOL_KEY" == "write" ]] && TOOL_DISPLAY="Write"

    ROTATION_MSG="STRATEGY ROTATION NEEDED: The ${TOOL_DISPLAY} tool has failed ${CONSECUTIVE} consecutive times. This approach is not working. You MUST try a fundamentally different approach:\\n- If you've been running the same command with variations, try a completely different command\\n- If you've been editing the same file, consider the problem is elsewhere\\n- If you've been retrying after the same error, step back and investigate the root cause\\n- State what you'll do differently BEFORE attempting it"

    cat <<EOF
{"additionalContext":"[🐙 Octopus] ${ROTATION_MSG}"}
EOF
fi
