---
command: standard-mode
disable-model-invocation: true
description: Switch Octopus model routing to the configured standard tier
allowed-tools: Bash
---

# Standard Cost Mode

**Your first output line MUST be:** `🐙 Octopus Cost Mode: Standard`

This v10 compatibility command selects the Standard option from
`/octo:model-config`. It is scheduled for removal in v11.

Run this command with the Bash tool:

```bash
OCTO_ROOT="${CLAUDE_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}"
helper="$OCTO_ROOT/scripts/helpers/octo-model-config.sh"
if [[ ! -x "$helper" ]]; then
  echo "ERROR: Claude Octopus model-config helper is unavailable. Run /octo:setup." >&2
  exit 1
fi
"$helper" cost-mode standard &&
  "$helper" cost-mode status
```

Report the helper output exactly. The selection persists in
`~/.claude-octopus/config/providers.json`; do not edit the user's shell profile.
