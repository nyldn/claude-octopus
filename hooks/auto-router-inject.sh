#!/usr/bin/env bash
# auto-router-inject.sh - Compact SessionStart routing contract.
#
# Inject one small, explicit contract early in the session so hook-provided
# routing instructions are honored.

set -euo pipefail
_octo_hook_exit() { local c=$?; if [[ $c -ne 0 ]]; then echo "[hook:$(basename "$0")] exit $c" >&2 2>/dev/null || true; fi; return 0; }
trap _octo_hook_exit EXIT

escape_for_json() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

emit_session_context() {
    local context="$1"
    local escaped
    escaped=$(escape_for_json "$context")

    if [[ -n "${CURSOR_PLUGIN_ROOT:-}" ]]; then
        printf '{"additional_context":"%s"}\n' "$escaped"
    elif [[ -n "${CLAUDE_PLUGIN_ROOT:-}" && -z "${COPILOT_CLI:-}" ]]; then
        printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$escaped"
    else
        printf '{"additionalContext":"%s"}\n' "$escaped"
    fi
}

normalize_router_mode() {
    local raw
    raw=$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr '_' '-')
    case "$raw" in
        off|disabled|disable|none|0) echo "off" ;;
        suggest|suggestion|advisory|hint|hints|false|no) echo "suggest" ;;
        invoke|auto|auto-invoke|autoinvoke|mandatory|true|yes|on|1) echo "invoke" ;;
        *) return 1 ;;
    esac
}

json_pref_value() {
    local file="$1"
    local key="$2"
    [[ -f "$file" ]] || return 1
    command -v python3 &>/dev/null || return 1
    python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    value = data.get(sys.argv[2], None)
    if value is not None:
        print(str(value))
except Exception:
    pass
" "$file" "$key" 2>/dev/null
}

AUTO_ROUTER_MODE="invoke"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
SETTINGS_FILE="${PLUGIN_ROOT}/settings.json"
[[ -f "$SETTINGS_FILE" ]] || SETTINGS_FILE="${PLUGIN_ROOT}/.claude-plugin/settings.json"

if [[ -f "$SETTINGS_FILE" ]]; then
    _setting_router=$(json_pref_value "$SETTINGS_FILE" "OCTOPUS_AUTO_ROUTER_MODE" || true)
    _setting_legacy=$(json_pref_value "$SETTINGS_FILE" "OCTOPUS_AUTO_INVOKE" || true)
    if [[ -n "$_setting_router" ]] && _mode=$(normalize_router_mode "$_setting_router"); then
        AUTO_ROUTER_MODE="$_mode"
    elif [[ -n "$_setting_legacy" ]] && _mode=$(normalize_router_mode "$_setting_legacy"); then
        AUTO_ROUTER_MODE="$_mode"
    fi
fi

PREFS_FILE="${HOME}/.claude-octopus/preferences.json"
if [[ -f "$PREFS_FILE" ]]; then
    _pref_router=$(json_pref_value "$PREFS_FILE" "auto_router_mode" || true)
    _pref_legacy=$(json_pref_value "$PREFS_FILE" "auto_invoke" || true)
    if [[ -n "$_pref_router" ]] && _mode=$(normalize_router_mode "$_pref_router"); then
        AUTO_ROUTER_MODE="$_mode"
    elif [[ -n "$_pref_legacy" ]] && _mode=$(normalize_router_mode "$_pref_legacy"); then
        AUTO_ROUTER_MODE="$_mode"
    fi
fi

if [[ -n "${OCTOPUS_AUTO_ROUTER_MODE:-}" ]] && _mode=$(normalize_router_mode "$OCTOPUS_AUTO_ROUTER_MODE"); then
    AUTO_ROUTER_MODE="$_mode"
elif [[ -n "${OCTOPUS_AUTO_INVOKE:-}" ]] && _mode=$(normalize_router_mode "$OCTOPUS_AUTO_INVOKE"); then
    AUTO_ROUTER_MODE="$_mode"
fi

[[ "$AUTO_ROUTER_MODE" == "off" ]] && exit 0

read -r -d '' CONTEXT <<'ROUTER' || true
<OCTOPUS-AUTO-ROUTER>
Octopus prompt hooks may add UserPromptSubmit routing context. If that context says "MANDATORY: Invoke Skill(...)", invoke that Skill before answering. Do not answer directly first.

Strong plain-language routes include: review -> octo:review, debate/compare/should-we -> octo:debate, research/investigate/explore -> octo:discover, security/threat-model -> octo:security, debug/failing/stacktrace -> octo:debug, write-tests/TDD -> octo:tdd, implement/execute-plan -> octo:develop.

If the hook only says "Detected intent" or "Tip", treat it as a suggestion and continue normally unless the user asks to route.
</OCTOPUS-AUTO-ROUTER>
ROUTER

CONTEXT="${CONTEXT/OCTOPUS-AUTO-ROUTER>/OCTOPUS-AUTO-ROUTER mode=\"$AUTO_ROUTER_MODE\">}"
emit_session_context "$CONTEXT"
