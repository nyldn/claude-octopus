---
command: sys-update
description: Check for updates to claude-octopus plugin
aliases:
  - update
  - check-update
---

# 🐙 Claude Octopus Update Check

Check for updates to the claude-octopus plugin and optionally auto-update.

## Usage

```
/octo:update              # Check for updates only
/octo:update --update     # Check and auto-install if available
```

---

## How To Implement This Command

When the user runs `/octo:update`, follow these steps:

### Step 1: Get Latest Version from GitHub

```bash
curl -s https://api.github.com/repos/nyldn/claude-octopus/releases/latest | grep '"tag_name"'
```

This returns the latest release version (e.g., `"tag_name": "v7.7.3"`).

### Step 2: Get Installed Version

The installed version is in this plugin's own `plugin.json` file. Since you're running FROM this plugin, check:

```bash
# The plugin root is where this command file lives
# Go up from .claude/commands/ to the plugin root
cat ${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json | grep '"version"'
```

If `CLAUDE_PLUGIN_ROOT` is not set, the plugin is likely at one of:
- The marketplace install location (managed by Claude Code)
- `~/.config/claude/plugins/claude-octopus/` (legacy local install)

**IMPORTANT**: If you find BOTH locations have the plugin installed, warn the user:
```
⚠️  Multiple installations detected!
   - Marketplace: [version]
   - Local: ~/.config/claude/plugins/claude-octopus/ [version]
   
Please remove the local installation:
   rm -rf ~/.config/claude/plugins/claude-octopus
```

### Step 3: Compare Versions

- If versions match: "✅ You're on the latest version (vX.X.X)"
- If outdated: Show update available message

### Step 4: If `--update` Flag Present

Provide instructions to update:

```
To update, run these commands:

/plugin uninstall claude-octopus
/plugin install claude-octopus@nyldn-plugins

Then restart Claude Code.
```

**DO NOT** use `/plugin marketplace update` - it doesn't work reliably.

---

## Output Format

### When Up-to-Date

```
🐙 Claude Octopus Update Check
==============================

📦 Installed version: v7.7.3
✅ Latest version:    v7.7.3

You're running the latest version!

📚 Release notes: https://github.com/nyldn/claude-octopus/releases/tag/v7.7.3
```

### When Update Available

```
🐙 Claude Octopus Update Check
==============================

📦 Installed version: v7.7.2
🆕 Latest version:    v7.7.3

Update available!

To update, run:
  /plugin uninstall claude-octopus
  /plugin install claude-octopus@nyldn-plugins

Then restart Claude Code.

📚 What's new: https://github.com/nyldn/claude-octopus/releases/tag/v7.7.3
```

### When Multiple Installations Detected

```
🐙 Claude Octopus Update Check
==============================

⚠️  WARNING: Multiple installations detected!

Found plugin at:
  1. Marketplace installation (v7.7.3) ✅
  2. ~/.config/claude/plugins/claude-octopus/ (v7.5.3) ⚠️ STALE

Please remove the stale local installation:
  rm -rf ~/.config/claude/plugins/claude-octopus

Then restart Claude Code.
```

---

## Error Handling

### Network Error
```
❌ Could not reach GitHub API
   Check your internet connection and try again.
```

### Plugin Not Installed
```
❌ claude-octopus plugin not found

To install:
  /plugin marketplace add https://github.com/nyldn/claude-octopus
  /plugin install claude-octopus@nyldn-plugins
```

---

## Key Points for Implementation

1. **Use GitHub API** to get latest version - this is reliable
2. **Check for duplicate installations** - warn if found
3. **Don't use marketplace update** - it doesn't work
4. **Keep it simple** - just check version and show instructions
5. **Always suggest restart** after update
