---
name: skill-code-review
aliases:
  - review
  - code-review
description: |
  Expert code review with comprehensive quality assessment, security analysis, and architecture feedback.
  
  Use PROACTIVELY when user says:
  - "review this code", "code review X", "review my changes"
  - "check this PR", "review this pull request"
  - "what's wrong with this code", "find issues in X"
  - "quality check", "review for best practices"
  
  PRIORITY TRIGGERS: "octo review", "code review", "review this"
  
  DO NOT use for: debugging (use skill-debug), security-only audits (use skill-security-audit),
  quick pre-commit checks (use skill-quick-review).
context: fork
agent: Explore
execution_mode: enforced
pre_execution_contract:
  - visual_indicators_displayed
validation_gates:
  - orchestrate_sh_executed
  - review_output_exists
---

# Code Review Skill

Invokes the code-reviewer persona for thorough code analysis during the `ink` (deliver) phase.

## Usage

```bash
# Via orchestrate.sh
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh spawn code-reviewer "Review this pull request for security issues"

# Via auto-routing (detects review intent)
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh auto "review the authentication implementation"
```

## Capabilities

- AI-powered code quality analysis
- Security vulnerability detection
- Performance optimization suggestions
- Architecture and design pattern review
- Best practices enforcement

## Persona Reference

This skill wraps the `code-reviewer` persona defined in:
- `agents/personas/code-reviewer.md`
- CLI: `codex-review`
- Model: `gpt-5.2-codex`
- Phases: `ink`

## Example Prompts

```
"Review this PR for OWASP Top 10 vulnerabilities"
"Analyze the error handling in src/api/"
"Check for memory leaks in the connection pool"
"Review the test coverage for the auth module"
```
