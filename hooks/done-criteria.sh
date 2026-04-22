#!/usr/bin/env bash
# Claude Octopus — DONE Criteria Injection Hook
# UserPromptSubmit hook that detects compound tasks and injects
# completion criteria requirements to prevent partial execution.
#
# Compound task detection uses heuristics (numbered lists, bullet lists,
# multiple action verbs with conjunctions) — no LLM calls.
#
# Kill switch: OCTO_DONE_CRITERIA=off
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


# Read input with timeout guard
if [ -t 0 ]; then exit 0; fi
if command -v timeout &>/dev/null; then
    input=$(timeout 3 cat 2>/dev/null || true)
else
    input=$(cat 2>/dev/null || true)
fi
[[ -z "$input" ]] && exit 0

# Kill switch
[[ "${OCTO_DONE_CRITERIA:-on}" == "off" ]] && exit 0

# Extract user prompt text from JSON
prompt=""
if command -v python3 &>/dev/null; then
    prompt=$(printf '%s' "$input" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('prompt', d.get('message', d.get('content', ''))))" 2>/dev/null) || true
fi
if [[ -z "$prompt" ]]; then
    # Fallback: regex extraction without python3
    prompt=$(printf '%s' "$input" | grep -oE '"(prompt|message|content)"\s*:\s*"[^"]*"' | head -1 | sed 's/.*: *"//;s/"$//' 2>/dev/null || true)
fi
[[ -z "$prompt" ]] && exit 0

# Skip short prompts (< 30 chars unlikely to be compound)
[[ ${#prompt} -lt 30 ]] && exit 0

# ── Compound task detection (heuristic, not LLM) ────────────────────────────

compound=false

# Pattern 1: Numbered lists (1. foo 2. bar  OR  1) foo 2) bar)
if printf '%s' "$prompt" | grep -qE '(^|[[:space:]])[0-9]+[.)][[:space:]].*[0-9]+[.)][[:space:]]'; then
    compound=true
fi

# Pattern 2: Multiple action verbs connected by conjunctions
verb_pattern='(add|create|fix|update|implement|remove|delete|change|modify|refactor|write|build|test|deploy|configure|setup|install|move|rename|merge|split|extract|convert)'
if printf '%s' "$prompt" | grep -qiE "${verb_pattern}.*(and|then|also|plus|additionally|furthermore|next|after that|finally).*${verb_pattern}"; then
    compound=true
fi

# Pattern 3: Bullet lists (- or * at start of line, 2+ bullets)
bullet_count=$(printf '%s' "$prompt" | grep -cE '(^|\\n)[[:space:]]*[-*][[:space:]]' 2>/dev/null || echo "0")
if [[ "$bullet_count" -ge 2 ]]; then
    compound=true
fi

# ── Emit additional context if compound task detected ────────────────────────

if $compound; then
    CONTEXT="[🐙 Octopus] Compound task detected — multiple distinct actions. Before executing: (1) List specific, verifiable completion criteria for EACH part. (2) Execute each part methodically. (3) Before declaring done, verify EACH criterion is met. Do not skip any part. A task is not done until every criterion is verified."
    echo "{\"hookSpecificOutput\":{\"hookEventName\":\"UserPromptSubmit\",\"additionalContext\":\"${CONTEXT}\"}}"
fi
