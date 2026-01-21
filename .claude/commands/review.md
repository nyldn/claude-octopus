---
command: review
description: Expert code review with comprehensive quality assessment and security analysis
---

# Review - Code Quality Assessment

## 🤖 INSTRUCTIONS FOR CLAUDE

When the user invokes this command (e.g., `/octo:review <arguments>`):

**✓ CORRECT - Use the Skill tool:**
```
Skill(skill: "octo:review", args: "<user's arguments>")
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
