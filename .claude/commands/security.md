---
command: security
description: Security audit with OWASP compliance and vulnerability detection
---

# Security - Security Audit

## INSTRUCTIONS FOR CLAUDE

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

**After receiving answers, incorporate them into the audit prompt.**

### Step 2: Display Banner

Output this text to the user before executing:

```
🐙 CLAUDE OCTOPUS ACTIVATED - Security audit mode
🔐 Audit: <brief description of target>

Providers:
🔴 Codex CLI - Vulnerability scanning
🟡 Gemini CLI - OWASP compliance check
🔵 Claude - Risk synthesis
```

### Step 3: Execute orchestrate.sh (USE BASH TOOL NOW)

**CRITICAL: You MUST execute this bash command. Do NOT skip it.**

```bash
OCTOPUS_AGENT_TEAMS=legacy "${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh" auto "security audit <user's audit target>"
```

**WAIT for completion. Do NOT proceed until it finishes.**

If it fails, show the error. Do NOT fall back to direct security analysis.

### Step 4: Read Results

```bash
RESULT_FILE=$(find ~/.claude-octopus/results -name "squeeze-*.md" 2>/dev/null | sort -r | head -n1)
if [[ -z "$RESULT_FILE" ]]; then
  echo "ERROR: No result file found"
  ls -lt ~/.claude-octopus/results/ 2>/dev/null | head -5
else
  echo "OK: $RESULT_FILE"
  cat "$RESULT_FILE"
fi
```

### Step 5: Present Results

Read the result file content and present it to the user with this footer:

```
---
Multi-AI Security Audit powered by Claude Octopus
Providers: 🔴 Codex | 🟡 Gemini | 🔵 Claude
Full report: <path to result file>
```

## PROHIBITIONS

- Do NOT audit security yourself without orchestrate.sh
- Do NOT use Skill tool or Task tool as substitute
- Do NOT use `Task(octo:personas:security-auditor)` or any Task agent
- If orchestrate.sh fails, tell the user - do NOT work around it

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

## Natural Language Examples

```
"Security audit of the payment processing code"
"Check for SQL injection vulnerabilities in the API"
"Comprehensive security review of user authentication"
```
