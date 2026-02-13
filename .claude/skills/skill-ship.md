---
name: skill-ship
description: Finalize and deliver completed work with Multi-AI validation
trigger: |
  AUTOMATICALLY ACTIVATE when user mentions:
  - "ship" or "deliver" or "finalize"
  - "done" or "complete the project"

  Do NOT use for: code review (use flow-deliver), implementation (use flow-develop).
execution_mode: enforced
---

# STOP. READ THIS FIRST.

**You are FORBIDDEN from shipping without multi-AI validation.** You MUST call orchestrate.sh via Bash.

Do NOT use Task agents, native personas, or skip the validation step.
The ONLY acceptable action is running the Bash command below.

---

## Step 1: Display banner

```
🐙 CLAUDE OCTOPUS ACTIVATED - Ship validation mode
🚀 Ship: <brief description of project>

Providers:
🔴 Codex CLI - Final quality check
🟡 Gemini CLI - Security and edge case audit
🔵 Claude - Ship readiness synthesis
```

## Step 2: Execute orchestrate.sh (USE BASH TOOL NOW)

```bash
OCTOPUS_AGENT_TEAMS=legacy "${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh" deliver "Final validation before shipping: <user's project description>"
```

**WAIT for completion. Do NOT proceed until it finishes.**

If it fails, show the error. Do NOT ship without validation.

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

## Step 4: Present ship readiness

Present the validation results and recommend whether to ship or fix issues first.

```
---
Multi-AI Ship Validation powered by Claude Octopus
Providers: 🔴 Codex | 🟡 Gemini | 🔵 Claude
```

---

## What NOT to do

- Do NOT use `Task(octo:personas:*)` or any Task agent
- Do NOT ship without running orchestrate.sh validation
- If orchestrate.sh fails, tell the user - do NOT work around it
