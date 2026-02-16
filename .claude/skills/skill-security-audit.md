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

---

## EXECUTION CONTRACT (MANDATORY - BLOCKING)

**You are PROHIBITED from proceeding without completing these steps in order.**

### STEP 1: Provider Detection (BLOCKING)

Use the Bash tool to execute:
```bash
command -v codex && echo "CODEX_AVAILABLE" || echo "CODEX_UNAVAILABLE"
command -v gemini && echo "GEMINI_AVAILABLE" || echo "GEMINI_UNAVAILABLE"
```

**You MUST use the Bash tool for this check.** Do NOT assume provider availability.

### STEP 2: Visual Indicators (BLOCKING)

Display the provider banner. DO NOT PROCEED without displaying it.

```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Security Audit mode
🔒 Audit: [Brief description of target being audited]

Providers:
🔴 Codex CLI - Vulnerability pattern detection
🟡 Gemini CLI - OWASP compliance and ecosystem review
🔵 Claude - Threat modeling and synthesis
```

### STEP 3: Execute orchestrate.sh via Bash tool (MANDATORY)

**You MUST use the Bash tool to invoke orchestrate.sh:**

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh spawn security-auditor "<user's security audit request>"
```

❌ You CANNOT audit code directly without this Bash call
❌ You CANNOT use Task/Explore agents as substitute for orchestrate.sh
❌ You CANNOT claim you are "simulating" the workflow
❌ You CANNOT skip to presenting results without orchestrate.sh execution

**This is NOT optional. You MUST use the Bash tool to invoke orchestrate.sh.**

### STEP 4: Verify Execution (VALIDATION GATE)

Use the Bash tool to verify orchestrate.sh completed:
```bash
if [ $? -ne 0 ]; then
  echo "❌ VALIDATION FAILED: orchestrate.sh spawn security-auditor failed"
  exit 1
fi
echo "✅ VALIDATION PASSED: Security audit completed via orchestrate.sh"
```

If validation fails, STOP and report the error. Do NOT substitute with direct analysis.
