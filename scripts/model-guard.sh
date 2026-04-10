#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# model-guard — PreToolUse hook that blocks hardcoded model names in CLI calls
# ═══════════════════════════════════════════════════════════════════════════════
#
# WHY: Claude frequently bypasses orchestrate.sh and dispatches providers
# manually with hardcoded model names (e.g., `codex exec -m o3` instead of
# reading providers.json). This hook intercepts Bash tool calls, detects
# raw CLI invocations with model flags, and blocks them with the correct
# model from the config.
#
# INSTALLATION:
# Add to ~/.claude/settings.json (or project settings):
#
#   {
#     "hooks": {
#       "PreToolUse": [
#         {
#           "matcher": "Bash",
#           "hooks": [
#             {
#               "type": "command",
#               "command": "/path/to/scripts/model-guard.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }
#
# Or run: /octo:setup to configure automatically.
#
# HOW IT WORKS:
# 1. Receives the Bash tool input as JSON on stdin
# 2. Extracts the command string
# 3. Checks if it matches known provider CLI patterns with model flags
# 4. If a model is hardcoded, resolves the correct one from providers.json
# 5. If they differ, blocks with an error message showing the correct model
#
# BYPASS: Set OCTOPUS_MODEL_GUARD=off to disable (e.g., for debugging)
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# Skip if guard is disabled
[[ "${OCTOPUS_MODEL_GUARD:-on}" == "off" ]] && exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${HOME}/.claude-octopus/config/providers.json"

# Bail early if no config file (plugin not configured)
[[ ! -f "$CONFIG_FILE" ]] && exit 0

# Read tool input from stdin
INPUT=$(cat)

# Extract the command field from the JSON tool input
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$COMMAND" ]] && exit 0

# ── Pattern matching ─────────────────────────────────────────────────────────

check_model() {
    local provider="$1"
    local detected_model="$2"
    local config_model

    config_model=$(jq -r ".providers.${provider}.default // empty" "$CONFIG_FILE" 2>/dev/null)
    [[ -z "$config_model" || "$config_model" == "null" ]] && return 0

    if [[ "$detected_model" != "$config_model" ]]; then
        # Output JSON to block the tool call
        jq -n \
            --arg provider "$provider" \
            --arg wrong "$detected_model" \
            --arg correct "$config_model" \
            '{
                "decision": "block",
                "reason": ("MODEL GUARD: Wrong model for " + $provider + ". Got \"" + $wrong + "\", expected \"" + $correct + "\" (from providers.json). Use: octo-dispatch " + $provider + " OR fix the --model flag.")
            }'
        exit 0
    fi
}

# Codex: codex exec ... --model <MODEL> ... or codex exec ... -m <MODEL> ...
if echo "$COMMAND" | grep -qE 'codex\s+exec\b'; then
    MODEL=$(echo "$COMMAND" | grep -oE '(-m|--model)\s+\S+' | head -1 | awk '{print $2}')
    if [[ -n "$MODEL" ]]; then
        check_model "codex" "$MODEL"
    fi
fi

# Gemini: gemini ... -m <MODEL> ...
if echo "$COMMAND" | grep -qE '\bgemini\b'; then
    MODEL=$(echo "$COMMAND" | grep -oE '-m\s+\S+' | head -1 | awk '{print $2}')
    if [[ -n "$MODEL" ]]; then
        check_model "gemini" "$MODEL"
    fi
fi

# Qwen: qwen ... -m <MODEL> ...
if echo "$COMMAND" | grep -qE '\bqwen\b'; then
    MODEL=$(echo "$COMMAND" | grep -oE '-m\s+\S+' | head -1 | awk '{print $2}')
    if [[ -n "$MODEL" ]]; then
        check_model "qwen" "$MODEL"
    fi
fi

# If we get here, either no model flag was detected or it matched — allow
exit 0
