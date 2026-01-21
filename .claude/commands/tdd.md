---
command: tdd
description: Test-driven development with red-green-refactor discipline
---

# TDD - Test-Driven Development Skill

## 🤖 INSTRUCTIONS FOR CLAUDE

When the user invokes this command (e.g., `/octo:tdd <arguments>`):

### Step 1: Ask Clarifying Questions

**CRITICAL: Before starting TDD, use the AskUserQuestion tool to gather context:**

Ask 3 clarifying questions to ensure appropriate test strategy:

```javascript
AskUserQuestion({
  questions: [
    {
      question: "What's your test coverage goal?",
      header: "Coverage",
      multiSelect: false,
      options: [
        {label: "Critical paths only", description: "Focus on business-critical flows"},
        {label: "Standard coverage ~80%", description: "Industry-standard coverage target"},
        {label: "Comprehensive >90%", description: "High coverage for safety-critical code"},
        {label: "Full mutation testing", description: "Maximum rigor with mutation tests"}
      ]
    },
    {
      question: "What test style fits this feature?",
      header: "Test Style",
      multiSelect: false,
      options: [
        {label: "Unit tests focus", description: "Isolated component testing"},
        {label: "Integration tests", description: "Module interaction testing"},
        {label: "E2E tests", description: "Full user flow testing"},
        {label: "Mix of all", description: "Test pyramid approach"}
      ]
    },
    {
      question: "What's the complexity level of this feature?",
      header: "Complexity",
      multiSelect: false,
      options: [
        {label: "Simple CRUD", description: "Basic create/read/update/delete"},
        {label: "Moderate business logic", description: "Some conditional logic and validation"},
        {label: "Complex algorithms", description: "Significant computation or logic"},
        {label: "Distributed systems", description: "Multiple services, async, eventual consistency"}
      ]
    }
  ]
})
```

**After receiving answers, incorporate them into the TDD approach and test depth.**

### Step 2: Execute TDD with Skill Tool

**✓ CORRECT - Use the Skill tool:**
```
Skill(skill: "octo:tdd", args: "<user's arguments + context>")
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
