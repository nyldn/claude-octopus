---
name: octopus-security-audit
aliases:
  - security
  - security-audit
description: OWASP compliance, vulnerability scanning, and penetration testing
execution_mode: enforced
pre_execution_contract:
  - visual_indicators_displayed
validation_gates:
  - orchestrate_sh_executed
  - output_artifact_exists
---

# Security Audit Skill

Invokes the security-auditor persona for thorough security analysis during the `ink` (deliver) phase.

## Usage

```bash
# Via orchestrate.sh
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh spawn security-auditor "Scan for SQL injection vulnerabilities"

# Via auto-routing (detects security intent)
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh auto "security audit the payment processing module"
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
