---
description: "\"[Legacy] Redirects to /octo:auto — the smart router\""
disable-model-invocation: true
---

# /octo:octo → /octo:auto (Legacy Redirect)

This v10 compatibility command delegates to `/octo:auto`. It is scheduled for
removal in v11.

## EXECUTION CONTRACT (Mandatory)

When the user invokes `/octo:octo <query>`, you MUST:

1. Inform the user: "Note: `/octo:octo` has been renamed to `/octo:auto`. Routing your request now."
2. Immediately read `${HOME}/.claude-octopus/plugin/commands/auto.md` and
   execute it with the full user query. Do not use the Skill tool; Octopus
   commands are explicit-only and hidden from model invocation.
3. If the routed workflow dispatches multiple providers, surface `${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh agent-summary` before final synthesis when available.

Do NOT duplicate the routing logic here — delegate entirely to `/octo:auto`.
