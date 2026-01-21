---
command: security
description: Security audit with OWASP compliance and vulnerability detection
---

# Security - Security Audit Skill

## 🤖 INSTRUCTIONS FOR CLAUDE

When the user invokes this command (e.g., `/octo:security <arguments>`):

### Step 1: Ask Clarifying Questions

**CRITICAL: Before starting the security audit, use the AskUserQuestion tool to gather context:**

Ask 3 clarifying questions to ensure targeted security assessment:

```javascript
AskUserQuestion({
  questions: [
    {
      question: "What's the threat model for this application?",
      header: "Threat Model",
      multiSelect: false,
      options: [
        {label: "Standard web app", description: "Typical internet-facing application"},
        {label: "High-value target", description: "Handles sensitive data or finances"},
        {label: "Compliance-driven", description: "Must meet regulatory requirements"},
        {label: "API-focused", description: "Primarily API endpoints and integrations"}
      ]
    },
    {
      question: "What compliance requirements apply?",
      header: "Compliance",
      multiSelect: true,
      options: [
        {label: "None specific", description: "General security best practices"},
        {label: "OWASP Top 10", description: "Standard web security vulnerabilities"},
        {label: "GDPR/HIPAA/PCI", description: "Data protection regulations"},
        {label: "SOC2/ISO27001", description: "Enterprise security frameworks"}
      ]
    },
    {
      question: "What's your risk tolerance?",
      header: "Risk Level",
      multiSelect: false,
      options: [
        {label: "Strict/Zero-trust", description: "Maximum security, flag everything"},
        {label: "Balanced", description: "Industry-standard security posture"},
        {label: "Pragmatic", description: "Focus on high/critical issues only"},
        {label: "Development-only", description: "Non-production environment"}
      ]
    }
  ]
})
```

**After receiving answers, incorporate them into the security audit scope and severity thresholds.**

### Step 2: Execute Security Audit with Skill Tool

**✓ CORRECT - Use the Skill tool:**
```
Skill(skill: "octo:security", args: "<user's arguments + context>")
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
