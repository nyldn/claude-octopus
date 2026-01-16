---
name: octopus-security-audit
description: |
  Comprehensive security auditing skill leveraging the security-auditor persona.
  Use for vulnerability scanning, OWASP compliance checks, and security reviews.
---

# Security Audit Skill

Invokes the security-auditor persona for thorough security analysis during the `ink` (deliver) phase.

## Usage

```bash
# Via orchestrate.sh
./scripts/orchestrate.sh spawn security-auditor "Scan for SQL injection vulnerabilities"

# Via auto-routing (detects security intent)
./scripts/orchestrate.sh auto "security audit the payment processing module"
```

## Capabilities

- OWASP Top 10 vulnerability detection
- SQL injection and XSS scanning
- Authentication/authorization review
- Secrets and credential detection
- Dependency vulnerability assessment
- Security configuration review

## Persona Reference

This skill wraps the `security-auditor` persona defined in:
- `agents/personas/security-auditor.md`
- CLI: `codex-review`
- Model: `gpt-5.2-codex`
- Phases: `ink`
- Expertise: `owasp`, `vulnerability-scanning`, `security-review`

## Example Prompts

```
"Scan for hardcoded credentials in the codebase"
"Check for CSRF vulnerabilities in form handlers"
"Review the API authentication implementation"
"Analyze the encryption at rest configuration"
```
