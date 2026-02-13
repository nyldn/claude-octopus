---
name: skill-debug
aliases:
  - debug
  - systematic-debugging
description: "Multi-AI debugging: Investigate, Analyze, Hypothesize, Implement"
trigger: |
  AUTOMATICALLY ACTIVATE when encountering bugs or failures:
  - "fix this bug" or "debug Y" or "troubleshoot X"
  - "why is X failing" or "why isn't X working"
  - "X does not work" or "X is broken"

  DO NOT activate for:
  - "Why do we use X?" (explanation, not debugging)
  - Known issues with clear solutions
  - Documentation questions
execution_mode: enforced
---

# STOP. READ THIS FIRST.

**You are FORBIDDEN from debugging directly.** You MUST call orchestrate.sh via Bash.

Do NOT use Task agents, native personas (debugger, etc.), or direct debugging.
The ONLY acceptable action is running the Bash command below.

---

## Step 1: Display banner

```
🐙 CLAUDE OCTOPUS ACTIVATED - Multi-provider debugging mode
🔧 Debug: <brief description of the bug>

Providers:
🔴 Codex CLI - Code analysis and root cause
🟡 Gemini CLI - Pattern matching and similar issues
🔵 Claude - Synthesis and fix recommendation
```

## Step 2: Execute orchestrate.sh (USE BASH TOOL NOW)

```bash
OCTOPUS_AGENT_TEAMS=legacy "${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh" probe "Debug: <user's bug description>"
```

**WAIT for completion. Do NOT proceed until it finishes.**

If it fails, show the error. Do NOT fall back to direct debugging.

## Step 3: Read synthesis

```bash
SYNTHESIS_FILE=$(find ~/.claude-octopus/results -name "probe-synthesis-*.md" 2>/dev/null | sort -r | head -n1)
if [[ -z "$SYNTHESIS_FILE" ]]; then
  echo "ERROR: No synthesis file found"
  ls -lt ~/.claude-octopus/results/ 2>/dev/null | head -5
else
  echo "OK: $SYNTHESIS_FILE"
  cat "$SYNTHESIS_FILE"
fi
```

## Step 4: Present results with attribution footer

```
---
Multi-AI Debugging powered by Claude Octopus
Providers: 🔴 Codex | 🟡 Gemini | 🔵 Claude
```

---

## What NOT to do

- Do NOT use `Task(octo:personas:debugger)` or any Task agent
- Do NOT debug the issue yourself
- If orchestrate.sh fails, tell the user - do NOT work around it
