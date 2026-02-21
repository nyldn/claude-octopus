---
command: deliver
description: "Delivery phase - Review, validate, and test with multi-AI quality assurance"
aliases:
  - ink
  - review-phase
---

# Deliver - Delivery Phase ✅

## 🤖 INSTRUCTIONS FOR CLAUDE

When the user invokes this command (e.g., `/octo:deliver <arguments>`):

**✓ CORRECT - Use the Skill tool:**
```
Skill(skill: "octo:deliver", args: "<user's arguments>")
```

**✗ INCORRECT - Do NOT use Task tool:**
```
Task(subagent_type: "octo:deliver", ...)  ❌ Wrong! This is a skill, not an agent type
```

**Why:** This command loads the `flow-deliver` skill. Skills use the `Skill` tool, not `Task`.

---

**Auto-loads the `flow-deliver` skill for the validation/review phase.**

## Quick Usage

Just use natural language:
```
"Review the authentication code for security"
"Validate the caching implementation"
"Test the notification system"
```

## What Is Deliver?

The **Deliver** phase of the Double Diamond methodology (convergent thinking):
- Validate and review implementations using external CLI providers
- Security audit and edge case analysis
- Final quality synthesis

## What You Get

- Multi-AI validation (Claude + Gemini + Codex)
- Security audit (OWASP compliance, vulnerability detection)
- Code quality review
- Edge case analysis
- Performance evaluation

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
4. **Deliver** <- You are here

To run all 4 phases: `/octo:embrace`
