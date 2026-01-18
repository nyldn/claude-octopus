---
name: sys-update
description: Check for updates to Claude Code and claude-octopus plugin, with optional auto-update
aliases:
  - update
  - check-update
---

# 🐙 Update Check & Auto-Update

Check for updates to both Claude Code and claude-octopus plugin. Optionally update claude-octopus automatically.

## Quick Usage

- `/co:update` - Check for updates only
- `/co:update --update` - Check and update if available

## Steps

### Part 1: Check & Update claude-octopus Plugin

1. **Check current claude-octopus version:**
```bash
grep '"version"' .claude-plugin/plugin.json | head -n 1
```

2. **Check for latest version on GitHub:**
```bash
curl -s https://api.github.com/repos/nyldn/claude-octopus/releases/latest | grep '"tag_name"'
```

3. **Compare versions and show update status:**
   - If versions match: "✅ Claude Octopus is up to date (vX.Y.Z)"
   - If update available: "🆕 Update available: vX.Y.Z → vA.B.C"

4. **If update available AND user requested `--update`:**

   Ask user: "Update claude-octopus from vX.Y.Z to vA.B.C?"

   If yes, execute:
   ```bash
   # Reinstall to latest version
   claude plugin uninstall claude-octopus
   claude plugin marketplace update nyldn-plugins
   claude plugin install claude-octopus@nyldn-plugins
   ```

   Then inform: "✅ Updated to vA.B.C. Please restart Claude Code to load the new version."

5. **If update available but user did NOT request `--update`:**

   Show update instructions:
   ```
   🆕 Update available: vX.Y.Z → vA.B.C

   To update, run:
   /co:update --update

   Or update manually:
   /plugin uninstall claude-octopus
   /plugin marketplace update nyldn-plugins
   /plugin install claude-octopus@nyldn-plugins
   ```

### Part 2: Check Claude Code Updates

6. **Check current Claude Code version:**
```bash
claude --version
```

7. **Check for available updates:**
```bash
npm view @anthropic-ai/claude-code version
```

8. **Review changelog for relevant features:**
   - Open: https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md
   - Focus on: hooks, skills, agents, MCP tools, parallel execution, CLI changes

9. **Key features to monitor for claude-octopus:**
   - **Hooks** - PreToolUse/PostToolUse/Stop for phase validation
   - **Skills** - Hot reload, nested discovery, context forking
   - **Agents** - Model selection fixes, background task controls
   - **Environment Variables** - Session ID, temp directory, task controls
   - **Parallel Execution** - Bug fixes affecting fan-out/tangle phases

10. **Update checklist:**
   - [ ] Check if new env vars benefit orchestrate.sh
   - [ ] Review hook enhancements for quality gates
   - [ ] Assess MCP/tool changes for agent coordination
   - [ ] Test parallel execution improvements

## Version Compatibility Matrix

| Claude Code | Claude-Octopus | Notes |
|-------------|----------------|-------|
| 2.1.9+ | 4.5.0+ | Full compatibility, session ID support |
| 2.1.7+ | 4.5.0+ | MCP auto-mode, keyboard shortcuts |
| 2.1.0+ | 4.0.0+ | Hooks in frontmatter, hot reload |
| 2.0.x | 3.x | Legacy mode |

## Example Output

### Check Only (no `--update` flag)

```
🐙 CLAUDE OCTOPUS UPDATE CHECK

Claude Octopus:
  Current: v7.4.0
  Latest:  v7.5.0
  Status:  🆕 Update available

  To update automatically:
  /co:update --update

Claude Code:
  Current: 2.1.10
  Latest:  2.1.11
  Status:  Update available (run: npm install -g @anthropic-ai/claude-code)
```

### Auto-Update (with `--update` flag)

```
🐙 CLAUDE OCTOPUS UPDATE CHECK

Claude Octopus:
  Current: v7.4.0
  Latest:  v7.5.0
  Status:  🆕 Update available

Updating claude-octopus...
✅ Uninstalled claude-octopus
✅ Updated marketplace
✅ Installed claude-octopus@nyldn-plugins v7.5.0

🎉 Successfully updated to v7.5.0!
⚠️  Please restart Claude Code to load the new version.

Claude Code:
  Current: 2.1.10
  Latest:  2.1.11
  Status:  Update available (run: npm install -g @anthropic-ai/claude-code)
```

## Schedule

Run this check:
- Weekly for claude-octopus updates (automated check available)
- After major Claude Code releases (2.x.0)
- Monthly for patch releases
- When users report compatibility issues

**Pro tip**: Add `--update` flag to automatically update claude-octopus when available.
