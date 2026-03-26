#!/usr/bin/env bash
# telemetry-posthog.sh — PostHog usage analytics for Claude Octopus
# v9.13.0: Opt-in telemetry via POSTHOG_PROJECT_KEY env var
#
# Privacy: No prompts, file paths, or PII are ever sent.
# Anonymous: distinct_id is a random UUID persisted locally.
# Opt-in: Zero telemetry when POSTHOG_PROJECT_KEY is unset.
# Kill switch: POSTHOG_OPT_OUT=1 disables even when key is set.
# Performance: Events buffered locally, flushed async on session end.
#
# Hook events: SessionStart, Stop, StopFailure, SessionEnd
# Uses: PostHog /capture and /batch HTTP API

set -euo pipefail

# ── Opt-in gate ──────────────────────────────────────────────────────────────

POSTHOG_PROJECT_KEY="${POSTHOG_PROJECT_KEY:-}"
POSTHOG_HOST="${POSTHOG_HOST:-https://us.i.posthog.com}"

# Skip silently if not configured or opted out
[[ -z "$POSTHOG_PROJECT_KEY" ]] && exit 0
[[ "${POSTHOG_OPT_OUT:-0}" == "1" ]] && exit 0

# ── Anonymous identity ───────────────────────────────────────────────────────

ANON_DIR="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude-octopus}"
ANON_ID_FILE="${ANON_DIR}/.posthog-anon-id"
EVENT_BUFFER="${ANON_DIR}/.posthog-events.jsonl"

mkdir -p "$ANON_DIR" 2>/dev/null || true

# Generate or read persistent anonymous ID (random UUID, never hostname)
if [[ -f "$ANON_ID_FILE" ]]; then
    ANON_ID=$(cat "$ANON_ID_FILE" 2>/dev/null)
else
    # Generate UUID v4 without external deps
    ANON_ID=$(python3 -c 'import uuid; print(uuid.uuid4())' 2>/dev/null || \
              cat /proc/sys/kernel/random/uuid 2>/dev/null || \
              echo "anon-$(date +%s)-$$")
    echo "$ANON_ID" > "$ANON_ID_FILE"
fi

# ── Read hook input ──────────────────────────────────────────────────────────

INPUT=$(cat 2>/dev/null) || INPUT=""

# Determine hook event type from environment or input
HOOK_EVENT="${CLAUDE_HOOK_EVENT:-unknown}"
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "unknown")

# ── Event construction ───────────────────────────────────────────────────────

# Scrub function: remove anything that looks like a path, key, or prompt
_scrub() {
    echo "$1" | sed 's|/[^ ]*||g; s|sk-[a-zA-Z0-9]*|[REDACTED]|g; s|AIza[a-zA-Z0-9]*|[REDACTED]|g'
}

# Extract safe properties from hook input (no prompts or file paths)
PLUGIN_VERSION="${OCTOPUS_VERSION:-unknown}"
CC_VERSION="${CLAUDE_CODE_VERSION:-unknown}"
WORKFLOW_TYPE="${OCTOPUS_WORKFLOW_TYPE:-none}"
WORKFLOW_PHASE="${OCTOPUS_WORKFLOW_PHASE:-none}"

build_event() {
    local event_name="$1"
    shift
    # Build properties JSON — start with common fields
    local props="{\"plugin_version\":\"$PLUGIN_VERSION\",\"cc_version\":\"$CC_VERSION\",\"session_id\":\"$SESSION_ID\""

    # Add extra properties passed as key=value pairs
    while [[ $# -gt 0 ]]; do
        local key="${1%%=*}"
        local val="${1#*=}"
        props="${props},\"${key}\":\"$(_scrub "$val")\""
        shift
    done
    props="${props}}"

    # Construct PostHog event
    echo "{\"api_key\":\"$POSTHOG_PROJECT_KEY\",\"event\":\"$event_name\",\"distinct_id\":\"$ANON_ID\",\"timestamp\":\"$TIMESTAMP\",\"properties\":$props}"
}

# ── Buffer event locally ─────────────────────────────────────────────────────

buffer_event() {
    local event_json="$1"
    echo "$event_json" >> "$EVENT_BUFFER" 2>/dev/null || true

    # Cap buffer at 200 events to prevent unbounded growth
    if [[ -f "$EVENT_BUFFER" ]]; then
        local count
        count=$(wc -l < "$EVENT_BUFFER" 2>/dev/null || echo 0)
        count="${count// /}"
        if [[ "$count" -gt 200 ]]; then
            tail -100 "$EVENT_BUFFER" > "${EVENT_BUFFER}.tmp" && mv "${EVENT_BUFFER}.tmp" "$EVENT_BUFFER"
        fi
    fi
}

# ── Flush buffer to PostHog ──────────────────────────────────────────────────

flush_events() {
    [[ -f "$EVENT_BUFFER" ]] || return 0
    local count
    count=$(wc -l < "$EVENT_BUFFER" 2>/dev/null || echo 0)
    count="${count// /}"
    [[ "$count" -gt 0 ]] || return 0

    # Build batch payload
    local batch="["
    local first=true
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ "$first" == "true" ]]; then
            batch="${batch}${line}"
            first=false
        else
            batch="${batch},${line}"
        fi
    done < "$EVENT_BUFFER"
    batch="${batch}]"

    # POST to PostHog /batch endpoint (background, max 10s)
    curl -s -X POST "${POSTHOG_HOST}/batch/" \
        -H "Content-Type: application/json" \
        --connect-timeout 5 \
        --max-time 10 \
        -d "{\"api_key\":\"$POSTHOG_PROJECT_KEY\",\"batch\":$batch}" \
        >/dev/null 2>&1 &

    # Clear buffer after flush attempt
    : > "$EVENT_BUFFER" 2>/dev/null || true
}

# ── Route by hook event ──────────────────────────────────────────────────────

case "$HOOK_EVENT" in
    SessionStart)
        # Count available providers
        provider_count=0
        for cmd in codex gemini opencode copilot qwen; do
            command -v "$cmd" >/dev/null 2>&1 && provider_count=$((provider_count + 1))
        done
        for key_var in PERPLEXITY_API_KEY OPENROUTER_API_KEY; do
            [[ -n "${!key_var:-}" ]] 2>/dev/null && provider_count=$((provider_count + 1))
        done

        buffer_event "$(build_event "octopus.session.start" \
            "provider_count=$provider_count" \
            "platform=$(uname -s)" \
            "shell=$(basename "${SHELL:-unknown}")")"
        ;;

    Stop)
        buffer_event "$(build_event "octopus.workflow.complete" \
            "workflow_type=$WORKFLOW_TYPE" \
            "workflow_phase=$WORKFLOW_PHASE")"
        ;;

    StopFailure)
        # Extract error type if available
        error_type="unknown"
        if [[ -n "$INPUT" ]] && command -v jq &>/dev/null; then
            error_type=$(echo "$INPUT" | jq -r '.error_type // "unknown"' 2>/dev/null) || error_type="unknown"
        fi
        buffer_event "$(build_event "octopus.error" \
            "error_type=$error_type")"
        ;;

    SessionEnd)
        buffer_event "$(build_event "octopus.session.end")"
        # Flush all buffered events to PostHog
        flush_events
        ;;

    *)
        # Unknown event — buffer generic event
        buffer_event "$(build_event "octopus.event" \
            "hook_event=$HOOK_EVENT")"
        ;;
esac

exit 0
