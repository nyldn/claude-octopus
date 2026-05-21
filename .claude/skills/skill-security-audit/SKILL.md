---
name: octopus-security-audit
aliases:
  - security
  - security-audit
description: OWASP compliance, vulnerability scanning, and adversarial red team testing — use for security reviews
trigger: |
  Use this skill when the user says "security audit this code", "find vulnerabilities in X",
  "red team review", "pentest this API", or "check for OWASP issues".
execution_mode: enforced
pre_execution_contract:
  - visual_indicators_displayed
validation_gates:
  - orchestrate_sh_executed
  - output_artifact_exists
invocation: human_only
paths:
  - "**/.env*"
  - "**/auth*"
  - "**/security*"
  - "**/oauth*"
  - "Dockerfile*"
---

# Security Audit Skill

**Your first output line MUST be:** `🐙 **CLAUDE OCTOPUS ACTIVATED** - Security Audit`

Invokes the security-auditor persona for thorough security analysis during the `ink` (deliver) phase. Supports both quick OWASP scanning and full adversarial red/blue team testing.

## Usage

```bash
# Quick scan via security-auditor persona
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh spawn security-auditor "Scan for SQL injection vulnerabilities"

# Adversarial red team via squeeze workflow
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh squeeze "Security audit the authentication module"

# Via auto-routing (detects security intent)
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh auto "security audit the payment processing module"
```

## Modes (Auto-Detected)

| Mode | Auto-Trigger | Confidence Gate | Scope |
|------|-------------|----------------|-------|
| **Quick** (default) | Standard security scan, no sensitive files in diff | 8/10 — only high-confidence findings | Changed files only |
| **Deep** (auto-escalated) | Diff touches auth/security/CI files, OR explicit request | 2/10 — flag anything suspicious | Entire codebase |

**Auto-escalation to Deep mode:** The skill automatically switches to Deep mode when ANY of these are true:
- Diff includes files matching: `*auth*`, `*login*`, `*password*`, `*session*`, `*token*`, `*secret*`, `*crypt*`, `*oauth*`, `*saml*`, `*jwt*`, `*permission*`, `*rbac*`, `*acl*`
- Diff includes CI/CD files: `.github/workflows/*`, `Dockerfile*`, `docker-compose*`, `.gitlab-ci*`
- Diff includes dependency files: `package-lock.json`, `yarn.lock`, `Gemfile.lock`, `requirements.txt`, `go.sum`
- The user explicitly says "deep", "full", "comprehensive", or "CSO"

No user action needed — mode detection happens automatically from the git diff context.

## Capabilities

### Core (both modes)
- OWASP Top 10 vulnerability detection
- SQL injection and XSS scanning
- Authentication/authorization review
- Secrets and credential detection
- Dependency vulnerability assessment
- Security configuration review

### Secrets Archaeology (Deep mode)
Scan git history for leaked credentials that may have been "deleted" but remain in commits:

```bash
# Search git history for common secret patterns
git log --all -p --diff-filter=D -- '*.env' '*.key' '*.pem' 2>/dev/null | head -200
git log --all -p -S 'AKIA' --pickaxe-regex 2>/dev/null | head -100  # AWS keys
git log --all -p -S 'sk-[a-zA-Z0-9]{20,}' --pickaxe-regex 2>/dev/null | head -100  # API keys
git log --all -p -S 'ghp_|gho_|github_pat_' --pickaxe-regex 2>/dev/null | head -100  # GitHub tokens
git log --all -p -S 'password\s*[:=]' --pickaxe-regex 2>/dev/null | head -100  # Passwords
```

Report any findings with the commit SHA, file, and recommendation to rotate the credential.

### CI/CD Pipeline Security (Deep mode)
Audit GitHub Actions and CI configuration for injection and privilege escalation:

```bash
# Find all workflow files
find .github/workflows -name '*.yml' -o -name '*.yaml' 2>/dev/null

# Check for dangerous patterns:
# 1. Untrusted input in run: blocks (command injection via PR titles/branch names)
# 2. pull_request_target with checkout of PR code (code execution from forks)
# 3. Overly broad permissions (write-all, contents: write)
# 4. Missing pinned action versions (uses: actions/checkout vs actions/checkout@v4)
# 5. Secrets exposed to pull_request events (accessible to forks)
```

Flag each finding with severity (CRITICAL/HIGH/MEDIUM/LOW).

### Skill & Plugin Supply Chain (Deep mode)
Verify integrity of installed Claude Code skills and plugins:

```bash
# List installed plugins
ls -la ~/.claude/plugins/ 2>/dev/null

# Check for skills that execute arbitrary bash
grep -r 'exec\|eval\|bash -c' ~/.claude/skills/*/SKILL.md 2>/dev/null | head -20

# Verify plugin sources (are they from known registries?)
cat ~/.claude/plugins/*/plugin.json 2>/dev/null | grep -E '"source"|"registry"'
```

### STRIDE Threat Modeling (Deep mode)
For the target component, enumerate threats across all 6 STRIDE categories:

| Category | Question |
|----------|----------|
| **S**poofing | Can an attacker impersonate a user or component? |
| **T**ampering | Can data be modified in transit or at rest? |
| **R**epudiation | Can actions be denied without audit trail? |
| **I**nformation Disclosure | Can sensitive data leak through logs, errors, or side channels? |
| **D**enial of Service | Can the service be overwhelmed or starved? |
| **E**levation of Privilege | Can a low-privilege user gain admin access? |

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
"Red team review the payment API"
```

---

## Adversarial Mode (squeeze workflow)

For comprehensive security testing, use the squeeze workflow which runs a 4-phase adversarial cycle:

1. **Blue Team** (Defense): Codex reviews code, identifies attack surface, proposes defenses
2. **Red Team** (Attack): Gemini attempts to break defenses, generates exploit PoCs
3. **Remediation** (Fix): Codex patches all vulnerabilities found
4. **Validation** (Verify): Gemini re-tests, confirms fixes or fails

```bash
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh squeeze "[user's security request]"
```

### OWASP Top 10 Coverage

- Broken Access Control
- Cryptographic Failures
- Injection
- Insecure Design
- Security Misconfiguration
- Vulnerable Components
- Authentication Failures
- Software Integrity Failures
- Logging & Monitoring Failures
- Server-Side Request Forgery

### Additional Attack Patterns

- Race conditions, business logic flaws
- Denial of service, information disclosure
- Client-side attacks (XSS, CSRF)

### Advanced Options

```bash
# Focus on specific vulnerabilities
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh squeeze --principles security "Audit for auth bypass only"

# Loop until all vulnerabilities fixed
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh squeeze --loop --quality 100 "Zero tolerance audit"
```

### When to Use Adversarial Mode

| Aspect | Quick Scan (spawn) | Adversarial (squeeze) |
|--------|-------------------|----------------------|
| Speed | 1-2 min | 5-10 min |
| Depth | Single perspective | Blue + Red team |
| Output | Issue list | Exploit PoCs + fixes |
| Best for | Pre-commit checks | Pre-deployment review |

## When NOT to Use This

- Production systems (use real pentest tools)
- Compliance audits (use certified auditors)
- Legal verification (consult security lawyers)

**Do use for**: pre-commit security checks, development-phase testing, architecture security review, CI/CD security gates.
