---
command: tdd
description: Test-driven development with red-green-refactor discipline
---

# TDD - Test-Driven Development Skill

## 🤖 INSTRUCTIONS FOR CLAUDE

When the user invokes this command (e.g., `/octo:tdd <arguments>`):

**✓ CORRECT - Use the Skill tool:**
```
Skill(skill: "octo:tdd", args: "<user's arguments>")
```

**✗ INCORRECT - Do NOT use Task tool:**
```
Task(subagent_type: "octo:tdd", ...)  ❌ Wrong! This is a skill, not an agent type
```

**Why:** This command loads the `skill-tdd` skill. Skills use the `Skill` tool, not `Task`.

---

**Auto-loads the `skill-tdd` skill for test-first development.**

## Quick Usage

Just use natural language:
```
"Use TDD to implement the authentication feature"
"Write tests first for the payment processing"
"TDD approach for the new API endpoint"
```

## TDD Workflow

1. **Red**: Write a failing test
2. **Green**: Write minimal code to pass
3. **Refactor**: Improve code quality
4. **Repeat**: Continue cycle

## What You Get

- Test-first approach enforcement
- Red-green-refactor discipline
- Comprehensive test coverage
- Clean, testable code
- Regression prevention

## Natural Language Examples

```
"Use TDD to build a user registration feature"
"Test-driven development for the shopping cart"
"Write tests first for the authentication system"
```
