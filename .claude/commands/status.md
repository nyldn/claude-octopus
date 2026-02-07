---
command: status
description: "Show Claude Octopus workflow and provider status"
skill: skill-status
---

# Status

Display current Claude Octopus state, active agents, and provider readiness.

Run:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh status
```

Then summarize:
- Current mode (dev/knowledge/auto)
- Provider readiness
- Active agents and results availability
- Recommended next command
