#!/usr/bin/env bash
# Claude Octopus — UserPromptSubmit Hook (v9.11.0)
# Fires before user prompt is processed. Classifies task intent
# with confidence levels, injects routing context, and optionally
# auto-invokes matching /octo: workflows.
#
# v9.11.0: Auto-invoke mode — strong signals fire immediately,
# weak signals fire on repeat intent in the same session.
# Controlled by OCTOPUS_AUTO_ROUTER_MODE=off|suggest|invoke.
# Legacy OCTOPUS_AUTO_INVOKE remains supported.
#
# v9.6.0: Confidence levels (HIGH/LOW), provider pre-warming,
# persona context injection on HIGH confidence.
#
# Hook event: UserPromptSubmit
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail
# EXIT trap — emits diagnostic stderr ONLY when the hook exits non-zero, so
# the Claude Code harness error "No stderr output" can never recur. EXIT (not
# ERR) avoids over-firing on intermediate `grep -o`/`cmd | ...` inside $() that
# the hook's logic already handles. See issue #313.
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

emit_user_prompt_context() {
    local context="$1"
    local escaped
    escaped=$(escape_for_json "$context")

    if [[ -n "${CURSOR_PLUGIN_ROOT:-}" ]]; then
        printf '{"additional_context":"%s"}\n' "$escaped"
    elif [[ -n "${CLAUDE_PLUGIN_ROOT:-}" && -z "${COPILOT_CLI:-}" ]]; then
        printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$escaped"
    else
        printf '{"additionalContext":"%s"}\n' "$escaped"
    fi
}

emit_user_prompt_title() {
    local title="$1"
    local escaped
    escaped=$(escape_for_json "$title")
    printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","sessionTitle":"%s"}}\n' "$escaped"
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

# Read hook input from stdin
if [ -t 0 ]; then exit 0; fi
if command -v timeout &>/dev/null; then
    INPUT=$(timeout 3 cat 2>/dev/null || true)
else
    INPUT=$(cat 2>/dev/null || true)
fi
[[ -z "$INPUT" ]] && exit 0

# Extract the user's prompt text (python3 preferred, jq fallback)
if command -v python3 &>/dev/null; then
    PROMPT=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('prompt', d.get('message', '')))" 2>/dev/null) || true
elif command -v jq &>/dev/null; then
    PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // .message // ""' 2>/dev/null) || true
else
    exit 0
fi

[[ -z "$PROMPT" ]] && exit 0

# ═══════════════════════════════════════════════════════════════════════════════
# GUARD: Skip if user already invoked an /octo: command (prevent double-exec)
# ═══════════════════════════════════════════════════════════════════════════════
PROMPT_LOWER=$(printf '%s' "$PROMPT" | tr '[:upper:]' '[:lower:]')

# ── Session title auto-naming (CC v2.1.94+, SUPPORTS_SESSION_TITLE_HOOK) ──
# When user invokes /octo: command, auto-title the session for easier /resume.
# Only sets title if no prior /rename (session_title absent or auto-generated).
# Respects OCTOPUS_AUTO_TITLE=false to disable.
# ── Session title auto-naming (CC v2.1.94+, SUPPORTS_SESSION_TITLE_HOOK) ──
# When user invokes /octo: command, auto-title the session for easier /resume.
# Only sets title on first /octo: invocation per session. Respects /rename.
_OCTO_EXPLICIT=false
if [[ "$PROMPT_LOWER" == /octo:* ]] || [[ "$PROMPT_LOWER" == "octo:"* ]]; then
    _OCTO_EXPLICIT=true
    if [[ "${OCTOPUS_AUTO_TITLE:-true}" != "false" ]]; then
        _CMD=$(printf '%s' "$PROMPT_LOWER" | sed 's|^/\{0,1\}octo:\([a-z_-]*\).*|\1|')
        if [[ -n "$_CMD" ]]; then
            _SESSION_ID=$(printf '%s' "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | cut -d'"' -f4)
            _TITLE_FILE="${HOME}/.claude-octopus/.session-titled-${_SESSION_ID:-unknown}"
            if [[ ! -f "$_TITLE_FILE" ]]; then
                touch "$_TITLE_FILE" 2>/dev/null || true
                emit_user_prompt_title "Octopus: /octo:${_CMD}"
                exit 0
            fi
        fi
    fi
    # Don't exit — fall through for intent tracking, but suppress auto-invoke below
fi
# Skip command-message XML tags (skill invocations already in progress)
if [[ "$PROMPT" == *"<command-message>octo:"* ]] || [[ "$PROMPT" == *"<command-name>/octo:"* ]]; then
    exit 0
fi

# ═══════════════════════════════════════════════════════════════════════════════
# SETTINGS: Load auto-router preference
# Precedence (highest wins): Env var > preferences.json > settings.json > default
# ═══════════════════════════════════════════════════════════════════════════════
AUTO_ROUTER_MODE="invoke"  # Default preserves legacy strong-signal auto-invoke.

# Tier 1: settings.json (plugin default). Prefer the current plugin-root
# settings.json path, but keep the old .claude-plugin/settings.json fallback.
SETTINGS_FILE="${CLAUDE_PLUGIN_ROOT:-.}/settings.json"
[[ -f "$SETTINGS_FILE" ]] || SETTINGS_FILE="${CLAUDE_PLUGIN_ROOT:-.}/.claude-plugin/settings.json"
if [[ -f "$SETTINGS_FILE" ]]; then
    _setting_router=$(json_pref_value "$SETTINGS_FILE" "OCTOPUS_AUTO_ROUTER_MODE" || true)
    _setting_legacy=$(json_pref_value "$SETTINGS_FILE" "OCTOPUS_AUTO_INVOKE" || true)
    if [[ -n "$_setting_router" ]] && _mode=$(normalize_router_mode "$_setting_router"); then
        AUTO_ROUTER_MODE="$_mode"
    elif [[ -n "$_setting_legacy" ]] && _mode=$(normalize_router_mode "$_setting_legacy"); then
        AUTO_ROUTER_MODE="$_mode"
    fi
fi

# Tier 2: preferences.json (user preference, survives sessions)
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

# Tier 3: Env var (highest priority — runtime override for CI/automation)
if [[ -n "${OCTOPUS_AUTO_ROUTER_MODE:-}" ]] && _mode=$(normalize_router_mode "$OCTOPUS_AUTO_ROUTER_MODE"); then
    AUTO_ROUTER_MODE="$_mode"
elif [[ -n "${OCTOPUS_AUTO_INVOKE:-}" ]] && _mode=$(normalize_router_mode "$OCTOPUS_AUTO_INVOKE"); then
    AUTO_ROUTER_MODE="$_mode"
fi

[[ "$AUTO_ROUTER_MODE" == "off" ]] && exit 0

# ═══════════════════════════════════════════════════════════════════════════════
# INTENT CLASSIFICATION — keyword matching (must be fast, <100ms)
# ═══════════════════════════════════════════════════════════════════════════════
INTENT=""
CONFIDENCE="LOW"
KEYWORD_HITS=0
SIGNAL_STRENGTH="weak"  # weak or strong — strong signals auto-invoke on first match

# Ordered to match /octo:auto: specific/specialized workflows first, broad
# build and quick paths last. Compound phrases are strong; broad single words
# stay weak so the hook nudges instead of over-taking the prompt.
set_intent() {
    INTENT="$1"
    KEYWORD_HITS="$2"
    SIGNAL_STRENGTH="$3"
}

if [[ -z "$INTENT" ]]; then
    case "$PROMPT_LOWER" in
        *"end-to-end"*|*"complete lifecycle"*|*"full workflow"*|*"entire project"*|*"whole system"*)
            set_intent "embrace" 2 "strong" ;;
        *"multi-llm"*|*"multi-provider"*|*"all providers"*|*"force multi"*|*"cross-model"*)
            set_intent "multi" 2 "strong" ;;
        *"team of teams"*|*"decompose"*|*"work packages"*|*"split into"*|*"parallel"*)
            set_intent "parallel" 2 "strong" ;;
        *"nlspec"*|*"requirements doc"*|*"define scope"*|*"write spec"*|*"specification"*)
            set_intent "spec" 2 "strong" ;;
        *"security audit"*|*"owasp"*|*"vulnerability scan"*|*"threat model"*|*"cve"*|*"attack surface"*|*"pentest"*)
            set_intent "security" 2 "strong" ;;
        *"security"*|*"vulnerability"*)
            set_intent "security" 1 "weak" ;;
        *"test-driven"*|*"test first"*|*"tdd"*|*"test coverage"*|*"write tests"*|*"unit test"*|*"test suite"*)
            set_intent "tdd" 2 "strong" ;;
        *"debug"*|*"fix bug"*|*"fix this bug"*|*"troubleshoot"*|*"stack trace"*|*"traceback"*|*"error trace"*|*"stacktrace"*|*"failing"*|*"crash"*)
            set_intent "debug" 2 "strong" ;;
        *"not working"*|*"broken"*|*"error"*)
            set_intent "debug" 1 "weak" ;;
        *"ui design"*|*"ux design"*|*"wireframe"*|*"mockup"*|*"design system"*|*"layout"*|*"prototype"*)
            set_intent "design-ui-ux" 2 "strong" ;;
        *"prd"*|*"product requirements"*|*"product spec"*|*"feature requirements"*)
            set_intent "prd" 2 "strong" ;;
        *"brainstorm"*|*"ideate"*|*"ideas"*|*"thought experiment"*|*"what if"*)
            set_intent "brainstorm" 2 "strong" ;;
        *"presentation"*|*"slides"*|*"slide deck"*|*"pitch deck"*|*"deck"*)
            set_intent "deck" 2 "strong" ;;
        *"documentation"*|*"api docs"*|*"write docs"*|*"readme"*|*"docstring"*)
            set_intent "docs" 2 "strong" ;;
    esac
fi

if [[ -z "$INTENT" ]]; then
    case "$PROMPT_LOWER" in
        *"research options"*|*"research "*|*"investigate "*|*"explore "*|*"study "*|*"understand patterns"*|*"analyze ecosystem"*)
            set_intent "discover" 2 "strong" ;;
        *"code review"*|*"pr review"*|*"review code"*|*"review this pr"*|*"review my changes"*|*"check quality"*|*"audit code"*)
            set_intent "review" 2 "strong" ;;
        *"validate"*|*"inspect"*|*"verify"*|*"review"*)
            set_intent "review" 1 "weak" ;;
        *"should we "*|*" vs "*|*" versus "*|*"decide between"*|*"which is better"*|*"trade-off"*|*"tradeoff"*|*"compare alternatives"*|*"compare "*)
            set_intent "debate" 2 "strong" ;;
    esac
fi

if [[ -z "$INTENT" ]]; then
    case "$PROMPT_LOWER" in
        *"implement the following plan"*|*"implement this plan"*|*"execute the plan"*)
            set_intent "develop" 3 "strong" ;;
        *"build "*|*"create "*|*"implement "*|*"develop "*|*"refactor"*|*"simplify"*|*"clean up"*|*"performance"*|*"optimize"*|*"slow"*|*"latency"*)
            set_intent "develop" 1 "weak" ;;
        *"make "*)
            set_intent "plan" 1 "weak" ;;
        *"quick"*|*"just do it"*|*"simple"*|*"fast"*|*"straightforward"*)
            set_intent "quick" 1 "weak" ;;
    esac
fi

# Determine confidence level
[[ $KEYWORD_HITS -ge 2 ]] && CONFIDENCE="HIGH"

# ═══════════════════════════════════════════════════════════════════════════════
# SESSION TRACKING — detect repeat intent for weak-signal auto-invoke
# ═══════════════════════════════════════════════════════════════════════════════
SESSION_FILE="${HOME}/.claude-octopus/session.json"
REPEAT_INTENT=false

if [[ -n "$INTENT" && -f "$SESSION_FILE" ]] && command -v jq &>/dev/null; then
    # Check if same intent was detected previously in this session
    PREV_INTENT=$(jq -r '.detected_intent // ""' "$SESSION_FILE" 2>/dev/null) || true
    [[ "$PREV_INTENT" == "$INTENT" ]] && REPEAT_INTENT=true

    # Provider pre-warming
    PRIMED="[]"
    _codex=false; _gemini=false; _opencode=false
    command -v codex &>/dev/null && [[ -n "${OPENAI_API_KEY:-}" || -f "${HOME}/.codex/auth.json" ]] && _codex=true
    command -v gemini &>/dev/null && [[ -n "${GEMINI_API_KEY:-}" || -f "${HOME}/.gemini/oauth_creds.json" ]] && _gemini=true
    command -v opencode &>/dev/null && _opencode=true
    PRIMED=$(python3 -c "
import json
p = ['claude']
if $_codex: p.insert(0, 'codex')
if $_gemini: p.insert(1 if $_codex else 0, 'gemini')
if $_opencode: p.append('opencode')
print(json.dumps(p))
" 2>/dev/null) || PRIMED='["claude"]'

    # Update session state
    TMP="${SESSION_FILE}.tmp"
    jq --arg intent "$INTENT" --arg conf "$CONFIDENCE" --argjson providers "$PRIMED" \
        '.detected_intent = $intent | .intent_confidence = $conf | .primed_providers = $providers' \
        "$SESSION_FILE" > "$TMP" 2>/dev/null && \
        mv "$TMP" "$SESSION_FILE" 2>/dev/null || rm -f "$TMP"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# AUTO-INVOKE DECISION
# ═══════════════════════════════════════════════════════════════════════════════
# Map intent to /octo: skill name
SKILL_NAME=""
case "$INTENT" in
    embrace)        SKILL_NAME="octo:embrace" ;;
    multi)          SKILL_NAME="octo:multi" ;;
    parallel)       SKILL_NAME="octo:parallel" ;;
    spec)           SKILL_NAME="octo:spec" ;;
    security)       SKILL_NAME="octo:security" ;;
    review)         SKILL_NAME="octo:review" ;;
    debate)         SKILL_NAME="octo:debate" ;;
    debug)          SKILL_NAME="octo:debug" ;;
    tdd)            SKILL_NAME="octo:tdd" ;;
    develop)        SKILL_NAME="octo:develop" ;;
    discover)       SKILL_NAME="octo:discover" ;;
    design-ui-ux)   SKILL_NAME="octo:design-ui-ux" ;;
    prd)            SKILL_NAME="octo:prd" ;;
    brainstorm)     SKILL_NAME="octo:brainstorm" ;;
    deck)           SKILL_NAME="octo:deck" ;;
    docs)           SKILL_NAME="octo:docs" ;;
    plan)           SKILL_NAME="octo:plan" ;;
    quick)          SKILL_NAME="octo:quick" ;;
esac

# Determine if we should auto-invoke
# Never auto-invoke when user already typed an explicit /octo: command
SHOULD_AUTO_INVOKE=false
if [[ "$_OCTO_EXPLICIT" == "true" ]]; then
    SHOULD_AUTO_INVOKE=false
elif [[ "$AUTO_ROUTER_MODE" == "invoke" && -n "$SKILL_NAME" ]]; then
    if [[ "$SIGNAL_STRENGTH" == "strong" && "$CONFIDENCE" == "HIGH" ]]; then
        # Strong signal + HIGH confidence = auto-invoke on first match
        SHOULD_AUTO_INVOKE=true
    elif [[ "$REPEAT_INTENT" == "true" && "$CONFIDENCE" == "HIGH" ]]; then
        # Repeat intent + HIGH confidence = auto-invoke (user is stuck)
        SHOULD_AUTO_INVOKE=true
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# OUTPUT — inject context or auto-invoke instruction
# ═══════════════════════════════════════════════════════════════════════════════
if [[ -n "$INTENT" ]]; then
    if [[ "$SHOULD_AUTO_INVOKE" == "true" ]]; then
        # Auto-invoke: inject MANDATORY skill invocation instruction
        # Escape the prompt once for the Skill args string inside JSON output.
        ESCAPED_ARGS=$(escape_for_json "$PROMPT")

        CONTEXT_MSG="[🐙 Octopus] Auto-invoke: ${INTENT} (${CONFIDENCE}, ${SIGNAL_STRENGTH}). MANDATORY: Invoke Skill(skill: \"${SKILL_NAME}\", args: \"${ESCAPED_ARGS}\") before responding. The skill handles the full response."
    else
        # Standard behavior: inject persona context only
        CONTEXT_MSG="[🐙 Octopus] Detected intent: ${INTENT} (${CONFIDENCE} confidence)."
        if [[ "$CONFIDENCE" == "HIGH" ]]; then
            PERSONA_HINT=""
            case "$INTENT" in
                security)    PERSONA_HINT="Security auditor persona activated — OWASP Top 10, threat modeling, DevSecOps focus." ;;
                review)      PERSONA_HINT="Code reviewer persona activated — quality analysis, vulnerability detection, production reliability." ;;
                debug)       PERSONA_HINT="Debugger persona activated — systematic root cause analysis, hypothesis-driven investigation." ;;
                tdd)         PERSONA_HINT="TDD orchestrator persona activated — red-green-refactor discipline, coverage analysis." ;;
            esac
            [[ -n "$PERSONA_HINT" ]] && CONTEXT_MSG="${CONTEXT_MSG} ${PERSONA_HINT}"

            # Soft nudge for HIGH confidence that didn't auto-invoke
            if [[ "$AUTO_ROUTER_MODE" != "off" && -n "$SKILL_NAME" ]]; then
                CONTEXT_MSG="${CONTEXT_MSG} Tip: /${SKILL_NAME} available for multi-AI analysis."
            fi
        fi
    fi

    emit_user_prompt_context "$CONTEXT_MSG"
    exit 0
fi

exit 0
