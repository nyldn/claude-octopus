---
command: tangle
description: Development phase - Multi-AI implementation with quality gates
---

# Tangle - Development Phase (Double Diamond)

## 🤖 INSTRUCTIONS FOR CLAUDE

When the user invokes this command (e.g., `/octo:tangle <arguments>`):

**✓ CORRECT - Use the Skill tool:**
```
Skill(skill: "octo:tangle", args: "<user's arguments>")
```

**✗ INCORRECT - Do NOT use Task tool:**
```
Task(subagent_type: "octo:tangle", ...)  ❌ Wrong! This is a skill, not an agent type
```

**Why:** This command loads the `flow-tangle` skill. Skills use the `Skill` tool, not `Task`.

---

**Auto-loads the `flow-tangle` skill for the development/implementation phase.**

## Quick Usage

Just use natural language:
```
"Build the authentication system"
"Tangle implementation for the payment flow"
"Develop the new API endpoints"
```

## What Is Tangle?

The **Develop** phase of the Double Diamond methodology:
- Divergent implementation
- Multiple approaches exploration
- Rapid prototyping
- Quality gates

## What You Get

- Multi-AI implementation approaches
- Code quality validation
- Security checks
- Performance considerations
- Test coverage

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

```
"Build a user authentication system with OAuth"
"Tangle the payment processing integration"
"Develop the real-time notification system"
```
