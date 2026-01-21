---
command: octo:sys-update
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

### Step 1: Get Latest Version from GitHub (Source of Truth)

```bash
# Get latest release info from GitHub API
GITHUB_RELEASE=$(curl -s https://api.github.com/repos/nyldn/claude-octopus/releases/latest)
GITHUB_VERSION=$(echo "$GITHUB_RELEASE" | grep '"tag_name"' | cut -d '"' -f 4)
RELEASE_DATE=$(echo "$GITHUB_RELEASE" | grep '"published_at"' | cut -d '"' -f 4)

# Calculate how long ago the release was published (for sync delay estimation)
# This helps explain to users why registry might not have synced yet
```

### Step 2: Get Installed Version

Find the plugin installation location. Check these paths in order:

```bash
# Method 1: Use CLAUDE_PLUGIN_ROOT if available
if [ -n "$CLAUDE_PLUGIN_ROOT" ]; then
    INSTALLED_VERSION=$(grep '"version"' "$CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json" | head -n 1 | cut -d '"' -f 4)
    INSTALL_LOCATION="$CLAUDE_PLUGIN_ROOT"
fi

# Method 2: Check marketplace cache (user scope)
MARKETPLACE_PATH="$HOME/.claude/plugins/cache/nyldn-plugins/claude-octopus"
if [ -d "$MARKETPLACE_PATH" ]; then
    # Find latest version in cache
    LATEST_CACHED=$(ls -t "$MARKETPLACE_PATH" | head -n 1)
    if [ -n "$LATEST_CACHED" ]; then
        INSTALLED_VERSION=$(grep '"version"' "$MARKETPLACE_PATH/$LATEST_CACHED/.claude-plugin/plugin.json" | head -n 1 | cut -d '"' -f 4)
        INSTALL_LOCATION="$MARKETPLACE_PATH/$LATEST_CACHED (user scope)"
    fi
fi

# Method 3: Check legacy local install
LEGACY_PATH="$HOME/.config/claude/plugins/claude-octopus"
if [ -d "$LEGACY_PATH" ]; then
    LEGACY_VERSION=$(grep '"version"' "$LEGACY_PATH/.claude-plugin/plugin.json" 2>/dev/null | head -n 1 | cut -d '"' -f 4)
    if [ -n "$LEGACY_VERSION" ]; then
        echo "⚠️  WARNING: Legacy installation found at $LEGACY_PATH"
        echo "   Please remove it: rm -rf $LEGACY_PATH"
    fi
fi
```

### Step 3: Check Registry Version (What the Plugin System Thinks is Latest)

This is NEW and critical for detecting sync delays:

```bash
# Try to get what version the registry thinks is latest
# We do this by running a dry-run update check
REGISTRY_CHECK=$(claude plugin update claude-octopus@nyldn-plugins 2>&1)

# The output will say either:
# - "already at the latest version (X.X.X)" - extract that version
# - "Updated to X.X.X" - that's the registry version
# Parse the version from the output
```

### Step 4: Compare All Three Versions

This is the key improvement - compare GitHub, installed, AND registry:

```bash
# Scenario A: Everything matches - user is truly up-to-date
if [ "$INSTALLED_VERSION" = "$GITHUB_VERSION" ]; then
    echo "✅ You're running the latest version ($GITHUB_VERSION)"

# Scenario B: GitHub ahead of installed, but registry has synced
elif [ "$REGISTRY_VERSION" = "$GITHUB_VERSION" ] && [ "$INSTALLED_VERSION" != "$GITHUB_VERSION" ]; then
    echo "🆕 Update available in registry: $GITHUB_VERSION"
    echo "   Your version: $INSTALLED_VERSION"
    if [ "$AUTO_UPDATE" = "true" ]; then
        # Safe to use standard update
        echo "   Updating via registry..."
    fi

# Scenario C: GitHub ahead of both installed AND registry (SYNC DELAY)
elif [ "$GITHUB_VERSION" != "$REGISTRY_VERSION" ]; then
    echo "⚠️  Version Sync Status"
    echo ""
    echo "   📦 Your version:     $INSTALLED_VERSION"
    echo "   🔵 Registry latest:  $REGISTRY_VERSION"
    echo "   🐙 GitHub latest:    $GITHUB_VERSION (released $HOURS_AGO hours ago)"
    echo ""
    echo "   A newer version exists on GitHub but hasn't propagated to the"
    echo "   plugin registry yet. Registry sync typically takes 12-24 hours."
    echo ""
    if [ "$AUTO_UPDATE" = "true" ]; then
        echo "   Options:"
        echo "   1. Wait for registry sync (recommended) - check back in 12-24h"
        echo "   2. Manual install from GitHub (advanced):"
        echo "      • View release notes: https://github.com/nyldn/claude-octopus/releases/tag/$GITHUB_VERSION"
        echo "      • When ready to update, the registry should be synced"
    else
        echo "   Run /octo:update again in 12-24 hours when registry has synced."
        echo "   📚 View what's new: https://github.com/nyldn/claude-octopus/releases/tag/$GITHUB_VERSION"
    fi
fi
```

### Step 5: If `--update` Flag Present

Only attempt auto-update when registry has synced:

```bash
if [ "$AUTO_UPDATE" = "true" ]; then
    if [ "$REGISTRY_VERSION" = "$GITHUB_VERSION" ]; then
        # Safe to update - registry has the latest
        echo "🔄 Updating to $GITHUB_VERSION..."
        claude plugin update claude-octopus@nyldn-plugins
        echo "✅ Update complete! Please restart Claude Code."
    else
        # Registry hasn't synced - don't attempt update
        echo "❌ Cannot auto-update: Registry has not synced with GitHub yet."
        echo "   Please wait 12-24 hours and try again."
    fi
fi
```

**Key Changes:**
- Check THREE sources: GitHub (truth), installed (current), registry (available)
- Detect and explain sync delays explicitly
- Only auto-update when registry has synced
- Provide clear timeline expectations (12-24 hours)

---

## Output Format

### Scenario A: Up-to-Date (All Versions Match)

```
🐙 Claude Octopus Update Check
==============================

📦 Your version:     v7.9.0
🔵 Registry latest:  v7.9.0
🐙 GitHub latest:    v7.9.0

✅ You're running the latest version!

📚 Release notes: https://github.com/nyldn/claude-octopus/releases/tag/v7.9.0
```

### Scenario B: Update Available (Registry Synced)

```
🐙 Claude Octopus Update Check
==============================

📦 Your version:     v7.8.15
🔵 Registry latest:  v7.9.0
🐙 GitHub latest:    v7.9.0

🆕 Update available!

To update, run:
  /octo:update --update

📚 What's new: https://github.com/nyldn/claude-octopus/releases/tag/v7.9.0
```

### Scenario C: Registry Sync Pending (THE FIX FOR YOUR ISSUE)

This is the new behavior that solves the confusion when GitHub has a release but the registry hasn't synced:

```
🐙 Claude Octopus Update Check
==============================

📦 Your version:     v7.8.15
🔵 Registry latest:  v7.8.15 (matches your version)
🐙 GitHub latest:    v7.9.0 (released 6 hours ago)

⚠️  Registry Sync Pending

A newer version (v7.9.0) exists on GitHub but hasn't propagated
to the plugin registry yet. Registry sync typically takes 12-24 hours.

Estimated sync completion: 6-18 hours from now

Options:
  • Wait for registry sync (recommended), then run: /octo:update --update
  • View release notes now: https://github.com/nyldn/claude-octopus/releases/tag/v7.9.0

Check back later with: /octo:update
```

### Scenario D: Auto-Update with Sync Pending

When user runs `/octo:update --update` but registry hasn't synced:

```
🐙 Claude Octopus Update Check
==============================

📦 Your version:     v7.8.15
🔵 Registry latest:  v7.8.15
🐙 GitHub latest:    v7.9.0 (released 6 hours ago)

❌ Cannot auto-update: Registry has not synced with GitHub yet.

The plugin registry is aware of v7.8.15 as the latest version.
GitHub shows v7.9.0 was released 6 hours ago.

Typical registry sync time: 12-24 hours
Estimated availability: 6-18 hours from now

Please check back later with: /octo:update --update

📚 Preview what's coming: https://github.com/nyldn/claude-octopus/releases/tag/v7.9.0
```

### Scenario E: Successful Auto-Update

When registry has synced and update proceeds:

```
🐙 Claude Octopus Update Check
==============================

📦 Your version:     v7.8.15
🔵 Registry latest:  v7.9.0
🐙 GitHub latest:    v7.9.0

🔄 Updating to v7.9.0...

Checking for updates for plugin "claude-octopus@nyldn-plugins"…
✔ Updated claude-octopus to v7.9.0

✅ Update complete! Please restart Claude Code to apply changes.

📚 What's new: https://github.com/nyldn/claude-octopus/releases/tag/v7.9.0
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

1. **Check THREE sources** - GitHub (truth), installed (current), registry (available)
2. **Detect sync delays** - when GitHub > registry, explain the timing
3. **Never say "already at latest"** when GitHub has a newer version
4. **Provide clear timelines** - "12-24 hours", "released 6 hours ago"
5. **Only auto-update when safe** - registry must match GitHub
6. **Always provide release notes link** - let users see what's new
7. **Check for duplicate installations** - warn if found
8. **Always suggest restart** after successful update

## Why This Matters

**The Problem We're Solving:**
- User sees: "Update available! v7.9.0"
- Then sees: "Already at latest version (7.8.15)"
- Result: Confusion, distrust, frustration

**The Solution:**
- Show all three versions transparently
- Explain WHY there's a discrepancy (registry sync delay)
- Set clear expectations (12-24 hours)
- Provide actionable next steps

**Research Findings:**
- Chrome extensions: up to 48h propagation time
- npm: 5-15 minutes for metadata, longer for CDN
- VSCode: hours for marketplace sync
- Users handle nuance better than contradiction
