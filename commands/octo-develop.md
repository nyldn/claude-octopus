---
description: "\"Development phase - Build solutions with multi-AI implementation and quality gates\""
---

# Develop - Development Phase 🛠️

## 🤖 INSTRUCTIONS FOR CLAUDE

### MANDATORY COMPLIANCE — DO NOT SKIP

**When the user explicitly invokes `/octo:develop`, you MUST execute the structured workflow below.** You are PROHIBITED from doing the task directly, skipping the development phase with quality gates, or deciding the task is "too simple" for this workflow. The user chose this command deliberately — respect that choice.

### EXECUTION MECHANISM — NON-NEGOTIABLE

**You MUST execute this command via the Bash tool calling `orchestrate.sh develop`. You are PROHIBITED from:**
- Using `Skill(skill: "octo:develop")` because it resolves back to this file and loops
- Using `Skill(skill: "flow-develop", ...)` because that internal name is not resolvable by the Skill tool
- Using the Agent tool, WebFetch, Read, or Grep as a substitute for multi-provider dispatch
- Skipping `orchestrate.sh` calls because "I can do this faster directly"
- Implementing the task using only Claude-native tools

**Multi-LLM orchestration is the purpose of this command.** If you execute using only Claude, you've violated the command's contract.

---

When the user invokes this command (e.g., `/octo:develop <arguments>`):

**Step 1 — Run provider preflight via Bash tool:**

```bash
bash "${HOME}/.claude-octopus/plugin/scripts/helpers/check-providers.sh"
```

Use the actual preflight output to display the workflow indicator before dispatch:

```text
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider implementation mode
```

List available providers and mark missing providers as `(unavailable - skipping)`. If `OCTOPUS_COMPACT_BANNERS=true`, use this compact single-line format:

```text
🐙 develop — Multi-provider implementation mode | codex ✓ | gemini (unavailable - skipping)
```

If no external provider is available, stop and tell the user to run `/octo:setup`; do not fall back to Claude-native implementation.

**Step 2 — Run orchestrate.sh via Bash tool:**

```bash
bash "${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh" develop "<user's arguments here>"
```

**✗ INCORRECT:**

```text
Skill(skill: "octo:develop", ...)  ❌ Resolves to this command file — infinite loop
Skill(skill: "flow-develop", ...)  ❌ Internal name, not resolvable by Skill tool
Task(subagent_type: "octo:develop", ...)  ❌ This is a skill, not an agent type
```

### Post-Completion — Interactive Next Steps

**CRITICAL: After the workflow completes, you MUST ask the user what to do next. Do NOT end the session silently.**

```javascript
AskUserQuestion({
  questions: [
    {
      question: "Development phase complete. What would you like to do next?",
      header: "Next Steps",
      multiSelect: false,
      options: [
        {label: "Move to Deliver phase", description: "Validate and review the implementation (/octo:deliver)"},
        {label: "Iterate on the implementation", description: "Make adjustments or handle edge cases"},
        {label: "Run quality gates again", description: "Re-validate with updated code"},
        {label: "Export the implementation", description: "Save a summary of what was built"},
        {label: "Done for now", description: "I have what I need"}
      ]
    }
  ]
})
```

---

**Dispatches to the develop workflow via `orchestrate.sh` for the implementation phase.**

### Model and Effort Policy

- For develop/tangle work on Opus 4.7, use `xhigh` for complex implementation and `medium` for trivial work.
- Fast Opus 4.6 mode is 6x more expensive ($30/$150 per MTok vs $5/$25 standard), uses extra-usage billing, applies only to Opus 4.6, and trades cost for lower latency with equivalent quality.
- Default to Opus 4.7 standard mode for multi-phase workflows; use fast mode only for interactive single-shot requests when explicitly selected.
- Respect user overrides: `OCTOPUS_OPUS_MODE`, `OCTOPUS_OPUS_MODEL`, and `OCTOPUS_EFFORT_OVERRIDE`.
- Record durable project memory for autonomy mode, provider availability, frequently used commands, prior project context, and model preferences.

## Quick Usage

Just use natural language:
```
"Build a user authentication system"
"Implement OAuth 2.0 flow"
"Create a caching layer for the API"
```

## What Is Develop?

The **Develop** phase of the Double Diamond methodology (divergent thinking for solutions):
- Multiple implementation approaches via external CLI providers
- Code generation and technical patterns
- Quality gate validation

## What You Get

- Multi-AI implementation (Claude + Gemini + Codex)
- Multiple implementation approaches
- Quality gate validation (75% consensus threshold)
- Security checks (OWASP compliance)
- Best practices enforcement

## When to Use Develop

Use develop when you need:
- **Building**: "Build X" or "Implement Y"
- **Creating**: "Create Z feature"
- **Code Generation**: "Write code to do Y"

## Part of the Full Workflow

Develop is phase 3 of 4 in the embrace (full) workflow:
1. Discover
2. Define
3. **Develop** <- You are here
4. Deliver

To run all 4 phases: `/octo:embrace`
