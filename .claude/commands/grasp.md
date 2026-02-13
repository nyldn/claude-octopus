---
command: grasp
description: Definition phase - Requirements clarification and scope definition
---

# Grasp - Definition Phase (Double Diamond)

## INSTRUCTIONS FOR CLAUDE

When the user invokes this command (e.g., `/octo:grasp <arguments>`):

### Step 1: Display Banner

Output this text to the user before executing:

```
🐙 CLAUDE OCTOPUS ACTIVATED - Multi-provider definition mode
🎯 Define Phase: <brief description of what needs scoping>

Providers:
🔴 Codex CLI - Technical requirements analysis
🟡 Gemini CLI - Ecosystem and best practices
🔵 Claude - Strategic synthesis
```

### Step 2: Execute orchestrate.sh (USE BASH TOOL NOW)

**CRITICAL: You MUST execute this bash command. Do NOT skip it.**

```bash
OCTOPUS_AGENT_TEAMS=legacy "${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh" define "<user's clarification request>"
```

**WAIT for completion. Do NOT proceed until it finishes.**

If it fails, show the error. Do NOT fall back to direct analysis.

### Step 3: Read Synthesis

```bash
SYNTHESIS_FILE=$(find ~/.claude-octopus/results -name "grasp-consensus-*.md" 2>/dev/null | sort -r | head -n1)
if [[ -z "$SYNTHESIS_FILE" ]]; then
  echo "ERROR: No synthesis file found"
  ls -lt ~/.claude-octopus/results/ 2>/dev/null | head -5
else
  echo "OK: $SYNTHESIS_FILE"
  cat "$SYNTHESIS_FILE"
fi
```

### Step 4: Present Results

Read the synthesis file content and present it to the user with this footer:

```
---
Multi-AI Definition powered by Claude Octopus
Providers: 🔴 Codex | 🟡 Gemini | 🔵 Claude
Full synthesis: <path to synthesis file>
```

## PROHIBITIONS

- Do NOT define requirements yourself without orchestrate.sh
- Do NOT use Skill tool or Task tool as substitute
- Do NOT use any Task agents or native personas
- If orchestrate.sh fails, tell the user - do NOT work around it

## What Is Grasp?

The **Define** phase of the Double Diamond methodology:
- Convergent thinking
- Requirements clarification
- Scope definition
- Problem statement refinement

## What You Get

- Clear problem definition
- Prioritized requirements
- Scope boundaries
- Success criteria
- Constraints identification

## When To Use

- After research/discovery
- Before implementation
- Clarifying ambiguous requirements
- Scoping features
- Planning sprints

## Natural Language Examples

```
"Define the requirements for user authentication"
"Grasp what we need for the payment system integration"
"Clarify the scope of the API v2 redesign"
```
