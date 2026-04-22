#!/usr/bin/env bash
# stop-failure-log.sh — Log API errors for diagnostics
# Hook event: StopFailure (CC v2.1.78+)
# Note: StopFailure hook output and exit code are ignored by CC.
# This hook is purely for telemetry — appends to error-log.jsonl.

set -euo pipefail
# EXIT trap — emits diagnostic stderr ONLY when the hook exits non-zero, so
# the Claude Code harness error "No stderr output" can never recur. EXIT (not
# ERR) avoids over-firing on intermediate `grep -o`/`cmd | ...` inside $() that
# the hook's logic already handles. See issue #313.
_octo_hook_exit() { local c=$?; if [[ $c -ne 0 ]]; then echo "[hook:$(basename "$0")] exit $c" >&2 2>/dev/null || true; fi; return 0; }
trap _octo_hook_exit EXIT


# Read hook input from stdin
INPUT=$(cat 2>/dev/null) || INPUT=""
[[ -z "$INPUT" ]] && exit 0

# Determine log directory
LOG_DIR="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude-octopus}"
mkdir -p "$LOG_DIR" 2>/dev/null || exit 0

LOG_FILE="$LOG_DIR/error-log.jsonl"

# Extract error info — try jq, fall back to timestamp-only entry
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "unknown")

if command -v jq &>/dev/null; then
    error_type=$(echo "$INPUT" | jq -r '.error_type // "unknown"' 2>/dev/null) || error_type="unknown"
    error_message=$(echo "$INPUT" | jq -r '.error_message // empty' 2>/dev/null) || error_message=""
    echo "{\"ts\":\"$TIMESTAMP\",\"type\":\"$error_type\",\"msg\":$(echo "$error_message" | jq -Rs '.' 2>/dev/null || echo '""')}" >> "$LOG_FILE"
else
    # Minimal fallback — just log that an error occurred
    echo "{\"ts\":\"$TIMESTAMP\",\"type\":\"unknown\",\"msg\":\"StopFailure event (no jq for details)\"}" >> "$LOG_FILE"
fi

# Cap log at 500 lines to prevent unbounded growth
if [[ -f "$LOG_FILE" ]]; then
    line_count=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
    line_count="${line_count// /}"
    if [[ "$line_count" -gt 500 ]]; then
        tail -250 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
    fi
fi

exit 0
