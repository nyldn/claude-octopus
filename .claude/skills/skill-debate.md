---
name: skill-debate
aliases:
  - debate
description: Structured three-way AI debates via orchestrate.sh grapple
context: fork
execution_mode: enforced
pre_execution_contract:
  - visual_indicators_displayed
validation_gates:
  - orchestrate_sh_executed
  - synthesis_file_exists
trigger: |
  AUTOMATICALLY ACTIVATE when user says:
  - "/debate <question>"
  - "run a debate about X"
  - "I want gemini and codex to review X"
  - "debate whether X or Y"

  Supports flags:
  - -r/--rounds N (3-7 rounds, default 3)
  - -d quick → -r 3
  - -d thorough → -r 5
  - -d adversarial → -r 3 (default grapple)
  - --principles TYPE (general, security, performance, maintainability)
---

# STOP. READ THIS FIRST.

## EXECUTION CONTRACT

1. You MUST call `orchestrate.sh grapple` via the Bash tool.
2. You MUST display the visual indicator banner BEFORE execution.
3. You are PROHIBITED from debating the topic yourself.
4. You are PROHIBITED from calling codex/gemini CLI directly.
5. You are PROHIBITED from using Task agents, web search, or native personas.
6. You CANNOT SKIP the orchestrate.sh call for any reason.
7. You MUST verify `validation_gates`: confirm orchestrate.sh exited 0 and a
   synthesis file exists in `~/.claude-octopus/results/grapple-*.md`.
8. If orchestrate.sh fails, report the error. You are PROHIBITED from
   falling back to direct debate or any workaround.

---

## Step 1: Parse flags

Map user flags to orchestrate.sh grapple options:
- `-r N` / `--rounds N` → pass as-is (3-7, default 3)
- `-d quick` → `-r 3`
- `-d thorough` → `-r 5`
- `-d adversarial` → `-r 3` (grapple default)
- `--principles TYPE` → pass as-is (general, security, performance, maintainability)

## Step 2: Display banner

Output this text to the user before executing:

```text
🐙 **CLAUDE OCTOPUS ACTIVATED** - AI Debate Hub
🐙 Debate: <brief description of debate topic>
🧭 Phase: Orchestration

Participants:
🔴 Codex CLI - Technical implementation perspective (~$0.01–$0.15/query)
🟡 Gemini CLI - Ecosystem and strategic perspective (~$0.01–$0.03/query)
🔵 Claude - Moderator and synthesis (included with subscription)
```

## Step 3: Execute orchestrate.sh (USE BASH TOOL NOW)

Run this command with the Bash tool. Replace placeholders with parsed values.

```bash
OCTOPUS_AGENT_TEAMS=legacy "${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh" grapple -r <rounds> --principles <principles> "<user's debate question>"
```

**WAIT for the command to complete. Do NOT proceed until it finishes.**

If it fails, show the error to the user. Do NOT fall back to direct debate.

## Step 4: Read the synthesis file

```bash
SYNTHESIS_FILE=$(find ~/.claude-octopus/results -name "grapple-*.md" 2>/dev/null | sort -r | head -n1)
if [[ -z "$SYNTHESIS_FILE" ]]; then
  echo "ERROR: No synthesis file found"
  ls -lt ~/.claude-octopus/results/ 2>/dev/null | head -5
else
  echo "OK: $SYNTHESIS_FILE"
  cat "$SYNTHESIS_FILE"
fi
```

If no synthesis file exists, report the failure. Do NOT substitute with your own debate.

## Step 5: Present results

Read the synthesis file content and present it to the user with this footer:

```text
---
Multi-AI Debate powered by Claude Octopus
Participants: 🔴 Codex (~$0.01–$0.15) | 🟡 Gemini (~$0.01–$0.03) | 🔵 Claude (included)
Full synthesis: <path to synthesis file>
```

---

## What NOT to do

- Do NOT call codex/gemini CLI directly
- Do NOT debate the topic yourself
- Do NOT use Task agents or web search
- Do NOT skip the orchestrate.sh call for any reason
- Do NOT ask clarifying questions before running — grapple handles its own flow
- If orchestrate.sh fails, tell the user — do NOT work around it
