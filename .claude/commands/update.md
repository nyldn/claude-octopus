---
command: octo:update
description: "Shortcut for /octo:sys-update - Check for updates to Claude Code and claude-octopus"
redirect: sys-update
---

# Update (Shortcut)

This is a shortcut alias for `/octo:sys-update`.

## Quick Usage

- `/octo:update` - Check for updates (shows GitHub, registry, and installed versions)
- `/octo:update --update` - Check and update if registry has synced

## What This Command Does

Checks three version sources to give you complete visibility:
- 📦 Your installed version
- 🔵 Plugin registry latest (what's available to install)
- 🐙 GitHub latest (source of truth)

If GitHub has a newer version but the registry hasn't synced yet (12-24h delay), the command will explain this and set expectations rather than showing confusing "already at latest" messages.

For full update documentation and implementation details, see `/octo:sys-update`.
