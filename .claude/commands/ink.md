---
command: ink
description: Delivery phase - Quality assurance, validation, and review
---

# Ink - Delivery Phase (Double Diamond)

## INSTRUCTIONS FOR CLAUDE

When the user invokes this command (e.g., `/octo:ink <arguments>`):

### Step 1: Display Banner

Output this text to the user before executing:

```text
🐙 CLAUDE OCTOPUS ACTIVATED - Multi-provider validation mode
✅ Deliver Phase: <brief description of what's being validated>

Providers:
🔴 Codex CLI - Code quality analysis
🟡 Gemini CLI - Security and edge cases
🔵 Claude - Synthesis and recommendations
```

### Step 2: Execute orchestrate.sh (USE BASH TOOL NOW)

**CRITICAL: You MUST execute this bash command. Do NOT skip it.**

```bash
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

## What Is Ink?

The **Deliver** phase of the Double Diamond methodology:
- Convergent validation
- Quality assurance
- Security review
- Production readiness

## Validation Checks

- Code quality (style, patterns, maintainability)
- Security (OWASP Top 10, vulnerabilities)
- Performance (bottlenecks, optimizations)
- Tests (coverage, quality, edge cases)
- Documentation (completeness, clarity)

## When To Use

- Before merging code
- Pre-production deployment
- Feature completion
- Quality gates
- Security audits

## Natural Language Examples

```text
"Review the authentication module for production"
"Ink validation of the payment processing code"
"Quality assurance check for the new API"
```
