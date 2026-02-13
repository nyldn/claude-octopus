---
name: skill-code-review
aliases:
  - review
  - code-review
description: Expert multi-AI code review with quality and security analysis
context: fork
agent: Explore
execution_mode: enforced
---

# STOP. READ THIS FIRST.

**You are FORBIDDEN from reviewing code directly.** You MUST call orchestrate.sh via Bash.

Do NOT use Task agents, native personas (code-reviewer, etc.), or direct analysis.
The ONLY acceptable action is running the Bash command below.

---

## Step 1: Display banner

```
🐙 CLAUDE OCTOPUS ACTIVATED - Multi-provider code review
📝 Review: <brief description of what's being reviewed>

Providers:
🔴 Codex CLI - Code quality analysis
🟡 Gemini CLI - Alternative patterns and edge cases
🔵 Claude - Synthesis and recommendations
```

## Step 2: Execute orchestrate.sh (USE BASH TOOL NOW)

```bash
OCTOPUS_AGENT_TEAMS=legacy "${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh" auto "review <user's code review request>"
```

**WAIT for completion. Do NOT proceed until it finishes.**

If it fails, show the error. Do NOT fall back to direct code review.

## Step 3: Read results

```bash
RESULT_FILE=$(find ~/.claude-octopus/results -name "delivery-*.md" | sort -r | head -n1)
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
Multi-AI Code Review powered by Claude Octopus
Providers: 🔴 Codex | 🟡 Gemini | 🔵 Claude
```

---

## What NOT to do

- Do NOT use `Task(octo:personas:code-reviewer)` or any Task agent
- Do NOT review the code yourself
- If orchestrate.sh fails, tell the user - do NOT work around it
