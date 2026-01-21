---
command: security
description: Security audit with OWASP compliance and vulnerability detection
---

# Security - Security Audit Skill

## 🤖 INSTRUCTIONS FOR CLAUDE

When the user invokes this command (e.g., `/octo:security <arguments>`):

**✓ CORRECT - Use the Skill tool:**
```
Skill(skill: "octo:security", args: "<user's arguments>")
```

**✗ INCORRECT - Do NOT use Task tool:**
```
Task(subagent_type: "octo:security", ...)  ❌ Wrong! This is a skill, not an agent type
```

**Why:** This command loads the `skill-security-audit` skill. Skills use the `Skill` tool, not `Task`.

---

**Auto-loads the `skill-security-audit` skill for comprehensive security analysis.**

## Quick Usage

Just use natural language:
```
"Security audit of the authentication module"
"Check auth.ts for security vulnerabilities"
"Security review of our API endpoints"
```

## What Gets Audited

- OWASP Top 10 vulnerabilities
- Authentication and authorization flaws
- Input validation and sanitization
- SQL injection and XSS risks
- Cryptography and data protection
- Session management
- API security

## Audit Types

- **Standard Audit**: OWASP compliance check
- **Adversarial**: Red team security testing (use `/octo:debate` with adversarial mode)
- **Quick Check**: Pre-commit security scan

## Natural Language Examples

```
"Security audit of the payment processing code"
"Check for SQL injection vulnerabilities in the API"
"Comprehensive security review of user authentication"
```
