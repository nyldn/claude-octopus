---
command: develop
description: "Development phase - Build solutions with multi-AI implementation and quality gates"
aliases:
  - build-phase
---

# Develop - Development Phase 🛠️

## INSTRUCTIONS FOR CLAUDE

When the user invokes this command (e.g., `/octo:develop <arguments>`):

### Step 1: Display Banner

Output this text to the user before executing:

```text
🐙 CLAUDE OCTOPUS ACTIVATED - Multi-provider implementation mode
🛠️ Develop Phase: <brief description of what's being built>

Providers:
🔴 Codex CLI - Implementation-focused, code generation, technical patterns
🟡 Gemini CLI - Alternative approaches, edge cases, best practices
🔵 Claude - Integration, refinement, and final implementation
```

### Step 2: Execute orchestrate.sh (USE BASH TOOL NOW)

**CRITICAL: You MUST execute this bash command. Do NOT skip it.**

```bash
OCTOPUS_AGENT_TEAMS=legacy "${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh" develop "<user's implementation request>"
```

**WAIT for completion. Do NOT proceed until it finishes.**

If it fails, show the error. Do NOT fall back to direct implementation.

### Step 3: Read Synthesis

```bash
SYNTHESIS_FILE=$(find ~/.claude-octopus/results -name "tangle-validation-*.md" 2>/dev/null | sort -r | head -n1)
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
Multi-AI Implementation powered by Claude Octopus
Providers: 🔴 Codex | 🟡 Gemini | 🔵 Claude
Full synthesis: <path to synthesis file>
```

## PROHIBITIONS

- Do NOT implement the solution yourself without orchestrate.sh
- Do NOT use Skill tool or Task tool as substitute
- Do NOT use any Task agents or native personas
- If orchestrate.sh fails, tell the user - do NOT work around it

## Usage

```bash
/octo:develop        # Development phase
```

## Natural Language Examples

```text
"Build a user authentication system"
"Implement OAuth 2.0 flow"
"Create a caching layer for the API"
"Develop a real-time notification feature"
```

## Quality Gates

The develop phase includes automatic quality validation:
- **75% consensus threshold** - Implementation must meet quality standards
- **Security checks** - OWASP compliance verification
- **Best practices** - Framework and language conventions
- **Performance** - Efficiency and scalability considerations

## When to Use Develop

Use develop when you need:
- **Building**: "Build X" or "Implement Y"
- **Creating**: "Create Z feature"
- **Code Generation**: "Write code to do Y"

**Don't use develop for:**
- Simple code edits (use Edit tool)
- Reading or reviewing code (use Read/review)
- Trivial single-file changes

## Part of the Full Workflow

Develop is phase 3 of 4 in the embrace (full) workflow:
1. Discover
2. Define
3. **Develop** - You are here
4. Deliver

To run all 4 phases: `/octo:embrace`
