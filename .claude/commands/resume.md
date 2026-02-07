---
command: resume
description: "Restore project context from prior Claude Octopus session"
skill: skill-resume
---

# Resume

Resume work from the last known project state.

Execution guidance:
1. Use the `skill-resume` workflow to restore context from persisted Octopus state.
2. If no state exists, explain that there is nothing to resume and suggest `/octo:embrace` or `/octo:discover`.
3. After restoration, provide:
   - Current phase
   - Open blockers/issues
   - Suggested immediate next action
