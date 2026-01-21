---
name: octo:config
description: "Shortcut for /octo:sys-configure - Configure Claude Octopus providers and API keys"
redirect: sys-configure
trigger: |
  Use this skill when the user wants to "configure Claude Octopus", "setup octopus",
  "configure providers", or "set up API keys for octopus".
---

# Config (Shortcut) - Configure Claude Octopus 🐙

This is a shortcut alias for `/octo:sys-configure`.

🐙 **CLAUDE OCTOPUS SETUP** - Helping you configure multi-agent orchestration

## What This Does

This skill helps you configure Claude Octopus:
- Auto-detect current setup (installed CLIs, API keys, authentication)
- Guide you through provider configuration
- Set up cost optimization preferences
- Display provider status and next steps

For full documentation, see `/octo:sys-configure`.

## Quick Start

Run the status command to see what's configured:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh status
```

Then run the configuration wizard:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh octopus-configure
```
