---
command: security
description: Security audit with OWASP compliance and vulnerability detection
---

# Security - Security Audit Skill

## 🤖 INSTRUCTIONS FOR CLAUDE

### MANDATORY COMPLIANCE — DO NOT SKIP

**When the user explicitly invokes `/octo:security`, you MUST execute the structured security audit workflow below.** You are PROHIBITED from doing a quick check directly, skipping the clarifying questions, or deciding the task is "too simple" for this workflow. The user chose this command deliberately — respect that choice.

---

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
    },
    {
      question: "How should findings be validated? Multi-LLM options use Claude + Codex + Gemini together.",
      header: "Multi-LLM Validation",
      multiSelect: false,
      options: [
        {label: "Standard audit", description: "Claude-only security analysis (no external API costs)"},
        {label: "Multi-LLM red team debate", description: "Codex plays blue team, Gemini plays red team, Claude synthesizes (recommended for high-value targets)"},
        {label: "Full Multi-LLM adversarial cycle", description: "4-phase blue→red→remediate→validate with three-model debate at each transition"},
        {label: "Multi-LLM debate on critical findings only", description: "Standard audit, then Claude + Codex + Gemini debate any critical/high severity findings"}
      ]
    }
  ]
})
```

**After receiving answers, incorporate them into the security audit scope and severity thresholds.**

### Step 2: Execute Security Audit with Skill Tool

**✓ CORRECT - Use the Skill tool:**
```
Skill(skill: "skill-security-framing", args: "<user's arguments + context>")
```

**✗ INCORRECT - Do NOT use Task tool:**
```
Task(subagent_type: "octo:security", ...)  ❌ Wrong! This is a skill, not an agent type
```

**Why:** This command loads the `skill-security-audit` skill. Skills use the `Skill` tool, not `Task`.

---

### Step 3: Debate-Enhanced Validation (if enabled)

**Based on the user's validation mode selection:**

1. **"Red team debate"**: After the initial audit produces findings, invoke:
   ```
   /octo:debate --rounds 2 --debate-style adversarial "Red team challenge: Can you exploit these defenses? Blue team: defend the implementation. Findings: [audit results]"
   ```
   One provider plays attacker, the other plays defender. Claude synthesizes.

2. **"Full adversarial cycle"**: Run the `octopus-security` (squeeze) workflow which already
   implements Blue→Red→Remediate→Validate, but add debate transitions between each phase:
   - After Blue Team: debate whether defense is sufficient
   - After Red Team: debate severity and exploitability of findings
   - After Remediation: debate whether fixes are complete
   - After Validation: final consensus on security posture

3. **"Debate critical findings only"**: After standard audit, filter findings by severity.
   For any Critical or High finding, invoke:
   ```
   /octo:debate --rounds 1 --debate-style adversarial "Is this finding exploitable in practice? [finding details + code context]"
   ```
   This eliminates false positives and confirms real risks through multi-model deliberation.

4. **Present results**: Show original audit findings annotated with debate verdicts:
   - ✅ **Confirmed** — debate agreed this is a real vulnerability
   - ⚠️ **Disputed** — models disagreed on severity or exploitability
   - ❌ **Overturned** — debate concluded this is a false positive

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
