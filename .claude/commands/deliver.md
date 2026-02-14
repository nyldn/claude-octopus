---
command: deliver
description: "Delivery phase - Review, validate, and test with multi-AI quality assurance"
aliases:
  - review-phase
---

# Deliver - Delivery Phase ✅

## INSTRUCTIONS FOR CLAUDE

When the user invokes this command (e.g., `/octo:deliver <arguments>`):

### Step 1: Display Banner

Output this text to the user before executing:

```text
🐙 CLAUDE OCTOPUS ACTIVATED - Multi-provider validation mode
✅ Deliver Phase: <brief description of what's being validated>

Providers:
🔴 Codex CLI - Code quality, best practices, technical correctness
🟡 Gemini CLI - Security audit, edge cases, user experience
🔵 Claude - Synthesis and final validation report
```

### Step 2: Execute orchestrate.sh (USE BASH TOOL NOW)

**CRITICAL: You MUST execute this bash command. Do NOT skip it.**

```bash
CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(jq -r '.plugins["octo@ayoahha-plugins"][0].installPath' ~/.claude/plugins/installed_plugins.json)}"
OCTOPUS_AGENT_TEAMS=legacy "${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh" deliver "<user's validation request>"
```

**WAIT for completion. Do NOT proceed until it finishes.**

If it fails, show the error. Do NOT fall back to direct review.

### Step 3: Read Synthesis

```bash
SYNTHESIS_FILE=$(find ~/.claude-octopus/results -name "delivery-*.md" 2>/dev/null | sort -r | head -n1)
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
Multi-AI Validation powered by Claude Octopus
Providers: 🔴 Codex | 🟡 Gemini | 🔵 Claude
Full synthesis: <path to synthesis file>
```

## PROHIBITIONS

- Do NOT review/validate yourself without orchestrate.sh
- Do NOT use Skill tool or Task tool as substitute
- Do NOT use any Task agents or native personas
- If orchestrate.sh fails, tell the user - do NOT work around it

## Usage

```bash
/octo:deliver        # Delivery phase
```

## Natural Language Examples

```text
"Review the authentication code for security"
"Validate the caching implementation"
"Test the notification system"
"Quality check the API endpoints"
```

## Quality Checks

The deliver phase includes:
- **Security audit** - OWASP compliance, vulnerability detection
- **Code quality** - Best practices, maintainability, readability
- **Edge cases** - Error handling, boundary conditions
- **Performance** - Efficiency, scalability
- **User experience** - API design, error messages, documentation

## When to Use Deliver

Use deliver when you need:
- **Review**: "Review X" or "Code review Y"
- **Validation**: "Validate Z"
- **Testing**: "Test the implementation"
- **Quality Check**: "Check if X works correctly"

**Don't use deliver for:**
- Implementation tasks (use develop phase)
- Research tasks (use discover phase)
- Requirement definition (use define phase)

## Part of the Full Workflow

Deliver is phase 4 of 4 in the embrace (full) workflow:
1. Discover
2. Define
3. Develop
4. **Deliver** - You are here

To run all 4 phases: `/octo:embrace`
