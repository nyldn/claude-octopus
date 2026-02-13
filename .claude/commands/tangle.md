---
command: tangle
description: Development phase - Multi-AI implementation with quality gates
---

# Tangle - Development Phase (Double Diamond)

## INSTRUCTIONS FOR CLAUDE

When the user invokes this command (e.g., `/octo:tangle <arguments>`):

### Step 1: Display Banner

Output this text to the user before executing:

```text
🐙 CLAUDE OCTOPUS ACTIVATED - Multi-provider implementation mode
🛠️ Develop Phase: <brief description of what's being built>

Providers:
🔴 Codex CLI - Code generation and patterns
🟡 Gemini CLI - Alternative approaches and review
🔵 Claude - Integration and quality gates
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

## What Is Tangle?

The **Develop** phase of the Double Diamond methodology:
- Divergent implementation
- Multiple approaches exploration
- Rapid prototyping
- Quality gates

## Quality Gates

- 75% consensus threshold
- Security vulnerability scanning
- Code quality assessment
- Test coverage validation

## When To Use

- Implementing new features
- Building prototypes
- Exploring solutions
- Complex implementations

## Natural Language Examples

```text
"Build a user authentication system with OAuth"
"Tangle the payment processing integration"
"Develop the real-time notification system"
```
