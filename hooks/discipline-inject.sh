#!/usr/bin/env bash
# discipline-inject.sh — Inject lightweight discipline directive on SessionStart
# Only fires when OCTOPUS_DISCIPLINE=on in config

set -euo pipefail

DISCIPLINE_CONF="${HOME}/.claude-octopus/config/discipline.conf"

# Check if discipline mode is enabled
if [[ ! -f "$DISCIPLINE_CONF" ]] || ! grep -q "OCTOPUS_DISCIPLINE=on" "$DISCIPLINE_CONF" 2>/dev/null; then
    # Not enabled — output empty JSON (no injection)
    echo '{}'
    exit 0
fi

# Discipline is ON — inject the lightweight directive
# This is ~30 lines, not 200+ like aggressive approaches
DIRECTIVE='🐙 DISCIPLINE MODE ACTIVE — Eight automatic gates are enforced this session:

DEVELOPMENT GATES:
1. BRAINSTORM GATE: Before writing code or making changes, confirm the approach has been discussed. If not, pause and plan first. Even simple changes. Use skill-thought-partner or skill-writing-plans.
2. VERIFICATION GATE: Before claiming work is done, fixed, or passing — run the actual verification command and show the output. No "should work" or "looks correct." Evidence only. Use skill-verification-gate.
3. REVIEW GATE: After completing any non-trivial code change, automatically run spec compliance check (does it match what was asked?) then code quality review. Flag issues before presenting results.
4. RESPONSE GATE: When receiving code review feedback, verify it against the actual code before implementing. Never blindly agree. Evaluate technically first. Use skill-review-response.
5. INVESTIGATION GATE: When encountering any bug, error, or test failure — investigate root cause before proposing fixes. No guessing. Use skill-debug.

KNOWLEDGE WORK GATES:
6. CONTEXT GATE: At the start of any task, detect whether this is dev work or knowledge work (research, writing, design, strategy). If knowledge work, switch to KM mode — prioritize structured research, decision frameworks, and design thinking over code-first approaches. Use skill-context-detection.
7. DECISION GATE: When comparing options, choosing between approaches, or evaluating trade-offs — present a structured comparison with criteria, scores, and a recommendation. Do not just list pros/cons in prose. Use skill-decision-support.
8. INTENT GATE: Before any creative or writing task (README, docs, copy, design), lock in the goal and audience first. What is this for? Who reads it? What should they do after? Validate output against these locked goals. Use skill-intent-contract.

These gates are NON-NEGOTIABLE while discipline mode is on. /octo:quick bypasses all gates for trivial tasks.'

# Escape for JSON
ESCAPED=$(printf '%s' "$DIRECTIVE" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ' | sed 's/  */ /g')

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$ESCAPED"
