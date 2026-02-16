---
command: grasp
description: Definition phase - Requirements clarification and scope definition
---

# Grasp - Definition Phase (Double Diamond)

## 🤖 INSTRUCTIONS FOR CLAUDE

When the user invokes this command (e.g., `/octo:grasp <arguments>`):

**✓ CORRECT - Use the Skill tool:**
```
Skill(skill: "octo:grasp", args: "<user's arguments>")
```

**✗ INCORRECT - Do NOT use Task tool:**
```
Task(subagent_type: "octo:grasp", ...)  ❌ Wrong! This is a skill, not an agent type
```

**Why:** This command loads the `flow-grasp` skill. Skills use the `Skill` tool, not `Task`.

---

**Auto-loads the `flow-grasp` skill for the requirements/definition phase.**

## Quick Usage

Just use natural language:
```
"Define requirements for the authentication system"
"Grasp the scope of the payment integration"
"Clarify requirements for the API redesign"
```

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
