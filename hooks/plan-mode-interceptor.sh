#!/bin/bash
# Plan Mode Interceptor — PreToolUse hook for EnterPlanMode
# Re-injects planning-relevant enforcement rules when entering plan mode.
# Prevents enforcement loss during plan mode transitions (same compaction
# survival issue but tool-triggered).
#
# Hook type: PreToolUse (matcher: EnterPlanMode)
# Returns: {"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"<PLAN-MODE-RULES>...</PLAN-MODE-RULES>"}

set -euo pipefail
# EXIT trap — emits diagnostic stderr ONLY when the hook exits non-zero, so
# the Claude Code harness error "No stderr output" can never recur. EXIT (not
# ERR) avoids over-firing on intermediate `grep -o`/`cmd | ...` inside $() that
# the hook's logic already handles. See issue #313.
_octo_hook_exit() { local c=$?; if [[ $c -ne 0 ]]; then echo "[hook:$(basename "$0")] exit $c" >&2 2>/dev/null || true; fi; return 0; }
trap _octo_hook_exit EXIT


# Read JSON payload from stdin (required by hook protocol)
if command -v timeout &>/dev/null; then
    INPUT=$(timeout 3 cat 2>/dev/null || true)
else
    INPUT=$(cat 2>/dev/null || true)
fi
[[ -z "$INPUT" ]] && INPUT='{}'

# Build planning-relevant enforcement context
read -r -d '' CONTEXT <<'RULES' || true
<PLAN-MODE-RULES source="🐙 Octopus">
## Planning Mode Enforcement Rules

These rules apply while in plan mode. They MUST be followed during planning
and carried into execution after the plan is approved.

### 1. No Stubs
NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE.
Every planned deliverable must include verification steps. Plans that omit
verification are incomplete.

### 2. Test-First
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST.
Plans must include test creation before implementation steps. If the plan
has "implement X" without a preceding "write failing test for X", revise it.

### 3. Intent Contract
If a session intent contract exists at .claude/session-intent.md, read it
before finalizing the plan. The plan must align with:
- Success criteria defined in the contract
- Boundaries and constraints
- Stakeholder requirements

Plans that contradict the intent contract are invalid.

### 4. Human-Only Skills
Do NOT plan to auto-invoke these skills — they require explicit user invocation:
- skill-factory, skill-deep-research, skill-adversarial-security
- flow-parallel, skill-ship

### 5. Octo Plan Artifact Conflict — MANDATORY WARNING
If the user invoked `/octo:plan` (or any octo planning workflow such as
`/octo:embrace`) while plan mode is active, plan mode's write restriction
BLOCKS octo from saving its planning artifacts:
  - .claude/session-intent.md  (intent contract)
  - .claude/session-plan.md    (weighted-phase plan)
  - provider block and phase visualization files

DO NOT silently fall through to generic native planning. You MUST:

1. Emit this exact warning as the very first output:

   ⚠️  OCTO PLAN DEGRADED — Plan Mode Write Conflict

   Native plan mode is active. Octo cannot save its planning artifacts
   (.claude/session-intent.md, .claude/session-plan.md) while plan mode
   restricts writes. You are getting display-only output — this is NOT
   a full octo multi-provider plan.

   To get the full octo plan:
     1. Exit or cancel native plan mode
     2. Re-run /octo:plan

   Continuing with plan visualization only (no artifacts saved)…

2. Skip Step 2 (Create Intent Contract) and Step 5 (Save the Plan) entirely.
   Do not attempt these writes — they will silently fail.
3. Complete Steps 1, 3, 4, and 6 so the user sees the visualization.
4. Repeat the re-run reminder at the end of Step 6.
</PLAN-MODE-RULES>
RULES

# Escape the context for JSON output
ESCAPED_CONTEXT=$(echo "$CONTEXT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null | sed 's/^"//;s/"$//')

# Return the hook response
cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"${ESCAPED_CONTEXT}"}}
EOF
