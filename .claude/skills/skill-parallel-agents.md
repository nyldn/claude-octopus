---
name: skill-parallel-agents
description: Multi-tentacled orchestration - route any task through orchestrate.sh
trigger: |
  PRIORITY TRIGGERS (always invoke immediately):
  - "/octo:multi" (explicit command)
  - "run this with all providers", "run with all providers"
  - "use all three AI models", "use all providers for"
  - "get multiple perspectives on", "force multi-provider analysis"

  AUTOMATICALLY ACTIVATE when user prefixes with "octo":
  - "octo research X", "octo build Y", "octo review Z"
  - "octo debug X", "octo security Y", "octo analyze Z"

  NEVER use for:
  - Built-in Claude Code commands (/plugin, /init, /help, etc.)
  - Simple file operations, git commands, or basic terminal tasks
execution_mode: enforced
---

# STOP. READ THIS FIRST.

**You are FORBIDDEN from handling multi-provider tasks directly.** You MUST call orchestrate.sh via Bash.

Do NOT use Task agents, native personas, or any direct approach.
Route through orchestrate.sh using the `auto` command which detects intent.

---

## Step 1: Display banner

```
🐙 CLAUDE OCTOPUS ACTIVATED - Multi-provider mode
🐙 Task: <brief description>

Providers:
🔴 Codex CLI - Technical analysis
🟡 Gemini CLI - Alternative perspectives
🔵 Claude - Synthesis
```

## Step 2: Execute orchestrate.sh (USE BASH TOOL NOW)

Use `auto` to let orchestrate.sh detect intent and route appropriately:

```bash
OCTOPUS_AGENT_TEAMS=legacy "${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh" auto "<user's full request>"
```

Or use a specific command if the intent is clear:
- Research: `probe "<question>"`
- Define: `define "<requirements>"`
- Build: `develop "<implementation>"`
- Review: `deliver "<review target>"`
- Security: `squeeze "<audit target>"`
- Debate: `grapple "<topic>"`
- Full workflow: `embrace "<task>"`

**WAIT for completion. Do NOT proceed until it finishes.**

## Step 3: Read results

```bash
RESULT_FILE=$(find ~/.claude-octopus/results -name "*.md" | sort -r | head -n1)
if [[ -z "$RESULT_FILE" ]]; then
  echo "ERROR: No result file found"
  ls -lt ~/.claude-octopus/results/ 2>/dev/null | head -5
else
  echo "OK: $RESULT_FILE"
  cat "$RESULT_FILE"
fi
```

## Step 4: Present results with attribution footer

```
---
Multi-AI Orchestration powered by Claude Octopus
Providers: 🔴 Codex | 🟡 Gemini | 🔵 Claude
```

---

## What NOT to do

- Do NOT use `Task(octo:personas:*)` or any Task agent
- Do NOT handle the task yourself without orchestrate.sh
- Do NOT ask "should I use the plugin?" - JUST USE IT
- If orchestrate.sh fails, tell the user - do NOT work around it
