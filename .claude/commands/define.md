---
command: define
description: "Definition phase - Clarify and scope problems with multi-AI consensus"
aliases:
  - grasp
  - scope-phase
---

# Define - Definition Phase 🎯

## 🤖 INSTRUCTIONS FOR CLAUDE

When the user invokes this command (e.g., `/octo:define <arguments>`):

**✓ CORRECT - Use the Skill tool:**
```
Skill(skill: "octo:define", args: "<user's arguments>")
```

**✗ INCORRECT - Do NOT use Task tool:**
```
Task(subagent_type: "octo:define", ...)  ❌ Wrong! This is a skill, not an agent type
```

**Why:** This command loads the `flow-define` skill. Skills use the `Skill` tool, not `Task`.

---

**Auto-loads the `flow-define` skill for the definition/scoping phase.**

## Quick Usage

Just use natural language:
```
"Define the requirements for user authentication"
"Clarify the scope of the caching feature"
"What exactly does the notification system need to do?"
```

## What Is Define?

The **Define** phase of the Double Diamond methodology (convergent thinking):
- Clarify and scope problems using external CLI providers
- Technical requirements analysis
- Problem synthesis and requirement definition

## What You Get

- Multi-AI consensus on requirements (Claude + Gemini + Codex)
- Clear problem statement
- Scoped requirements
- Edge case identification
- Constraint analysis

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
2. **Define** <- You are here
3. Develop
4. Deliver

To run all 4 phases: `/octo:embrace`
