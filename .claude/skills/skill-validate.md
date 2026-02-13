---
name: skill-validate
description: Multi-AI adversarial validation via structured debate between providers
version: 1.0.0
category: workflow
tags: [validation, quality-assurance, debate, security, testing]
execution_mode: enforced
---

# STOP. READ THIS FIRST.

**You are FORBIDDEN from validating directly.** You MUST call orchestrate.sh via Bash.

Do NOT use Task agents, native personas, or direct analysis.
The ONLY acceptable action is running the Bash command below.

---

## Step 1: Display banner

```
🐙 CLAUDE OCTOPUS ACTIVATED - Multi-provider validation mode
✅ Validate: <brief description of target>

Providers:
🔴 Codex CLI - Quality analysis
🟡 Gemini CLI - Edge cases and security
🔵 Claude - Debate synthesis
```

## Step 2: Execute orchestrate.sh (USE BASH TOOL NOW)

```bash
OCTOPUS_AGENT_TEAMS=legacy "${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh" grapple "<user's validation target>"
```

**WAIT for completion. Do NOT proceed until it finishes.**

If it fails, show the error. Do NOT fall back to direct validation.

## Step 3: Read results

```bash
RESULT_FILE=$(find ~/.claude-octopus/results -name "*grapple*" -o -name "*validate*" | sort -r | head -n1)
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
Multi-AI Validation powered by Claude Octopus
Providers: 🔴 Codex | 🟡 Gemini | 🔵 Claude
```

---

## What NOT to do

- Do NOT use `Task(octo:personas:*)` or any Task agent
- Do NOT validate or score the code yourself
- If orchestrate.sh fails, tell the user - do NOT work around it
