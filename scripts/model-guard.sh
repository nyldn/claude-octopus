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
# 4. If a model is hardcoded, resolves the correct one via resolve_octopus_model
#    (same 7-tier precedence as orchestrate.sh)
# 5. If they differ, blocks with an error message showing the correct model
#
# BYPASS: Set OCTOPUS_MODEL_GUARD=off to disable (e.g., for debugging)
# ═══════════════════════════════════════════════════════════════════════════════

# NOTE: Do NOT use set -e here — grep returns 1 on no-match, which would
# abort the hook and block unrelated Bash commands.
set -uo pipefail

# Skip if guard is disabled
[[ "${OCTOPUS_MODEL_GUARD:-on}" == "off" ]] && exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${HOME}/.claude-octopus/config/providers.json"
RESOLVER="${SCRIPT_DIR}/lib/model-resolver.sh"

# Bail early if no config file (plugin not configured)
[[ ! -f "$CONFIG_FILE" ]] && exit 0

# Require jq for JSON parsing
command -v jq &>/dev/null || exit 0

# Read tool input from stdin
INPUT=$(cat)

# Extract the command field from the JSON tool input
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || true
[[ -z "$COMMAND" ]] && exit 0

# ── Model comparison ────────────────────────────────────────────────────────

check_model() {
    local provider="$1"
    local detected_model="$2"
    local expected_model=""

    # Use the full resolver if available (same 7-tier precedence as dispatch)
    if [[ -f "$RESOLVER" ]]; then
        # shellcheck source=lib/model-resolver.sh
        source "$RESOLVER" 2>/dev/null || true
        if declare -f resolve_octopus_model &>/dev/null; then
            expected_model=$(resolve_octopus_model "$provider" "$provider" "" "" 2>/dev/null) || true
        fi
    fi

    # Fallback to config default if resolver unavailable (mirrors model-resolver.sh tier 6)
    if [[ -z "$expected_model" || "$expected_model" == "null" ]]; then
        expected_model=$(jq -r ".providers.${provider}.default // .providers.${provider}.model // empty" "$CONFIG_FILE" 2>/dev/null) || true
    fi

    [[ -z "$expected_model" || "$expected_model" == "null" ]] && return 0

    if [[ "$detected_model" != "$expected_model" ]]; then
        # Output JSON to block the tool call
        jq -n \
            --arg provider "$provider" \
            --arg wrong "$detected_model" \
            --arg correct "$expected_model" \
            '{
                "decision": "block",
                "reason": ("MODEL GUARD: Wrong model for " + $provider + ". Got \"" + $wrong + "\", expected \"" + $correct + "\" (from providers.json). Use: octo-dispatch " + $provider + " OR fix the --model flag.")
            }'
        exit 0
    fi
}

# ── Extract model from flag patterns ────────────────────────────────────────
# Uses POSIX ERE only (no \s, \S, \b — those are PCRE and break on BSD grep).
# Uses grep -e to prevent patterns starting with - from being parsed as flags.
extract_model_flag() {
    local cmd="$1"
    local model=""

    # Try --model=VALUE or -m=VALUE first (equals form)
    model=$(echo "$cmd" | grep -oE -e '(--model|-m)=[^ ]+' 2>/dev/null | head -1 | sed 's/^.*=//' | tr -d "\"'") || true
    if [[ -z "$model" ]]; then
        # Try --model VALUE (long flag, space-separated)
        model=$(echo "$cmd" | grep -oE -e '--model[[:space:]]+[^ ]+' 2>/dev/null | head -1 | awk '{print $2}' | tr -d "\"'") || true
    fi
    if [[ -z "$model" ]]; then
        # Try -m VALUE (short flag, space-separated)
        # Use sed to avoid grep interpreting -m as its own --max-count flag
        model=$(echo "$cmd" | sed -n 's/.*[[:space:]]-m[[:space:]]\{1,\}\([^ ]*\).*/\1/p' | head -1 | tr -d "\"'") || true
    fi

    echo "$model"
}

# ── Provider detection ──────────────────────────────────────────────────────
# Uses POSIX character classes and grep -e to avoid flag/pattern collisions.
# All grep calls use || true to prevent exit-on-no-match under pipefail.

# Codex: codex exec ... --model <MODEL> ... or ... -m <MODEL> ...
if echo "$COMMAND" | grep -qE 'codex[[:space:]]+exec' 2>/dev/null; then
    MODEL=$(extract_model_flag "$COMMAND")
    if [[ -n "$MODEL" ]]; then
        check_model "codex" "$MODEL"
    fi
fi

# Gemini: gemini <flags> ... (require gemini as CLI invocation, not substring)
# Pattern requires gemini followed by a space and a flag, avoiding false positives
# on commands like: grep gemini logfile.txt, cat ~/.gemini/config
if echo "$COMMAND" | grep -qE '(^|[;&|])([[:space:]]*)gemini[[:space:]]' 2>/dev/null; then
    MODEL=$(extract_model_flag "$COMMAND")
    if [[ -n "$MODEL" ]]; then
        check_model "gemini" "$MODEL"
    fi
fi

# Qwen: qwen <flags> ... (same CLI invocation pattern as gemini)
if echo "$COMMAND" | grep -qE '(^|[;&|])([[:space:]]*)qwen[[:space:]]' 2>/dev/null; then
    MODEL=$(extract_model_flag "$COMMAND")
    if [[ -n "$MODEL" ]]; then
        check_model "qwen" "$MODEL"
    fi
fi

# Claude: claude <flags> --model <MODEL> (require CLI invocation + --model flag)
if echo "$COMMAND" | grep -qE '(^|[;&|])([[:space:]]*)claude[[:space:]].*--model' 2>/dev/null; then
    MODEL=$(extract_model_flag "$COMMAND")
    if [[ -n "$MODEL" ]]; then
        check_model "claude" "$MODEL"
    fi
fi

# Ollama: ollama run <MODEL> ...
if echo "$COMMAND" | grep -qE 'ollama[[:space:]]+run' 2>/dev/null; then
    MODEL=$(echo "$COMMAND" | sed -n 's/.*ollama[[:space:]]\{1,\}run[[:space:]]\{1,\}\([^ ]*\).*/\1/p' | head -1 | tr -d "\"'") || true
    if [[ -n "$MODEL" ]]; then
        check_model "ollama" "$MODEL"
    fi
fi

# If we get here, either no model flag was detected or it matched — allow
exit 0
