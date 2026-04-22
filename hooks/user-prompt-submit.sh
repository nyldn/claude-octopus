#!/usr/bin/env bash
# Claude Octopus — UserPromptSubmit Hook (v9.11.0)
# Fires before user prompt is processed. Classifies task intent
# with confidence levels, injects routing context, and optionally
# auto-invokes matching /octo: workflows.
#
# v9.11.0: Auto-invoke mode — strong signals fire immediately,
# weak signals fire on repeat intent in the same session.
# Controlled by OCTOPUS_AUTO_INVOKE setting (default: true).
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
                printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","sessionTitle":"Octopus: /octo:%s"}}\n' "$_CMD"
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
# SETTINGS: Load auto-invoke preference
# Precedence (highest wins): Env var > preferences.json > settings.json > default
# ═══════════════════════════════════════════════════════════════════════════════
AUTO_INVOKE="true"  # Default: ON

# Tier 1: settings.json (plugin default)
SETTINGS_FILE="${CLAUDE_PLUGIN_ROOT:-.}/.claude-plugin/settings.json"
if [[ -f "$SETTINGS_FILE" ]] && command -v python3 &>/dev/null; then
    _setting=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        s = json.load(f)
    v = s.get('OCTOPUS_AUTO_INVOKE', None)
    if v is not None:
        print(str(v).lower())
except: pass" "$SETTINGS_FILE" 2>/dev/null) || true
    [[ "$_setting" == "false" || "$_setting" == "off" ]] && AUTO_INVOKE="false"
    [[ "$_setting" == "true" || "$_setting" == "on" ]] && AUTO_INVOKE="true"
fi

# Tier 2: preferences.json (user preference, survives sessions)
PREFS_FILE="${HOME}/.claude-octopus/preferences.json"
if [[ -f "$PREFS_FILE" ]] && command -v python3 &>/dev/null; then
    _pref=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        p = json.load(f)
    v = p.get('auto_invoke', None)
    if v is not None:
        print(str(v).lower())
except: pass" "$PREFS_FILE" 2>/dev/null) || true
    [[ "$_pref" == "false" || "$_pref" == "off" ]] && AUTO_INVOKE="false"
    [[ "$_pref" == "true" || "$_pref" == "on" ]] && AUTO_INVOKE="true"
fi

# Tier 3: Env var (highest priority — runtime override for CI/automation)
if [[ -n "${OCTOPUS_AUTO_INVOKE:-}" ]]; then
    case "${OCTOPUS_AUTO_INVOKE}" in
        false|off|0|no) AUTO_INVOKE="false" ;;
        true|on|1|yes)  AUTO_INVOKE="true" ;;
    esac
fi

# ═══════════════════════════════════════════════════════════════════════════════
# INTENT CLASSIFICATION — keyword matching (must be fast, <100ms)
# ═══════════════════════════════════════════════════════════════════════════════
INTENT=""
CONFIDENCE="LOW"
KEYWORD_HITS=0
SIGNAL_STRENGTH="weak"  # weak or strong — strong signals auto-invoke on first match

# Strong signals: compound phrases that almost always mean the specific intent
# Weak signals: single words that appear in many contexts
case "$PROMPT_LOWER" in
    # Security — strong signals
    *"security audit"*|*"owasp"*|*"vulnerability scan"*|*"threat model"*|*"cve"*)
        INTENT="security"; KEYWORD_HITS=2; SIGNAL_STRENGTH="strong" ;;
    *"security"*|*"vulnerability"*)
        INTENT="security"; KEYWORD_HITS=1 ;;

    # Code review — strong signals
    *"code review"*|*"pr review"*|*"review code"*|*"review this pr"*|*"review my changes"*)
        INTENT="review"; KEYWORD_HITS=2; SIGNAL_STRENGTH="strong" ;;
    *"review"*)
        INTENT="review"; KEYWORD_HITS=1 ;;

    # Debugging — strong signals (stack traces, explicit debug requests)
    *"stack trace"*|*"traceback"*|*"fix bug"*|*"fix this bug"*|*"debug"*)
        INTENT="debug"; KEYWORD_HITS=2; SIGNAL_STRENGTH="strong" ;;
    *"not working"*|*"broken"*|*"error"*)
        INTENT="debug"; KEYWORD_HITS=1 ;;

    # Testing — strong signals
    *"tdd"*|*"test coverage"*|*"write tests"*|*"unit test"*|*"test suite"*)
        INTENT="tdd"; KEYWORD_HITS=2; SIGNAL_STRENGTH="strong" ;;
    *"test"*)
        INTENT="tdd"; KEYWORD_HITS=1 ;;

    # Multi-file implementation — strong signal
    *"implement the following plan"*|*"implement this plan"*|*"execute the plan"*)
        INTENT="develop"; KEYWORD_HITS=3; SIGNAL_STRENGTH="strong" ;;

    # Research — moderate signals
    *"research"*|*"explore options"*|*"investigate"*|*"compare alternatives"*)
        INTENT="research"; KEYWORD_HITS=1; [[ "$PROMPT_LOWER" == *"research"* && "$PROMPT_LOWER" == *"options"* ]] && { KEYWORD_HITS=2; SIGNAL_STRENGTH="strong"; } ;;

    # Design
    *"design system"*|*"ui design"*|*"ux design"*|*"mockup"*)
        INTENT="design-ui-ux"; KEYWORD_HITS=2; SIGNAL_STRENGTH="strong" ;;
    *"design"*|*"ui"*|*"ux"*)
        INTENT="design-ui-ux"; KEYWORD_HITS=1 ;;

    # Refactoring
    *"refactor"*|*"simplify"*|*"clean up"*)
        INTENT="develop"; KEYWORD_HITS=1 ;;

    # Performance
    *"performance"*|*"optimize"*|*"slow"*|*"latency"*)
        INTENT="develop"; KEYWORD_HITS=1 ;;
esac

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
    security)       SKILL_NAME="octo:security" ;;
    review)         SKILL_NAME="octo:review" ;;
    debug)          SKILL_NAME="octo:debug" ;;
    tdd)            SKILL_NAME="octo:tdd" ;;
    develop)        SKILL_NAME="octo:develop" ;;
    research)       SKILL_NAME="octo:research" ;;
    design-ui-ux)   SKILL_NAME="octo:design-ui-ux" ;;
esac

# Determine if we should auto-invoke
# Never auto-invoke when user already typed an explicit /octo: command
SHOULD_AUTO_INVOKE=false
if [[ "$_OCTO_EXPLICIT" == "true" ]]; then
    SHOULD_AUTO_INVOKE=false
elif [[ "$AUTO_INVOKE" == "true" && -n "$SKILL_NAME" ]]; then
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
        # Escape the prompt for safe JSON embedding
        ESCAPED_ARGS=$(printf '%s' "$PROMPT" | python3 -c "
import sys, json
print(json.dumps(sys.stdin.read())[1:-1])" 2>/dev/null) || true

        CONTEXT_MSG="[🐙 Octopus] Auto-invoke: ${INTENT} (${CONFIDENCE}, ${SIGNAL_STRENGTH}). MANDATORY: Invoke Skill(skill: \\\"${SKILL_NAME}\\\", args: \\\"${ESCAPED_ARGS}\\\") before responding. The skill handles the full response."
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
            if [[ "$AUTO_INVOKE" == "true" && -n "$SKILL_NAME" ]]; then
                CONTEXT_MSG="${CONTEXT_MSG} Tip: /${SKILL_NAME} available for multi-AI analysis."
            fi
        fi
    fi

    echo "{\"hookSpecificOutput\":{\"hookEventName\":\"UserPromptSubmit\",\"additionalContext\":\"${CONTEXT_MSG}\"}}"
    exit 0
fi

exit 0
