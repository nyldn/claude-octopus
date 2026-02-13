---
name: octopus-research
aliases:
  - research
  - deep-research
description: Deep multi-AI parallel research with cost transparency and synthesis
context: fork
agent: Explore
task_management: true
execution_mode: enforced
trigger: |
  Use this skill when the user wants to "research this topic", "investigate how X works",
  "analyze the architecture", "explore different approaches to Y", or "what are the options for Z".
---

# STOP. READ THIS FIRST.

**You are FORBIDDEN from researching directly.** You MUST call orchestrate.sh via Bash.

Do NOT use Task agents, web search, native personas, or any other research method.
The ONLY acceptable action is running the Bash command below.

---

## Step 1: Display banner

```
🐙 CLAUDE OCTOPUS ACTIVATED - Multi-provider research mode
🔍 Deep Research: <brief description of topic>

Providers:
🔴 Codex CLI - Technical analysis
🟡 Gemini CLI - Ecosystem research
🔵 Claude - Strategic synthesis
```

## Step 2: Execute orchestrate.sh (USE BASH TOOL NOW)

```bash
OCTOPUS_AGENT_TEAMS=legacy "${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh" probe "<user's research question>"
```

**WAIT for completion. Do NOT proceed until it finishes.**

If it fails, show the error. Do NOT fall back to direct research.

## Step 3: Read synthesis

```bash
SYNTHESIS_FILE=$(find ~/.claude-octopus/results -name "probe-synthesis-*.md" -mmin -10 2>/dev/null | head -n1)
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
Multi-AI Research powered by Claude Octopus
Providers: 🔴 Codex | 🟡 Gemini | 🔵 Claude
```

---

## What NOT to do

- Do NOT use `Task(octo:personas:*)` or any Task agent
- Do NOT use WebSearch or WebFetch
- Do NOT research the topic yourself
- If orchestrate.sh fails, tell the user - do NOT work around it
