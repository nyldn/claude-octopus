---
command: rollback
description: "Restore project state from a saved checkpoint"
skill: skill-rollback
---

# Rollback

Rollback to a known checkpoint when a change needs to be undone.

Execution guidance:
1. Delegate checkpoint operations to `skill-rollback`.
2. Support:
   - `/octo:rollback` or `/octo:rollback list` to show checkpoints
   - `/octo:rollback <tag>` to restore
3. Before restore, present what will change; after restore, summarize result and next steps.
