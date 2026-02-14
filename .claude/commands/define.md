---
command: define
description: "Definition phase - Clarify and scope problems with multi-AI consensus"
aliases:
  - scope-phase
---

# Define - Definition Phase 🎯

## INSTRUCTIONS FOR CLAUDE

When the user invokes this command (e.g., `/octo:define <arguments>`):

### Step 1: Display Banner

Output this text to the user before executing:

```text
🐙 CLAUDE OCTOPUS ACTIVATED - Multi-provider definition mode
🎯 Define Phase: <brief description of what needs scoping>

Providers:
🔴 Codex CLI - Technical requirements analysis
🟡 Gemini CLI - User needs and business requirements
🔵 Claude - Problem synthesis and requirement definition
```

### Step 2: Execute orchestrate.sh (USE BASH TOOL NOW)

**CRITICAL: You MUST execute this bash command. Do NOT skip it.**

```bash
CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(jq -r '.plugins["octo@ayoahha-plugins"][0].installPath' ~/.claude/plugins/installed_plugins.json)}"
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

```text
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

## Usage

```bash
/octo:define         # Definition phase
```

## Natural Language Examples

```text
"Define the requirements for user authentication"
"Clarify the scope of the caching feature"
"What exactly does the notification system need to do?"
"Scope out the API versioning feature"
```

## When to Use Define

Use define when you need:
- **Requirements**: "Define the requirements for X"
- **Clarification**: "Clarify the scope of Y"
- **Scoping**: "What exactly does X need to do?"
- **Problem Understanding**: "Help me understand the problem with Y"

**Don't use define for:**
- Implementation tasks (use develop phase)
- Research tasks (use discover phase)
- Review tasks (use deliver phase)

## Part of the Full Workflow

Define is phase 2 of 4 in the embrace (full) workflow:
1. Discover
2. **Define** - You are here
3. Develop
4. Deliver

To run all 4 phases: `/octo:embrace`
