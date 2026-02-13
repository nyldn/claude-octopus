---
name: octopus-architecture
aliases:
  - architecture
description: System architecture and API design with multi-AI consensus
execution_mode: enforced
---

# STOP. READ THIS FIRST.

**You are FORBIDDEN from designing architecture directly.** You MUST call orchestrate.sh via Bash.

Do NOT use Task agents, native personas (backend-architect, etc.), or direct analysis.
The ONLY acceptable action is running the Bash command below.

---

## Step 1: Display banner

```
🐙 CLAUDE OCTOPUS ACTIVATED - Architecture design mode
🏗️ Architecture: <brief description of system>

Providers:
🔴 Codex CLI - Technical architecture patterns
🟡 Gemini CLI - Ecosystem and scalability analysis
🔵 Claude - Strategic synthesis
```

## Step 2: Execute orchestrate.sh (USE BASH TOOL NOW)

```bash
touch /tmp/.octopus-arch-marker && OCTOPUS_AGENT_TEAMS=legacy "${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh" auto "architect <user's architecture request>"
```

**WAIT for completion. Do NOT proceed until it finishes.**

If it fails, show the error. Do NOT fall back to direct architecture work.

## Step 3: Read results

```bash
RESULT_FILE=$(find ~/.claude-octopus/results -type f -name "*.md" -newer /tmp/.octopus-arch-marker 2>/dev/null | sort -r | head -n1)
if [[ -z "$RESULT_FILE" ]]; then
  RESULT_FILE=$(find ~/.claude-octopus/results -type f -name "*.md" | sort -r | head -n1)
fi
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
Multi-AI Architecture Review powered by Claude Octopus
Providers: 🔴 Codex | 🟡 Gemini | 🔵 Claude
```

---

## What NOT to do

- Do NOT use `Task(octo:personas:backend-architect)` or any Task agent
- Do NOT design the architecture yourself
- If orchestrate.sh fails, tell the user - do NOT work around it
