---
name: octo:develop
description: |
  Develop phase shortcut. Triggers: "build this", "implement X", "create feature".
  Redirects to flow-develop for multi-agent implementation with parallel solutions.
redirect: flow-develop
trigger: |
  AUTOMATICALLY ACTIVATE when user requests building or implementation:
  - "build X" or "implement Y" or "create Z"
  - "develop a feature for X"
  - "write code to do Y"
  - "add functionality for Z"
---

# Develop (Shortcut) - Develop Phase 🛠️

This is a shortcut alias for `/octo:flow-develop`.

**Part of Double Diamond: DEVELOP** (divergent thinking)

## What This Does

The **develop** phase generates multiple implementation approaches using external CLI providers:

1. **🔴 Codex CLI** - Implementation-focused, code generation, technical patterns
2. **🟡 Gemini CLI** - Alternative approaches, edge cases, best practices
3. **🔵 Claude (You)** - Integration, refinement, and final implementation

For full documentation, see `/octo:flow-develop`.
