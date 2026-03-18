#!/usr/bin/env bash
# Claude Octopus — UserPromptSubmit Hook (v8.41.0)
# Fires before user prompt is processed. Classifies task intent
# and injects routing context to improve skill matching and
# early workflow selection.
#
# Hook event: UserPromptSubmit
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# Read hook input from stdin
if [ -t 0 ]; then exit 0; fi
INPUT=$(timeout 3 cat 2>/dev/null || true); [[ -z "$INPUT" ]] && exit 0

# Extract the user's prompt text
if ! command -v python3 &>/dev/null; then
    exit 0
fi

PROMPT=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('prompt', d.get('message', '')))" 2>/dev/null) || true

[[ -z "$PROMPT" ]] && exit 0

# Quick intent classification via keyword matching
# This runs BEFORE prompt processing, so must be fast (<100ms)
INTENT=""
PROMPT_LOWER=$(printf '%s' "$PROMPT" | tr '[:upper:]' '[:lower:]')

case "$PROMPT_LOWER" in
    *"security"*|*"vulnerability"*|*"owasp"*|*"cve"*)
        INTENT="security-audit" ;;
    *"review"*|*"code review"*|*"pr review"*)
        INTENT="code-review" ;;
    *"debug"*|*"error"*|*"fix bug"*|*"traceback"*)
        INTENT="debugging" ;;
    *"test"*|*"tdd"*|*"unit test"*|*"coverage"*)
        INTENT="testing" ;;
    *"deploy"*|*"ci/cd"*|*"pipeline"*)
        INTENT="deployment" ;;
    *"research"*|*"explore"*|*"investigate"*)
        INTENT="research" ;;
    *"design"*|*"ui"*|*"ux"*|*"mockup"*)
        INTENT="design" ;;
    *"document"*|*"docs"*|*"readme"*)
        INTENT="documentation" ;;
    *"refactor"*|*"simplify"*|*"clean up"*)
        INTENT="refactoring" ;;
    *"performance"*|*"optimize"*|*"slow"*|*"latency"*)
        INTENT="performance" ;;
esac

# Inject routing context if intent detected
if [[ -n "$INTENT" ]]; then
    SESSION_FILE="${HOME}/.claude-octopus/session.json"
    # Update session with detected intent for downstream routing
    if [[ -f "$SESSION_FILE" ]] && command -v jq &>/dev/null; then
        TMP="${SESSION_FILE}.tmp"
        jq --arg intent "$INTENT" '.detected_intent = $intent' "$SESSION_FILE" > "$TMP" 2>/dev/null && \
            mv "$TMP" "$SESSION_FILE" 2>/dev/null || rm -f "$TMP"
    fi

    # Output context per hook spec: additionalContext must be under hookSpecificOutput
    echo "{\"hookSpecificOutput\":{\"hookEventName\":\"UserPromptSubmit\",\"additionalContext\":\"[Octopus] Detected task intent: ${INTENT}. Relevant personas and skills have been pre-matched for this intent type.\"}}"
    exit 0
fi

exit 0
