#!/usr/bin/env bash
# Claude Octopus — UserPromptSubmit Hook (v9.6.0)
# Fires before user prompt is processed. Classifies task intent
# with confidence levels and injects routing context with persona
# hints for high-confidence matches.
#
# v9.6.0: Confidence levels (HIGH/LOW), provider pre-warming,
# persona context injection on HIGH confidence.
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
CONFIDENCE="LOW"
PROMPT_LOWER=$(printf '%s' "$PROMPT" | tr '[:upper:]' '[:lower:]')
KEYWORD_HITS=0

# Count keyword matches per category for confidence scoring
case "$PROMPT_LOWER" in
    *"security audit"*|*"owasp"*|*"vulnerability scan"*|*"threat model"*|*"cve"*)
        INTENT="security-audit"; KEYWORD_HITS=2 ;;
    *"security"*|*"vulnerability"*)
        INTENT="security-audit"; KEYWORD_HITS=1 ;;
    *"code review"*|*"pr review"*|*"review code"*)
        INTENT="code-review"; KEYWORD_HITS=2 ;;
    *"review"*)
        INTENT="code-review"; KEYWORD_HITS=1 ;;
    *"debug"*|*"fix bug"*|*"traceback"*|*"stack trace"*)
        INTENT="debugging"; KEYWORD_HITS=2 ;;
    *"error"*)
        INTENT="debugging"; KEYWORD_HITS=1 ;;
    *"tdd"*|*"unit test"*|*"test coverage"*|*"write tests"*)
        INTENT="testing"; KEYWORD_HITS=2 ;;
    *"test"*)
        INTENT="testing"; KEYWORD_HITS=1 ;;
    *"deploy"*|*"ci/cd"*|*"pipeline"*)
        INTENT="deployment"; KEYWORD_HITS=1 ;;
    *"research"*|*"explore"*|*"investigate"*)
        INTENT="research"; KEYWORD_HITS=1 ;;
    *"design"*|*"ui"*|*"ux"*|*"mockup"*)
        INTENT="design"; KEYWORD_HITS=1 ;;
    *"document"*|*"docs"*|*"readme"*)
        INTENT="documentation"; KEYWORD_HITS=1 ;;
    *"refactor"*|*"simplify"*|*"clean up"*)
        INTENT="refactoring"; KEYWORD_HITS=1 ;;
    *"performance"*|*"optimize"*|*"slow"*|*"latency"*)
        INTENT="performance"; KEYWORD_HITS=1 ;;
esac

# v9.6.0: Determine confidence level
[[ $KEYWORD_HITS -ge 2 ]] && CONFIDENCE="HIGH"

# Inject routing context if intent detected
if [[ -n "$INTENT" ]]; then
    SESSION_FILE="${HOME}/.claude-octopus/session.json"

    # Update session with detected intent and primed providers
    if [[ -f "$SESSION_FILE" ]] && command -v jq &>/dev/null; then
        # v9.6.0: Provider pre-warming — detect available providers once
        PRIMED="[]"
        _codex=false; _gemini=false
        command -v codex &>/dev/null && [[ -n "${OPENAI_API_KEY:-}" || -f "${HOME}/.codex/auth.json" ]] && _codex=true
        command -v gemini &>/dev/null && [[ -n "${GEMINI_API_KEY:-}" || -f "${HOME}/.gemini/oauth_creds.json" ]] && _gemini=true
        PRIMED=$(python3 -c "
import json
p = ['claude']
if $_codex: p.insert(0, 'codex')
if $_gemini: p.insert(1 if $_codex else 0, 'gemini')
print(json.dumps(p))
" 2>/dev/null) || PRIMED='["claude"]'

        TMP="${SESSION_FILE}.tmp"
        jq --arg intent "$INTENT" --arg conf "$CONFIDENCE" --argjson providers "$PRIMED" \
            '.detected_intent = $intent | .intent_confidence = $conf | .primed_providers = $providers' \
            "$SESSION_FILE" > "$TMP" 2>/dev/null && \
            mv "$TMP" "$SESSION_FILE" 2>/dev/null || rm -f "$TMP"
    fi

    # v9.6.0: Build richer context for HIGH confidence matches
    CONTEXT_MSG="[🐙 Octopus] Detected intent: ${INTENT} (${CONFIDENCE} confidence)."
    if [[ "$CONFIDENCE" == "HIGH" ]]; then
        # Map intent to persona for richer context injection
        PERSONA_HINT=""
        case "$INTENT" in
            security-audit) PERSONA_HINT="Security auditor persona activated — OWASP Top 10, threat modeling, DevSecOps focus." ;;
            code-review)    PERSONA_HINT="Code reviewer persona activated — quality analysis, vulnerability detection, production reliability." ;;
            debugging)      PERSONA_HINT="Debugger persona activated — systematic root cause analysis, hypothesis-driven investigation." ;;
            testing)        PERSONA_HINT="TDD orchestrator persona activated — red-green-refactor discipline, coverage analysis." ;;
        esac
        [[ -n "$PERSONA_HINT" ]] && CONTEXT_MSG="${CONTEXT_MSG} ${PERSONA_HINT}"
    fi

    echo "{\"hookSpecificOutput\":{\"hookEventName\":\"UserPromptSubmit\",\"additionalContext\":\"${CONTEXT_MSG}\"}}"
    exit 0
fi

exit 0
