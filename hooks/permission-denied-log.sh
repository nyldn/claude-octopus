#!/usr/bin/env bash
# Claude Octopus — PermissionDenied Hook (v9.21.0)
# Logs denied command names (NOT arguments) for /octo:careful analytics.
# Only active when careful mode is enabled.
#
# Security: logs tool_name and denial reason only — never logs tool_input
# to prevent leaking secrets, API keys, or sensitive file paths.
#
# Hook event: PermissionDenied (CC v2.1.89+)
set -euo pipefail
# EXIT trap — emits diagnostic stderr ONLY when the hook exits non-zero, so
# the Claude Code harness error "No stderr output" can never recur. EXIT (not
# ERR) avoids over-firing on intermediate `grep -o`/`cmd | ...` inside $() that
# the hook's logic already handles. See issue #313.
_octo_hook_exit() { local c=$?; if [[ $c -ne 0 ]]; then echo "[hook:$(basename "$0")] exit $c" >&2 2>/dev/null || true; fi; return 0; }
trap _octo_hook_exit EXIT


# Only log when careful mode is active
CAREFUL_STATE="${HOME}/.claude-octopus/.careful-mode"
[[ -f "$CAREFUL_STATE" ]] || exit 0
[[ "${OCTO_CAREFUL_MODE:-on}" == "off" ]] && exit 0

# Read hook input from stdin
if [ -t 0 ]; then exit 0; fi
if command -v timeout &>/dev/null; then
    INPUT=$(timeout 3 cat 2>/dev/null || true)
else
    INPUT=$(cat 2>/dev/null || true)
fi
[[ -z "$INPUT" ]] && exit 0

# Extract tool name and reason — NEVER extract tool_input
TOOL_NAME=$(printf '%s' "$INPUT" | grep -o '"tool_name":"[^"]*"' | head -1 | cut -d'"' -f4)
REASON=$(printf '%s' "$INPUT" | grep -o '"reason":"[^"]*"' | head -1 | cut -d'"' -f4)
[[ -z "$TOOL_NAME" ]] && exit 0

# Log to denied-commands.log (append-only, one line per denial)
LOG_FILE="${HOME}/.claude-octopus/denied-commands.log"
mkdir -p "$(dirname "$LOG_FILE")"
printf '%s\ttool=%s\treason=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$TOOL_NAME" "${REASON:-unknown}" >> "$LOG_FILE"

# Rotate log if over 100KB
LOG_SIZE=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
if [[ "$LOG_SIZE" -gt 102400 ]]; then
    tail -100 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
fi

exit 0
