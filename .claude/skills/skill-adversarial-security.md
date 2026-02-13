---
name: octopus-security
aliases:
  - security
  - adversarial-security
  - red-team
description: Adversarial red team security testing with blue/red team cycle
trigger: |
  Use this skill when the user says "security audit this code", "find vulnerabilities in X",
  "red team review", "pentest this API", or "check for OWASP issues".
execution_mode: enforced
---

# STOP. READ THIS FIRST.

**You are FORBIDDEN from doing security analysis directly.** You MUST call orchestrate.sh via Bash.

Do NOT use Task agents, native personas (security-auditor, etc.), or direct analysis.
The ONLY acceptable action is running the Bash command below.

---

## Step 1: Display banner

```
🐙 CLAUDE OCTOPUS ACTIVATED - Adversarial security mode
🔒 Red Team: <brief description of target>

Providers:
🔴 Codex CLI - Blue team (defend)
🟡 Gemini CLI - Red team (attack)
🔵 Claude - Moderate and synthesize
```

## Step 2: Execute orchestrate.sh (USE BASH TOOL NOW)

```bash
OCTOPUS_AGENT_TEAMS=legacy "${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh" squeeze "<user's security audit request>"
```

**WAIT for completion. Do NOT proceed until it finishes.**

If it fails, show the error. Do NOT fall back to direct security analysis.

## Step 3: Read results

```bash
RESULT_FILE=$(find ~/.claude-octopus/results -name "squeeze-*.md" -o -name "security-*.md" | sort -r | head -n1)
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
Multi-AI Security Audit powered by Claude Octopus
Providers: 🔴 Codex (Blue) | 🟡 Gemini (Red) | 🔵 Claude (Moderator)
```

---

## What NOT to do

- Do NOT use `Task(octo:personas:security-auditor)` or any Task agent
- Do NOT analyze security yourself
- If orchestrate.sh fails, tell the user - do NOT work around it
