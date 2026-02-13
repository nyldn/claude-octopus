---
name: flow-deliver
aliases:
  - deliver
  - deliver-workflow
  - ink
  - ink-workflow
description: Multi-AI validation and review (Double Diamond Deliver phase)
  - Quality assurance, testing, security review

  PRIORITY TRIGGERS (always invoke): "octo deliver", "octo ink", "octo validate", "co-deliver"

  DO NOT use for: research (use flow-discover), scoping (use flow-define),
  implementation (use flow-develop).

agent: Explore
context: fork
task_management: true
execution_mode: enforced
trigger: |
  AUTOMATICALLY ACTIVATE when user requests multi-AI validation:
  - "octo review X" or "octo validate Y"
  - "validate with multi-AI" or "review with all providers"
  - "deliver and validate"

  DO NOT activate for:
  - Research tasks (use flow-discover)
  - Requirements (use flow-define)
  - Implementation (use flow-develop)
  - Simple code reviews Claude can do alone
---

# STOP. READ THIS FIRST.

**You are FORBIDDEN from reviewing/validating directly.** You MUST call orchestrate.sh via Bash.

Do NOT use Task agents, direct review, or native personas.
The ONLY acceptable action is running the Bash command below.

---

## Step 1: Display banner

Output this text to the user before executing:

```
🐙 CLAUDE OCTOPUS ACTIVATED - Multi-provider validation mode
✅ Deliver Phase: <brief description of what's being validated>

Providers:
🔴 Codex CLI - Code quality analysis
🟡 Gemini CLI - Security and edge cases
🔵 Claude - Synthesis and recommendations
```

## Step 2: Execute orchestrate.sh (USE BASH TOOL NOW)

Run this command with the Bash tool. Replace the placeholder with the user's request.

```bash
OCTOPUS_AGENT_TEAMS=legacy "${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh" deliver "<user's validation request>"
```

**WAIT for the command to complete. Do NOT proceed until it finishes.**

If it fails, show the error to the user. Do NOT fall back to direct review.

## Step 3: Read the synthesis file

```bash
SYNTHESIS_FILE=$(find ~/.claude-octopus/results -name "delivery-*.md" | sort -r | head -n1)
if [[ -z "$SYNTHESIS_FILE" ]]; then
  echo "ERROR: No synthesis file found"
  ls -lt ~/.claude-octopus/results/ 2>/dev/null | head -5
else
  echo "OK: $SYNTHESIS_FILE"
  cat "$SYNTHESIS_FILE"
fi
```

If no synthesis file exists, report the failure. Do NOT substitute with your own review.

## Step 4: Present results

Read the synthesis file content and present it to the user with this footer:

```
---
Multi-AI Validation powered by Claude Octopus
Providers: 🔴 Codex | 🟡 Gemini | 🔵 Claude
Full synthesis: <path to synthesis file>
```

---

## What NOT to do

- Do NOT use `Task(octo:personas:*)` or any Task agent
- Do NOT review or validate the code yourself
- Do NOT skip the orchestrate.sh call for any reason
- If orchestrate.sh fails, tell the user - do NOT work around it
