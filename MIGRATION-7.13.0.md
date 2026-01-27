# Migration Guide: v7.12.x → v7.13.0

This guide helps you upgrade Claude Octopus from v7.12.x to v7.13.0, which integrates Claude Code v2.1.16-v2.1.20 features.

## Breaking Changes

### Minimum Claude Code Version Requirement

**v7.13.0 requires Claude Code v2.1.16 or higher.**

**Check your version:**
```bash
claude --version
```

**Upgrade if needed:**
```bash
claude update
```

If you're on an older version of Claude Code, you must upgrade before installing v7.13.0.

## New Features

### 1. Task Management System (v2.1.16+)

Workflows now create and track tasks automatically:

**What's New:**
- Each workflow phase creates a task with progress tracking
- Task dependencies ensure phases run in order
- Tasks visible in Claude Code's task list (`/tasks`)

**No action required** - feature works automatically.

**Benefits:**
- Visual progress tracking for multi-phase workflows
- Better understanding of what's happening during embrace workflows
- Task history for debugging and auditing

### 2. Session Variable Tracking (v2.1.9+)

Enhanced session isolation and cost tracking:

**What's New:**
- Each workflow execution has a unique session ID
- Per-session result directories
- Provider-specific session tracking (Codex, Gemini, Claude)

**No action required** - feature works automatically.

**Benefits:**
- Better organization of workflow outputs
- Per-session cost attribution
- Clearer audit trail

### 3. MCP Dynamic Provider Detection (v2.1.0+)

Faster provider availability checks:

**What's New:**
- Uses MCP `list_changed` notifications when available
- Falls back to command-line detection automatically
- Faster workflow startup

**No action required** - feature detects MCP automatically.

**Benefits:**
- Faster pre-flight checks
- More efficient provider detection
- Better error messages

### 4. Background Agent Permissions (v2.1.19+)

User control over background AI operations:

**What's New:**
- Permission prompts before spawning background AI agents
- Shows estimated API cost before execution
- Respects autonomy mode settings

**Action required:**
- First time running a workflow in v7.13.0, you'll see a new permission prompt
- Click "Yes" to proceed with background operations
- In autonomous mode, this prompt is skipped

**Benefits:**
- Transparency about AI usage and costs
- User control over when external APIs are called
- No unexpected API charges

### 5. Hook System Enhancements (v2.1.9+)

Improved provider context injection:

**What's New:**
- Hooks can now provide `additionalContext` to Claude
- Session-aware hook execution
- Better provider routing validation

**No action required** - enhancements are automatic.

**Benefits:**
- More context-aware workflows
- Better debugging information
- Improved error handling

### 6. Modular CLAUDE.md Configuration (v2.1.20+)

Provider and workflow-specific configuration:

**What's New:**
- CLAUDE.md split into modular files
- Provider-specific configs in `config/providers/`
- Workflow methodology in `config/workflows/`

**Optional: Load specific modules with `--add-dir`:**
```bash
claude --add-dir=config/providers/codex    # Codex-specific context
claude --add-dir=config/providers/gemini   # Gemini-specific context
claude --add-dir=config/workflows          # Double Diamond methodology
```

**Benefits:**
- Reduced context pollution
- Load only what you need
- Better organized documentation

## Migration Steps

### For Existing Users

1. **Upgrade Claude Code:**
   ```bash
   claude update
   claude --version  # Verify v2.1.16 or higher
   ```

2. **Update Claude Octopus:**
   ```bash
   /plugin update claude-octopus
   ```

3. **Verify Installation:**
   ```bash
   /octo:setup
   ```

4. **Test a Simple Workflow:**
   ```bash
   octo research "test v7.13.0 features"
   ```

   You should see:
   - New task created and tracked
   - Background permission prompt (first time)
   - Session ID in banner
   - Faster provider detection

### For New Installs

Just follow the standard installation guide - all new features work out of the box.

## Troubleshooting

### "Claude Code version too old"

**Problem:** You're on Claude Code < v2.1.16

**Solution:**
```bash
claude update
```

### "Task creation failed"

**Problem:** Task Management feature not available

**Check:**
```bash
claude --version  # Must be v2.1.16+
```

### "Permission prompt appears every time"

**Problem:** Autonomy mode not saving

**Solution:**
Set autonomy mode in `/octo:setup`:
- **Supervised**: Prompt after each phase (default)
- **Semi-autonomous**: Prompt only on quality gate failures
- **Autonomous**: Never prompt

### "MCP provider detection not working"

**Problem:** MCP support unavailable

**Note:** This is expected and harmless. The plugin falls back to command-line detection automatically.

## Rollback

If you need to rollback to v7.12.1:

```bash
/plugin uninstall claude-octopus
/plugin install claude-octopus@7.12.1
```

**Warning:** You'll lose access to new features:
- Task management
- Enhanced session tracking
- Background permissions
- MCP dynamic detection

## Support

Issues? Report them at:
https://github.com/nyldn/claude-octopus/issues

Include:
- Claude Code version (`claude --version`)
- Claude Octopus version (`/plugin list`)
- Error message or unexpected behavior
- Steps to reproduce

## What's Next?

With v7.13.0, you get:
- ✅ Better visibility into workflow progress
- ✅ Clearer cost transparency
- ✅ Faster provider detection
- ✅ More control over AI operations
- ✅ Modular, maintainable configuration

Start using the new features:
```bash
/octo:embrace "build a feature with full visibility"
```

Watch for task creation, background permission prompts, and session tracking!
