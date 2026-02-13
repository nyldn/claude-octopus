---
name: flow-develop
aliases:
  - develop
  - develop-workflow
  - tangle
  - tangle-workflow
description: Multi-AI implementation with quality gates (Double Diamond Develop phase)
  - Building solutions with Codex and Gemini review

  PRIORITY TRIGGERS (always invoke): "octo develop", "octo tangle", "octo build", "co-develop"

  DO NOT use for: research (use flow-discover), scoping (use flow-define),
  validation only (use flow-deliver).

agent: Explore
context: fork
task_management: true
execution_mode: enforced
trigger: |
  AUTOMATICALLY ACTIVATE when user requests multi-AI implementation:
  - "octo build X" or "octo implement Y"
  - "build with multi-AI" or "implement with all providers"
  - "tangle this implementation"

  DO NOT activate for:
  - Research tasks (use flow-discover)
  - Requirements (use flow-define)
  - Validation only (use flow-deliver)
  - Simple coding tasks Claude can do alone
---

# STOP. READ THIS FIRST.

**You are FORBIDDEN from implementing directly.** You MUST call orchestrate.sh via Bash.

Do NOT use Task agents, direct coding, or native personas for the multi-AI implementation.
The ONLY acceptable action is running the Bash command below.

---

## Step 1: Display banner

Output this text to the user before executing:

```
🐙 CLAUDE OCTOPUS ACTIVATED - Multi-provider implementation mode
🛠️ Develop Phase: <brief description of what's being built>

Providers:
🔴 Codex CLI - Code generation and patterns
🟡 Gemini CLI - Alternative approaches and review
🔵 Claude - Integration and quality gates
```

## Step 2: Execute orchestrate.sh (USE BASH TOOL NOW)

Run this command with the Bash tool. Replace the placeholder with the user's request.

```bash
OCTOPUS_AGENT_TEAMS=legacy "${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh" develop "<user's implementation request>"
```

**WAIT for the command to complete. Do NOT proceed until it finishes.**

If it fails, show the error to the user. Do NOT fall back to direct implementation.

## Step 3: Read the synthesis file

```bash
SYNTHESIS_FILE=$(find ~/.claude-octopus/results -name "tangle-validation-*.md" | sort -r | head -n1)
if [[ -z "$SYNTHESIS_FILE" ]]; then
  echo "ERROR: No synthesis file found"
  ls -lt ~/.claude-octopus/results/ 2>/dev/null | head -5
else
  echo "OK: $SYNTHESIS_FILE"
  cat "$SYNTHESIS_FILE"
fi
```

If no synthesis file exists, report the failure. Do NOT substitute with direct implementation.

## Step 4: Present results

Read the synthesis file content and present it to the user with this footer:

```
---
Multi-AI Implementation powered by Claude Octopus
Providers: 🔴 Codex | 🟡 Gemini | 🔵 Claude
Full synthesis: <path to synthesis file>
```

---

## What NOT to do

- Do NOT use `Task(octo:personas:*)` or any Task agent
- Do NOT implement the solution yourself
- Do NOT skip the orchestrate.sh call for any reason
- If orchestrate.sh fails, tell the user - do NOT work around it
