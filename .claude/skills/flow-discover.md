---
name: flow-discover
aliases:
  - discover
  - discover-workflow
  - probe
  - probe-workflow
description: Multi-AI research using Codex and Gemini CLIs (Double Diamond Discover phase)
  - Questions about best practices, patterns, or ecosystem research

  PRIORITY TRIGGERS (always invoke): "octo research", "octo discover", "co-research", "co-discover"

  DO NOT use for: simple file searches (use Read/Grep), questions Claude can answer directly,
  debugging issues (use skill-debug), or "what are my options" for decision support.

# Claude Code v2.1.12+ Integration
agent: Explore
context: fork
task_management: true
execution_mode: enforced
trigger: |
  AUTOMATICALLY ACTIVATE when user requests research or exploration:
  - "research X" or "explore Y" or "investigate Z"
  - "what are the options for X" or "what are my choices for Y"
  - "find information about Y" or "look up Z"
  - "analyze different approaches to Z" or "evaluate approaches"
  - Questions about best practices, patterns, or ecosystem research
  - Comparative analysis ("compare X vs Y" or "X vs Y comparison")

  DO NOT activate for:
  - Simple file searches or code reading (use Read/Grep tools)
  - Questions Claude can answer directly from knowledge
  - Debugging issues (use skill-debug instead)
---

# STOP. READ THIS FIRST.

**You are FORBIDDEN from researching directly.** You MUST call orchestrate.sh via Bash.

Do NOT use Task agents, web search, native personas, or any other research method.
The ONLY acceptable action is running the Bash command below.

---

## Step 1: Display banner

Output this text to the user before executing:

```
🐙 CLAUDE OCTOPUS ACTIVATED - Multi-provider research mode
🔍 Discover Phase: <brief description of research topic>

Providers:
🔴 Codex CLI - Technical implementation analysis
🟡 Gemini CLI - Ecosystem and community research
🔵 Claude - Strategic synthesis
```

## Step 2: Execute orchestrate.sh (USE BASH TOOL NOW)

Run this command with the Bash tool. Replace the placeholder with the user's research question.

```bash
OCTOPUS_AGENT_TEAMS=legacy "${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh" probe "<user's research question>"
```

**WAIT for the command to complete. Do NOT proceed until it finishes.**

If it fails, show the error to the user. Do NOT fall back to direct research.

## Step 3: Read the synthesis file

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

If no synthesis file exists, report the failure. Do NOT substitute with your own research.

## Step 4: Present results

Read the synthesis file content and present it to the user with this footer:

```
---
Multi-AI Research powered by Claude Octopus
Providers: 🔴 Codex | 🟡 Gemini | 🔵 Claude
Full synthesis: <path to synthesis file>
```

---

## What NOT to do

- Do NOT use `Task(octo:personas:research-synthesizer)` or any Task agent
- Do NOT use WebSearch or WebFetch
- Do NOT research the topic yourself
- Do NOT say "let me research this" and then use your own knowledge
- Do NOT skip the orchestrate.sh call for any reason
- If orchestrate.sh fails, tell the user - do NOT work around it
