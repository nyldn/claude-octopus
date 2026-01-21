---
command: octo:develop
description: "Development phase - Build solutions with multi-AI implementation and quality gates"
aliases:
  - tangle
  - build-phase
---

# Develop - Development Phase 🛠️

**Part of Double Diamond: DEVELOP** (divergent thinking)

Build and implement solutions using external CLI providers.

## Usage

```bash
/octo:develop        # Development phase
```

## Natural Language Examples

Just describe what you want to build:

```
"Build a user authentication system"
"Implement OAuth 2.0 flow"
"Create a caching layer for the API"
"Develop a real-time notification feature"
```

## What This Phase Does

The **develop** phase generates multiple implementation approaches using external CLI providers:

1. **🔴 Codex CLI** - Implementation-focused, code generation, technical patterns
2. **🟡 Gemini CLI** - Alternative approaches, edge cases, best practices
3. **🔵 Claude (You)** - Integration, refinement, and final implementation

This is the **divergent** phase for solutions - we explore different implementation paths before converging on the best approach.

## Quality Gates

The develop phase includes automatic quality validation:
- **75% consensus threshold** - Implementation must meet quality standards
- **Security checks** - OWASP compliance verification
- **Best practices** - Framework and language conventions
- **Performance** - Efficiency and scalability considerations

If quality gates fail, you'll be notified and can iterate.

## When to Use Develop

Use develop when you need:
- **Building**: "Build X" or "Implement Y"
- **Creating**: "Create Z feature"
- **Development**: "Develop a feature for X"
- **Code Generation**: "Write code to do Y"
- **Implementation**: "Add functionality for Z"

**Don't use develop for:**
- Simple code edits (use Edit tool)
- Reading or reviewing code (use Read/review skills)
- Trivial single-file changes

## Part of the Full Workflow

Develop is phase 3 of 4 in the embrace (full) workflow:
1. Discover
2. Define
3. **Develop** ← You are here
4. Deliver

To run all 4 phases: `/octo:embrace`
