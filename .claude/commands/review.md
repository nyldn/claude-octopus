---
command: review
description: Expert code review with comprehensive quality assessment and security analysis
---

# Review - Code Quality Assessment

## 🤖 INSTRUCTIONS FOR CLAUDE

When the user invokes this command (e.g., `/octo:review <arguments>`):

### Step 1: Ask Clarifying Questions

**CRITICAL: Before starting the review, use the AskUserQuestion tool to gather context:**

Ask 3 clarifying questions to ensure focused review:

```javascript
AskUserQuestion({
  questions: [
    {
      question: "What's the primary goal of this review?",
      header: "Goal",
      multiSelect: false,
      options: [
        {label: "Pre-commit check", description: "Quick review before committing"},
        {label: "Security focus", description: "Deep security vulnerability analysis"},
        {label: "Performance optimization", description: "Identify bottlenecks and improvements"},
        {label: "Architecture assessment", description: "Design patterns and structure review"}
      ]
    },
    {
      question: "What are your priority concerns?",
      header: "Priority",
      multiSelect: true,
      options: [
        {label: "Security vulnerabilities", description: "OWASP, authentication, data protection"},
        {label: "Performance issues", description: "Speed, efficiency, scalability"},
        {label: "Code maintainability", description: "Readability, complexity, structure"},
        {label: "Test coverage", description: "Testing adequacy and quality"}
      ]
    },
    {
      question: "Who is the audience for this review?",
      header: "Audience",
      multiSelect: false,
      options: [
        {label: "Just me", description: "Personal learning and improvement"},
        {label: "Team review", description: "Preparing for team code review"},
        {label: "Production release", description: "Pre-deployment quality gate"},
        {label: "External audit", description: "Client or compliance review"}
      ]
    }
  ]
})
```

**After receiving answers, incorporate them into the review focus and depth.**

### Step 2: Execute Review with Skill Tool

**✓ CORRECT - Use the Skill tool:**
```
Skill(skill: "octo:review", args: "<user's arguments + context>")
```

**✗ INCORRECT - Do NOT use Task tool:**
```
Task(subagent_type: "octo:review", ...)  ❌ Wrong! This is a skill, not an agent type
```

**Why:** This command loads the `skill-code-review` skill. Skills use the `Skill` tool, not `Task`.

---

**Auto-loads the `skill-code-review` skill for comprehensive code review.**

## Quick Usage

Just use natural language:
```
"Review my authentication code for security issues"
"Code review the API endpoints in src/api/"
"Review this PR for quality and performance"
```

## What Gets Reviewed

- Code quality and style
- Security vulnerabilities (OWASP Top 10)
- Performance issues and optimizations
- Architecture and design patterns
- Test coverage and quality
- Error handling and edge cases

## Review Types

- **Quick Review**: Pre-commit checks (use `/octo:quick-review` or just say "quick review")
- **Full Review**: Comprehensive analysis with security audit
- **Security Focus**: Deep security and vulnerability assessment

## Natural Language Examples

```
"Review the auth module for security vulnerabilities"
"Quick review of my changes before I commit"
"Comprehensive code review of the payment processing code"
```

The skill will automatically analyze your code and provide detailed feedback with specific recommendations.
