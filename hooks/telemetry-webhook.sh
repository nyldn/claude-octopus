#!/bin/bash
# Claude Octopus Telemetry Webhook Hook
# v8.29.0: PostToolUse hook that POSTs phase completion data to configured webhook URL
# Only fires if OCTOPUS_WEBHOOK_URL is set — zero noise when unconfigured

WEBHOOK_URL="${OCTOPUS_WEBHOOK_URL:-}"

# Skip silently if no webhook configured
if [[ -z "$WEBHOOK_URL" ]]; then
    echo '{"decision": "continue"}'
    exit 0
fi

# Read tool output from stdin
HOOK_DATA=""
if [[ ! -t 0 ]]; then
    HOOK_DATA="$(cat)"
fi

SESSION_ID="${CLAUDE_SESSION_ID:-}"
WORKFLOW_PHASE="${OCTOPUS_WORKFLOW_PHASE:-unknown}"
WEBHOOK_TOKEN="${OCTOPUS_WEBHOOK_TOKEN:-}"

# Extract tool name from hook data for event context
TOOL_NAME=""
if [[ -n "$HOOK_DATA" ]]; then
    TOOL_NAME=$(echo "$HOOK_DATA" | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"//;s/"$//' 2>/dev/null || true)
fi

# Build telemetry payload
PAYLOAD=$(cat <<EOFPAYLOAD
{
  "event": "phase_complete",
  "session_id": "$SESSION_ID",
  "phase": "$WORKFLOW_PHASE",
  "tool": "${TOOL_NAME:-unknown}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "tool_output_length": ${#HOOK_DATA}
}
EOFPAYLOAD
)

# POST to webhook asynchronously — don't block workflow execution
CURL_ARGS=(-s -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -H "X-Octopus-Session: $SESSION_ID" \
    -H "X-Octopus-Phase: $WORKFLOW_PHASE" \
    --connect-timeout 5 \
    --max-time 10 \
    -d "$PAYLOAD")

if [[ -n "$WEBHOOK_TOKEN" ]]; then
    CURL_ARGS+=(-H "Authorization: Bearer $WEBHOOK_TOKEN")
fi

curl "${CURL_ARGS[@]}" >/dev/null 2>&1 &

echo '{"decision": "continue"}'
exit 0
