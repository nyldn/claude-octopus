---
name: flow-define
aliases:
  - define
  - define-workflow
  - grasp
  - grasp-workflow
description: Multi-AI requirements clarification (Double Diamond Define phase)
  - Scope definition, requirements, consensus building

  PRIORITY TRIGGERS (always invoke): "octo define", "octo grasp", "co-define", "co-grasp"

  DO NOT use for: simple file searches, questions Claude can answer directly,
  research tasks (use flow-discover), implementation (use flow-develop).

agent: Explore
context: fork
task_management: true
execution_mode: enforced
trigger: |
  AUTOMATICALLY ACTIVATE when user requests requirements clarification:
  - "define requirements for X" or "scope Y"
  - "clarify what we need for Z"
  - "narrow down the approach"
  - "what exactly should we build"

  DO NOT activate for:
  - Research tasks (use flow-discover)
  - Implementation (use flow-develop)
  - Validation (use flow-deliver)
---

# STOP. READ THIS FIRST.

**You are FORBIDDEN from defining requirements directly.** You MUST call orchestrate.sh via Bash.

Do NOT use Task agents, direct analysis, or native personas.
The ONLY acceptable action is running the Bash command below.

---

## Step 1: Display banner

Output this text to the user before executing:

```
🐙 CLAUDE OCTOPUS ACTIVATED - Multi-provider definition mode
🎯 Define Phase: <brief description of what needs scoping>

Providers:
🔴 Codex CLI - Technical requirements analysis
🟡 Gemini CLI - Ecosystem and best practices
🔵 Claude - Strategic synthesis
```

## Step 2: Execute orchestrate.sh (USE BASH TOOL NOW)

Run this command with the Bash tool. Replace the placeholder with the user's request.

```bash
OCTOPUS_AGENT_TEAMS=legacy "${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh" define "<user's clarification request>"
```

**WAIT for the command to complete. Do NOT proceed until it finishes.**

If it fails, show the error to the user. Do NOT fall back to direct analysis.

## Step 3: Read the synthesis file

```bash
SYNTHESIS_FILE=$(find ~/.claude-octopus/results -name "grasp-consensus-*.md" | sort -r | head -n1)
if [[ -z "$SYNTHESIS_FILE" ]]; then
  echo "ERROR: No synthesis file found"
  ls -lt ~/.claude-octopus/results/ 2>/dev/null | head -5
else
  echo "OK: $SYNTHESIS_FILE"
  cat "$SYNTHESIS_FILE"
fi
```

If no synthesis file exists, report the failure. Do NOT substitute with your own analysis.

## Step 4: Present results

Read the synthesis file content and present it to the user with this footer:

```
---
Multi-AI Definition powered by Claude Octopus
Providers: 🔴 Codex | 🟡 Gemini | 🔵 Claude
Full synthesis: <path to synthesis file>
```

---

## What NOT to do

- Do NOT use `Task(octo:personas:*)` or any Task agent
- Do NOT analyze requirements yourself
- Do NOT skip the orchestrate.sh call for any reason
- If orchestrate.sh fails, tell the user - do NOT work around it
