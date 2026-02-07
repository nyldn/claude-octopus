---
command: validate
description: "Run comprehensive multi-AI validation on code or project targets"
skill: skill-validate
---

# Validate

Run quality, security, and best-practices validation for a target path.

Usage:

```bash
/octo:validate <target> [--focus security|code-quality|best-practices|performance]
```

Execution guidance:
1. Delegate to `skill-validate`.
2. Ensure Codex, Gemini, and Claude perspectives are included.
3. Return prioritized findings and an explicit pass/fail recommendation.
