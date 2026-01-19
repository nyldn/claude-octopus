---
command: sys-update
description: Check for updates to Claude Code and claude-octopus plugin, with auto-install and error debugging
aliases:
  - update
  - check-update
---

# 🐙 Claude Octopus Update Check & Auto-Update

Automatically check for updates to claude-octopus plugin, install updates, and debug any errors.

## Quick Usage

```bash
/octo:update              # Check for updates only
/octo:update --update     # Check and auto-install if outdated
```

---

## Implementation

### Step 1: Get Current Version

```bash
# Check if plugin is installed using claude plugin list --json
PLUGIN_INFO=$(claude plugin list --json 2>/dev/null | grep -A 20 '"id": "claude-octopus@nyldn-plugins"' | head -20)

if [ -z "$PLUGIN_INFO" ]; then
  echo "❌ Error: claude-octopus plugin is not installed"
  echo ""
  echo "To install the plugin, run:"
  echo "  /plugin marketplace add nyldn/claude-octopus"
  echo "  /plugin install claude-octopus@nyldn-plugins"
  echo ""
  echo "Or visit: https://github.com/nyldn/claude-octopus"
  exit 1
fi

# Extract version from plugin info
CURRENT_VERSION=$(echo "$PLUGIN_INFO" | grep '"version"' | head -n 1 | sed 's/.*"version": *"\([^"]*\)".*/\1/' | tr -d '",')

if [ -z "$CURRENT_VERSION" ]; then
  echo "⚠️  Warning: Could not determine installed version"
  echo "Plugin appears to be installed but version could not be read"
  CURRENT_VERSION="unknown"
fi

echo "📦 Current version: v$CURRENT_VERSION"
```

### Step 2: Check GitHub for Latest Release

```bash
echo "🔍 Checking GitHub for latest release..."

# Fetch latest release info from GitHub API
GITHUB_RESPONSE=$(curl -s -w "\n%{http_code}" https://api.github.com/repos/nyldn/claude-octopus/releases/latest 2>&1)
HTTP_CODE=$(echo "$GITHUB_RESPONSE" | tail -n 1)
GITHUB_JSON=$(echo "$GITHUB_RESPONSE" | head -n -1)
```

**Error Handling:**
```bash
if [ "$HTTP_CODE" != "200" ]; then
  echo "❌ Error: Failed to fetch latest release from GitHub"
  echo "HTTP Status Code: $HTTP_CODE"

  case $HTTP_CODE in
    000)
      echo "⚠️  Network error - check your internet connection"
      echo "Troubleshooting:"
      echo "  1. Test: curl -I https://api.github.com"
      echo "  2. Check firewall/proxy settings"
      echo "  3. Try again in a few moments"
      ;;
    403)
      echo "⚠️  GitHub API rate limit exceeded"
      echo "Troubleshooting:"
      echo "  1. Wait ~60 minutes for rate limit reset"
      echo "  2. Check: curl -s https://api.github.com/rate_limit"
      echo "  3. Or visit: https://github.com/nyldn/claude-octopus/releases"
      ;;
    404)
      echo "⚠️  Repository not found (unexpected)"
      echo "Repository: https://github.com/nyldn/claude-octopus"
      ;;
    *)
      echo "⚠️  Unexpected error"
      echo "Response: $GITHUB_JSON"
      ;;
  esac

  exit 1
fi

# Extract latest version tag
LATEST_VERSION=$(echo "$GITHUB_JSON" | grep '"tag_name"' | head -n 1 | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/' | sed 's/^v//')

if [ -z "$LATEST_VERSION" ]; then
  echo "❌ Error: Could not parse latest version from GitHub response"
  echo "Response preview:"
  echo "$GITHUB_JSON" | head -20
  exit 1
fi

echo "✅ Latest version on GitHub: v$LATEST_VERSION"
```

### Step 3: Compare Versions

```bash
if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
  echo ""
  echo "✅ You're running the latest version! (v$CURRENT_VERSION)"
  echo ""
  echo "📚 Release notes: https://github.com/nyldn/claude-octopus/releases/tag/v$CURRENT_VERSION"
  exit 0
fi

echo ""
echo "🆕 Update available!"
echo "   Current:  v$CURRENT_VERSION"
echo "   Latest:   v$LATEST_VERSION"
echo ""
```

### Step 4: Check for --update Flag

Parse command arguments to check if `--update` flag was provided.

**If --update flag is NOT present:**
```bash
echo "To update automatically, run:"
echo "  /octo:update --update"
echo ""
echo "Or update manually:"
echo "  /plugin uninstall claude-octopus"
echo "  /plugin install claude-octopus@nyldn-plugins"
echo ""
echo "📚 Changelog: https://github.com/nyldn/claude-octopus/releases/tag/v$LATEST_VERSION"
exit 0
```

**If --update flag IS present:**

### Step 5: Perform Auto-Update

```bash
echo "🚀 Starting auto-update to v$LATEST_VERSION..."
echo ""

# Step 5a: Uninstall current version
echo "1️⃣  Uninstalling current version (v$CURRENT_VERSION)..."

# Use AskUserQuestion to confirm
```

**Ask user for confirmation:**
```
Update claude-octopus from v$CURRENT_VERSION to v$LATEST_VERSION?

This will:
1. Uninstall current version
2. Update marketplace cache
3. Install latest version
4. Require Claude Code restart

Continue?
```

**If user confirms "Yes":**

```bash
echo "Proceeding with update..."
echo ""

# Track any errors
UPDATE_ERRORS=""

# Step 5b: Uninstall
echo "🗑️  Step 1/2: Uninstalling current version..."
if ! /plugin uninstall claude-octopus 2>&1; then
  UPDATE_ERRORS="$UPDATE_ERRORS\n- Failed to uninstall current version"
  echo "⚠️  Warning: Uninstall may have failed, continuing anyway..."
else
  echo "✅ Uninstalled v$CURRENT_VERSION"
fi
echo ""

# Step 5c: Install latest version
echo "📦 Step 2/2: Installing v$LATEST_VERSION..."
INSTALL_OUTPUT=$(/plugin install claude-octopus@nyldn-plugins 2>&1)
INSTALL_EXIT_CODE=$?

if [ $INSTALL_EXIT_CODE -ne 0 ]; then
  echo "❌ Error: Installation failed"
  echo ""
  echo "Error details:"
  echo "$INSTALL_OUTPUT"
  echo ""
  echo "Common Issues:"
  echo ""
  echo "1. 'Plugin has an invalid manifest file' - Check plugin.json syntax"
  echo "   - Fix: Report issue at https://github.com/nyldn/claude-octopus/issues"
  echo ""
  echo "2. 'Unrecognized key: dependencies' - Invalid schema field"
  echo "   - This was fixed in v7.5.2+"
  echo "   - Current latest: v$LATEST_VERSION"
  echo ""
  echo "3. Network/download errors"
  echo "   - Check: curl -I https://github.com/nyldn/claude-octopus"
  echo "   - Retry in a few moments"
  echo ""
  echo "4. Permission errors"
  echo "   - Check Claude Code has write access to plugin directory"
  echo "   - Path: ~/.claude/plugins/"
  echo ""
  echo "Manual installation:"
  echo "  git clone https://github.com/nyldn/claude-octopus.git ~/claude-octopus"
  echo "  /plugin install ~/claude-octopus"
  echo ""

  exit 1
fi

echo "✅ Installed v$LATEST_VERSION"
echo ""

# Step 5e: Verify installation
echo "🔍 Verifying installation..."
VERIFY_INFO=$(claude plugin list --json 2>/dev/null | grep -A 20 '"id": "claude-octopus@nyldn-plugins"' | head -20)
INSTALLED_VERSION=$(echo "$VERIFY_INFO" | grep '"version"' | head -n 1 | sed 's/.*"version": *"\([^"]*\)".*/\1/' | tr -d '",')

if [ -z "$INSTALLED_VERSION" ]; then
  echo "⚠️  Warning: Could not verify installed version"
  echo "Plugin may not be loaded yet. Please restart Claude Code."
else
  echo "✅ Verified: v$INSTALLED_VERSION installed"

  if [ "$INSTALLED_VERSION" != "$LATEST_VERSION" ]; then
    echo ""
    echo "⚠️  Warning: Installed version ($INSTALLED_VERSION) doesn't match latest ($LATEST_VERSION)"
    echo "This might happen if:"
    echo "  1. Marketplace cache is stale"
    echo "  2. Multiple versions are published"
    echo "  3. Installation is still loading"
    echo ""
    echo "Please restart Claude Code and check version again."
  fi
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "✨ Update Complete!"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "Updated: v$CURRENT_VERSION → v$LATEST_VERSION"
echo ""
echo "⚠️  IMPORTANT: Restart Claude Code to load the new version"
echo ""
echo "📚 Release notes: https://github.com/nyldn/claude-octopus/releases/tag/v$LATEST_VERSION"
echo ""

# Show any accumulated warnings
if [ -n "$UPDATE_ERRORS" ]; then
  echo "⚠️  Some warnings occurred during update:"
  echo -e "$UPDATE_ERRORS"
  echo ""
fi
```

**If user says "No":**
```bash
echo "❌ Update cancelled by user"
echo ""
echo "To update later, run:"
echo "  /octo:update --update"
exit 0
```

---

## Error Recovery

If installation fails, the command provides:

1. **Detailed error message** from installation command
2. **Common issue diagnostics:**
   - Invalid manifest errors
   - Network/download failures
   - Permission errors
   - Schema validation errors
3. **Manual installation fallback:**
   ```bash
   git clone https://github.com/nyldn/claude-octopus.git ~/claude-octopus
   /plugin install ~/claude-octopus
   ```
4. **Issue reporting:** Link to GitHub issues

---

## Debugging Steps (if errors occur)

### Network Issues
```bash
# Test GitHub API access
curl -I https://api.github.com

# Test repository access
curl -I https://github.com/nyldn/claude-octopus

# Check rate limits
curl -s https://api.github.com/rate_limit | grep remaining
```

### Marketplace Issues
```bash
# List available marketplaces
/plugin marketplace list

# Re-add marketplace (use HTTPS URL)
/plugin marketplace add https://github.com/nyldn/claude-octopus
```

### Installation Issues
```bash
# Check plugin directory permissions
ls -la ~/.claude/plugins/

# Try local installation
cd ~/Downloads
git clone https://github.com/nyldn/claude-octopus.git
/plugin install ~/Downloads/claude-octopus
```

---

## Version Compatibility

| Claude Code | Claude-Octopus | Status |
|-------------|----------------|--------|
| 2.1.12+ | 7.5.2+ | ✅ Recommended |
| 2.1.10+ | 7.4.0+ | ✅ Supported |
| 2.1.7+ | 7.0.0+ | ⚠️  Partial support |
| < 2.1.7 | Any | ❌ Not supported |

**Check your Claude Code version:**
```bash
claude --version
```

**Update Claude Code:**
```bash
npm install -g @anthropic-ai/claude-code@latest
```

---

## Success Criteria

After running `/claude-octopus:update --update`, you should see:

✅ Latest version fetched from GitHub
✅ Current version uninstalled
✅ Marketplace cache updated
✅ Latest version installed
✅ Installation verified
✅ No errors in output

**Final step:** Restart Claude Code to load the new version.
