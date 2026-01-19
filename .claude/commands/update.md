---
command: update
description: "Shortcut for /octo:sys-update - Check for updates to Claude Code and claude-octopus"
redirect: sys-update
---

# Update (Shortcut)

This is a shortcut alias for `/octo:sys-update`.

## Quick Usage

- `/octo:update` - Check for updates only
- `/octo:update --update` - Check and update if available

Running update check...

```bash
# Check current version
grep '"version"' .claude-plugin/plugin.json | head -n 1

# Check for latest version
curl -s https://api.github.com/repos/nyldn/claude-octopus/releases/latest | grep '"tag_name"'
```

For full update documentation, see `/octo:sys-update`.
