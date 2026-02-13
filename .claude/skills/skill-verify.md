---
name: skill-verify
description: "Evidence gate: verify before claiming success"
trigger: |
  Use when about to claim work is complete, fixed, or passing.
  Auto-invoke before: commits, PRs, task completion, moving to next task.
  ALWAYS use before expressing satisfaction ("Done!", "Fixed!", "All passing!").
execution_mode: enforced
---

# STOP. READ THIS FIRST.

**You are FORBIDDEN from claiming completion without evidence.** Run orchestrate.sh preflight first.

---

## Step 1: Run preflight check (USE BASH TOOL NOW)

```bash
OCTOPUS_AGENT_TEAMS=legacy "${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh" preflight
```

## Step 2: If preflight passes

You may now claim the work is complete. Include the preflight output as evidence.

## Step 3: If preflight fails

Report the failure. Do NOT claim the work is done. Fix the issues first.

---

## The Iron Law

```
NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE
```

If you haven't run preflight in this message, you cannot claim it passes.
