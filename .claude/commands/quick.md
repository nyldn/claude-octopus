---
command: quick
description: Quick execution mode for ad-hoc tasks without full workflow overhead
skill: octopus-quick
---

# Quick Mode Command

Execute ad-hoc tasks without multi-AI orchestration overhead.

## Usage

```
/octo:quick "<task description>"
```

## When to Use

**Perfect for:**
- Bug fixes with known solutions
- Configuration updates
- Small refactorings
- Documentation fixes
- Dependency updates
- Typo corrections

**NOT for:**
- New features
- Architecture changes
- Security-sensitive work
- Tasks requiring research

## Examples

```
/octo:quick "fix typo in README"
/octo:quick "update Next.js to v15"
/octo:quick "remove console.log statements"
/octo:quick "add error handling to login function"
```

## What It Does

1. Directly implements the change
2. Creates atomic commit
3. Updates state
4. Generates summary

**Skips:** Research, planning, multi-AI validation

## Cost

Quick mode only uses Claude (included with Claude Code).
No external provider costs.

## When to Escalate

If the task becomes complex:
- Use `/octo:discover` for research
- Use `/octo:define` for planning
- Use `/octo:develop` for building
- Use `/octo:deliver` for validation
