---
command: setup
description: "Shortcut for /octo:sys-setup - Check Claude Octopus setup status"
redirect: sys-setup
---

# Setup (Shortcut)

This is a shortcut alias for `/octo:sys-setup`.

Running setup detection...

```bash
CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(jq -r '.plugins["octo@ayoahha-plugins"][0].installPath' ~/.claude/plugins/installed_plugins.json)}"
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh detect-providers
```

For full setup documentation, see `/octo:sys-setup`.
