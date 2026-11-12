---
description: "[advanced] Team of Teams - Decompose compound tasks across independent claude instances"
disable-model-invocation: true
---

# Parallel work packages

## MANDATORY COMPLIANCE

When the user invokes `/octo:parallel`, you MUST load and follow
`skills/flow-parallel/SKILL.md` from the verified plugin root in the current
conversation. Pass through the user's task, constraints, and supplied options.
Do not invoke this command or its skill recursively.

### EXECUTION MECHANISM

Resolve the root from the command entry that was actually loaded. Verify the
plugin manifest and native skill entry there. Read that complete `SKILL.md` as
instructions and execute its seven-step contract. Stop if the root or entry is
unavailable; do not guess a fallback checkout.

**PROHIBITED:** Simulating workers, skipping required gates, fabricating provider
or test output, discarding user changes, or claiming package commits are already
integrated into the caller's branch.

The workflow decomposes a compound task into scoped packages, reviews their
dependencies when authorized, and runs independent Claude CLI workers with the
plugin loaded explicitly. Each run owns separate state, branches, and worktrees.
Timeouts and failed prerequisites stop dependent work while preserving evidence.

Example: `/octo:parallel "Build OAuth login, permissions, and audit logging"`.
