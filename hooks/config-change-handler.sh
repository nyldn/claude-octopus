#!/bin/bash
# Claude Octopus ConfigChange Hook Handler
# Triggered when Claude Code configuration changes (v2.1.49+)
# Detects Octopus setting changes and writes reload signal for orchestrate.sh
# v8.29.0: Expanded from fast-mode-only to full Octopus settings hot-reload

CONFIG_CHANGE_DATA=""
if [[ ! -t 0 ]]; then
    CONFIG_CHANGE_DATA="$(cat)"
fi

SESSION_ID="${CLAUDE_SESSION_ID:-}"
WORKFLOW_PHASE="${OCTOPUS_WORKFLOW_PHASE:-unknown}"
SIGNAL_DIR="${HOME}/.claude-octopus"

# Log the change for debugging
if [[ "${VERBOSE:-false}" == "true" ]]; then
    echo "[ConfigChange] Session: $SESSION_ID, Phase: $WORKFLOW_PHASE" >&2
    if [[ -n "$CONFIG_CHANGE_DATA" ]]; then
        echo "[ConfigChange] Data: $CONFIG_CHANGE_DATA" >&2
    fi
fi

if [[ -n "$CONFIG_CHANGE_DATA" ]]; then
    # Detect fast mode toggle
    if echo "$CONFIG_CHANGE_DATA" | grep -q '"fast"' 2>/dev/null; then
        if [[ "${VERBOSE:-false}" == "true" ]]; then
            echo "[ConfigChange] Fast mode setting changed" >&2
        fi
    fi

    # Detect Octopus-specific setting changes
    NEEDS_RELOAD=false
    for setting in OCTOPUS_ROUTING_MODE OCTOPUS_AUTONOMY OCTOPUS_OPUS_MODE \
                   OCTOPUS_MAX_COST_USD OCTOPUS_MAX_PARALLEL_AGENTS \
                   OCTOPUS_QUALITY_GATE_THRESHOLD OCTOPUS_WORKTREE_ISOLATION \
                   OCTOPUS_WEBHOOK_URL OCTOPUS_GEMINI_SANDBOX OCTOPUS_CODEX_SANDBOX \
                   OCTOPUS_MEMORY_INJECTION OCTOPUS_PERSONA_PACKS OCTOPUS_COST_WARNINGS \
                   OCTOPUS_TOOL_POLICIES; do
        if echo "$CONFIG_CHANGE_DATA" | grep -q "\"$setting\"" 2>/dev/null; then
            NEEDS_RELOAD=true
            if [[ "${VERBOSE:-false}" == "true" ]]; then
                echo "[ConfigChange] Octopus setting changed: $setting" >&2
            fi
        fi
    done

    # Write reload signal for orchestrate.sh to pick up on next invocation
    if [[ "$NEEDS_RELOAD" == "true" ]]; then
        mkdir -p "$SIGNAL_DIR"
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$SIGNAL_DIR/.config-reload-signal" 2>/dev/null || true
        if [[ "${VERBOSE:-false}" == "true" ]]; then
            echo "[ConfigChange] Wrote reload signal for orchestrate.sh" >&2
        fi
    fi
fi

echo '{"decision": "continue"}'
exit 0
