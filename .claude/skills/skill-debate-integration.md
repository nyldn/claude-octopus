---
name: skill-debate-integration
description: "Internal: quality gates and export for AI debates"
trigger: |
  AUTOMATICALLY ACTIVATE when:
  - User runs /debate command
  - AI Debate Hub (.dependencies/claude-skills/skills/debate.md) is present
  - Running in claude-octopus context

  Provides enhancements without modifying the original skill.
execution_mode: enforced
---

# STOP. READ THIS FIRST.

**You are FORBIDDEN from running debates directly.** You MUST call orchestrate.sh via Bash.

Do NOT use Task agents, native personas, or direct multi-model debate.
The ONLY acceptable action is running the Bash command below.

---

## Step 1: Display banner

```
🐙 CLAUDE OCTOPUS ACTIVATED - AI Debate Hub
🐙 Debate: <topic>

Participants:
🔴 Codex CLI - Technical perspective
🟡 Gemini CLI - Ecosystem perspective
🔵 Claude - Moderator and synthesis
```

## Step 2: Execute orchestrate.sh (USE BASH TOOL NOW)

```bash
OCTOPUS_AGENT_TEAMS=legacy "${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh" grapple "<debate topic>"
```

For adversarial debates with more rounds:
```bash
OCTOPUS_AGENT_TEAMS=legacy "${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh" grapple -r 5 "<debate topic>"
```

**WAIT for completion. Do NOT proceed until it finishes.**

## Step 3: Read results

```bash
RESULT_FILE=$(find ~/.claude-octopus/results -name "*grapple*" -o -name "*debate*" | sort -r | head -n1)
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
AI Debate powered by Claude Octopus
Original Skill: AI Debate Hub by wolverin0 (MIT)
Providers: 🔴 Codex | 🟡 Gemini | 🔵 Claude
```

---

## What NOT to do

- Do NOT use `Task(octo:personas:*)` or any Task agent
- Do NOT simulate a debate yourself
- If orchestrate.sh fails, tell the user - do NOT work around it
