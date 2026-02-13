---
command: validate
description: "Run comprehensive multi-AI validation on code or project targets"
---

# Validate - Multi-AI Validation

## INSTRUCTIONS FOR CLAUDE

When the user invokes this command (e.g., `/octo:validate <arguments>`):

### Step 1: Display Banner

Output this text to the user before executing:

```
🐙 CLAUDE OCTOPUS ACTIVATED - Multi-provider validation mode
✅ Validate: <brief description of target>

Providers:
🔴 Codex CLI - Quality analysis
🟡 Gemini CLI - Edge cases and security
🔵 Claude - Debate synthesis
```

### Step 2: Execute orchestrate.sh (USE BASH TOOL NOW)

**CRITICAL: You MUST execute this bash command. Do NOT skip it.**

```bash
OCTOPUS_AGENT_TEAMS=legacy "${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh" grapple "<user's validation target>"
```

**WAIT for completion. Do NOT proceed until it finishes.**

If it fails, show the error. Do NOT fall back to direct validation.

### Step 3: Read Results

```bash
RESULT_FILE=$(find ~/.claude-octopus/results -name "*grapple*" -o -name "*validate*" 2>/dev/null | sort -r | head -n1)
if [[ -z "$RESULT_FILE" ]]; then
  echo "ERROR: No result file found"
  ls -lt ~/.claude-octopus/results/ 2>/dev/null | head -5
else
  echo "OK: $RESULT_FILE"
  cat "$RESULT_FILE"
fi
```

### Step 4: Present Results

Read the result file content and present it to the user with this footer:

```
---
Multi-AI Validation powered by Claude Octopus
Providers: 🔴 Codex | 🟡 Gemini | 🔵 Claude
Full report: <path to result file>
```

## PROHIBITIONS

- Do NOT validate or score code yourself without orchestrate.sh
- Do NOT use Skill tool or Task tool as substitute
- Do NOT use any Task agents or native personas
- If orchestrate.sh fails, tell the user - do NOT work around it

## Usage

```bash
/octo:validate <target> [--focus security|code-quality|best-practices|performance]
```

## What Gets Validated

- Code quality (style, patterns, maintainability)
- Security (OWASP compliance, vulnerability scanning)
- Best practices (framework and language conventions)
- Performance (efficiency, scalability)
- Returns prioritized findings and an explicit pass/fail recommendation
