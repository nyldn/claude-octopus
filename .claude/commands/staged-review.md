---
command: staged-review
description: "Two-stage review: spec compliance then code quality"
aliases:
  - two-stage-review
  - full-review
---

# Staged Review — Two-Stage Pipeline

## INSTRUCTIONS FOR CLAUDE

When the user invokes this command (e.g., `/octo:staged-review`):

1. **Load the staged-review skill** — Read and execute `skill-staged-review.md`
2. **Run Stage 1** (Spec Compliance) — Validate against intent contract
3. **Gate check** — Stage 1 must pass before Stage 2
4. **Run Stage 2** (Code Quality) — Stub detection + quality review
5. **Present combined report** — Unified verdict

If invoked with arguments (e.g., `/octo:staged-review src/auth/`), scope the review
to the specified path.

## Related Commands

- `/octo:review` — Quick single-pass code review
- `/octo:verify` — Evidence-based verification before completion claims
- `/octo:ship` — Full delivery pipeline with security audit
