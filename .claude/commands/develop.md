---
command: develop
description: "Development phase - Build solutions with multi-AI implementation and quality gates"
aliases:
  - tangle
  - build-phase
---

# Develop - Development Phase 🛠️

## 🤖 INSTRUCTIONS FOR CLAUDE

### MANDATORY COMPLIANCE — DO NOT SKIP

**When the user explicitly invokes `/octo:develop`, you MUST execute the structured workflow below.** You are PROHIBITED from doing the task directly, skipping the development phase with quality gates, or deciding the task is "too simple" for this workflow. The user chose this command deliberately — respect that choice.

---

When the user invokes this command (e.g., `/octo:develop <arguments>`):

**✓ CORRECT - Use the Skill tool:**
```
Skill(skill: "flow-develop", args: "<user's arguments>")
```

**✗ INCORRECT - Do NOT use Task tool:**
```
Task(subagent_type: "octo:develop", ...)  ❌ Wrong! This is a skill, not an agent type
```

**Why:** This command loads the `flow-develop` skill. Skills use the `Skill` tool, not `Task`.

### Post-Completion — Interactive Next Steps

**CRITICAL: After the skill completes, you MUST ask the user what to do next. Do NOT end the session silently.**

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

**Auto-loads the `flow-develop` skill for the implementation phase.**

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
