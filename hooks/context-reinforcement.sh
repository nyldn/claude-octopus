#!/bin/bash
# Context Reinforcement Hook — SessionStart
# Re-injects Iron Laws after context compaction so enforcement rules survive
# conversation compression. Inspired by obra/superpowers v4.3.1 SessionStart pattern.
#
# Hook type: SessionStart
# Returns: {"decision":"continue","additionalContext":"<CONTEXT-REINFORCEMENT>...</CONTEXT-REINFORCEMENT>"}

set -euo pipefail

# Read JSON payload from stdin (required by hook protocol)
INPUT=$(cat)

# Build the enforcement context string with Iron Laws extracted from skills
read -r -d '' CONTEXT <<'RULES' || true
<CONTEXT-REINFORCEMENT>
## Iron Laws (re-injected after context compaction)

These rules MUST be followed at all times, even if earlier conversation context
has been compressed or lost. They are non-negotiable enforcement contracts.

### 1. No Stubs (skill-verify)
<HARD-GATE>
NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE
</HARD-GATE>
Claiming work is complete without verification is dishonesty, not efficiency.
If you haven't run the verification command in this message, you cannot claim it passes.

### 2. Test-First (skill-tdd)
<HARD-GATE>
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
</HARD-GATE>
Violating the letter of this rule is violating the spirit of this rule.
Write code before the test? Delete it. Start over.

### 3. Debug Protocol (skill-debug)
<HARD-GATE>
NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST
</HARD-GATE>
Random fixes waste time and create new bugs. Quick patches mask underlying issues.
If you haven't completed Phase 1 (root cause investigation), you cannot propose fixes.

### 4. Execution Contract (skill-deep-research)
You MUST call orchestrate.sh via the Bash tool for deep research. Do NOT research
the topic yourself. Do NOT use Task agents, web search, or your own knowledge as
a substitute. The ONLY valid execution path is: Bash → orchestrate.sh probe.

### 5. Factory Prohibitions (skill-factory)
<HARD-GATE>
PROHIBITED from:
- Running embrace directly (MUST use factory command which wraps it)
- Simulating or faking holdout testing
- Substituting direct Claude analysis for multi-provider scoring
- Skipping the factory pipeline
- Creating working/progress files in plugin directory
</HARD-GATE>

## Human-Only Skills
The following skills require explicit user invocation and MUST NOT auto-trigger:
- skill-factory (Dark Factory Mode)
- skill-deep-research (Deep Research)
- skill-adversarial-security (Security Audit)
- flow-parallel (Team of Teams)
- skill-ship (Ship/Deliver)
</CONTEXT-REINFORCEMENT>
RULES

# Escape the context for JSON output
ESCAPED_CONTEXT=$(echo "$CONTEXT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null | sed 's/^"//;s/"$//')

# Return the hook response
cat <<EOF
{"decision":"continue","additionalContext":"${ESCAPED_CONTEXT}"}
EOF
