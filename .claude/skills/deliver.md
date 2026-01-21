---
name: octo:deliver
description: |
  Deliver phase shortcut. Triggers: "validate this", "review implementation", "verify it works".
  Redirects to flow-deliver for multi-agent validation and quality assurance.
redirect: flow-deliver
trigger: |
  AUTOMATICALLY ACTIVATE when user requests validation or review:
  - "review X" or "validate Y" or "test Z"
  - "check if X works correctly"
  - "verify the implementation of Y"
  - "find issues in Z"
---

# Deliver (Shortcut) - Deliver Phase ✅

This is a shortcut alias for `/octo:flow-deliver`.

**Part of Double Diamond: DELIVER** (convergent thinking)

## What This Does

The **deliver** phase validates and reviews implementations using external CLI providers:

1. **🔴 Codex CLI** - Code quality, best practices, technical correctness
2. **🟡 Gemini CLI** - Security audit, edge cases, user experience
3. **🔵 Claude (You)** - Synthesis and final validation report

For full documentation, see `/octo:flow-deliver`.
