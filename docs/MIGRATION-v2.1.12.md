# Migration Guide: Claude Code v2.1.12+ Integration

## Overview

Claude Octopus v7.12.0 integrates with Claude Code v2.1.12+ features for enhanced task management, fork context isolation, and improved workflow orchestration. This guide explains the new features and migration path.

## What's New in v7.12.0

### 1. Native Task Management (Claude Code v2.1.16+)

Workflows now create trackable tasks with dependency chains:

```
Discover Task → Define Task → Develop Task → Deliver Task
```

**Benefits:**
- See progress across workflow phases
- Resume interrupted workflows
- Automatic checkpoint creation
- Task dependency tracking

**Example:**
```bash
/octo:embrace "Build user authentication"
# Creates 4 linked tasks automatically
# View progress: Tasks: 2 in progress, 1 completed, 1 pending
```

### 2. Fork Context Isolation (Claude Code v2.1.16+)

Heavy workflows run in isolated fork contexts to prevent conversation bloat:

**Benefits:**
- Memory-efficient execution
- Prevents context mixing
- Parallel workflow execution
- Better resource management

**Affected skills:**
- `flow-discover` - Research operations in fork context
- `flow-define` - Scoping operations in fork context
- `flow-develop` - Implementation in fork context
- `flow-deliver` - Validation in fork context

### 3. Agent Field Specification

Skills now explicitly declare which agent type to use:

```yaml
# In skill frontmatter
agent: Explore      # Research and discovery
agent: Plan         # Scoping and requirements
agent: general-purpose # Implementation
```

**Benefits:**
- Explicit provider control
- Clearer execution intent
- Better routing decisions

### 4. Enhanced Hook System

New middleware hooks for validation:

- **TaskCreate hook** - Validates task dependencies before creation
- **TaskUpdate hook** - Creates checkpoints on task completion
- **Provider routing hook** - Validates CLI availability

**Benefits:**
- Automatic task dependency validation
- Session resumption support
- Better error messages for missing providers

### 5. Wildcard Bash Permissions

Flexible CLI command patterns:

```bash
# Old: Exact pattern matching
Bash(codex exec "prompt")

# New: Wildcard patterns
Bash(codex *)          # Any codex command
Bash(gemini *)         # Any gemini command
Bash(*/orchestrate.sh *) # Any orchestrate.sh call
```

**Benefits:**
- More flexible permissions
- Less friction for CLI execution
- Better developer experience

---

## Do I Need to Upgrade?

**No!** The plugin automatically detects your Claude Code version and uses appropriate features.

### Feature Matrix

| Claude Code Version | Available Features |
|---------------------|-------------------|
| **< v2.1.12** | Legacy mode (tmux-based async) |
| **v2.1.12 - v2.1.15** | Task management, bash wildcards |
| **v2.1.16+** | All features (fork context, agent fields) |

---

## How to Upgrade

### Step 1: Update Claude Code

Update to the latest version of Claude Code:

```bash
# Via npm (if installed that way)
npm install -g @anthropic/claude-code@latest

# Or download from official site
# https://claude.ai/download
```

Verify version:
```bash
claude --version
# Should show v2.1.16 or higher for full feature set
```

### Step 2: Update Claude Octopus Plugin

The plugin auto-updates by default. To manually update:

```bash
# From within Claude Code
/octo:sys-setup
# Select "Check for updates"

# Or use Claude CLI
claude plugin update nyldn-plugins/claude-octopus
```

### Step 3: Restart Claude Code

Close and restart Claude Code to load the new plugin version.

### Step 4: Verify Installation

Run the test suite to verify everything works:

```bash
./tests/test-v2.1.12-integration.sh
```

You should see:
```
✓ All tests passed!
```

---

## What Stays the Same

### ✅ No Breaking Changes

- All existing commands work unchanged
- Visual indicators remain consistent
- Tmux-based async still available as fallback
- All workflow triggers function identically
- No configuration file changes required

### ✅ Backward Compatible

If you're on Claude Code < v2.1.12:
- Plugin detects version automatically
- Falls back to tmux-based async
- All workflows continue to work
- No degradation of functionality

---

## New Features in Action

### Example 1: Task Management

**Before (v7.11.x):**
```
/octo:embrace "Build authentication"
# No task tracking
# Manual progress monitoring
```

**After (v7.12.0 with Claude Code v2.1.16+):**
```
/octo:embrace "Build authentication"

🐙 CLAUDE OCTOPUS ACTIVATED - Full Double Diamond Workflow
📝 Tasks: 1 in progress, 0 completed, 3 pending

# Tasks auto-created with dependencies:
# [✓] Discover: Research auth patterns
# [→] Define: Scope auth requirements (blocked by Discover)
# [ ] Develop: Implement auth (blocked by Define)
# [ ] Deliver: Validate auth (blocked by Develop)
```

### Example 2: Fork Context Isolation

**Before (v7.11.x):**
```
/octo:discover "OAuth vs JWT authentication"
# Runs in main conversation
# Can bloat context with research
```

**After (v7.12.0 with Claude Code v2.1.16+):**
```
/octo:discover "OAuth vs JWT authentication"
# Runs in isolated fork context
# Main conversation stays clean
# Research happens in parallel
```

### Example 3: Task Status Visibility

**Visual Banner Enhancement:**

```
🐙 CLAUDE OCTOPUS ACTIVATED - Multi-provider research mode
🔍 [Dev] Discover Phase: OAuth authentication research
📋 Session: abc-123
📝 Tasks: 2 in progress, 1 completed, 1 pending  ← NEW

Providers:
🔴 Codex CLI: Available ✓
🟡 Gemini CLI: Available ✓
🔵 Claude: Available ✓
```

---

## Troubleshooting

### Issue: "Task management not available"

**Symptom:** Tasks not being created during workflows

**Cause:** Claude Code version < v2.1.16

**Solution:**
1. Check version: `claude --version`
2. Upgrade if needed: See "How to Upgrade" section
3. Or accept fallback mode (works fine)

---

### Issue: "Fork context not supported"

**Symptom:** Warning message about fork context

**Cause:** Claude Code version < v2.1.16

**Solution:**
- Upgrade to v2.1.16+ for fork context
- Or ignore warning - plugin uses standard execution mode

---

### Issue: Hook scripts not executable

**Symptom:** Hook errors during workflow execution

**Solution:**
```bash
chmod +x hooks/*.sh
```

---

### Issue: Test suite fails

**Symptom:** `./tests/test-v2.1.12-integration.sh` shows failures

**Diagnosis:**
```bash
# Run with verbose output
./tests/test-v2.1.12-integration.sh

# Check which tests fail:
# - Version detection failures → Claude CLI not in PATH
# - Hook script failures → Permissions issue
# - Frontmatter failures → Plugin update incomplete
```

**Solutions:**
1. **Version detection fails:** Ensure `claude` CLI is in PATH
2. **Hook scripts fail:** Run `chmod +x hooks/*.sh`
3. **Frontmatter fails:** Re-run plugin update

---

## FAQ

### Q: Will my existing workflows break?

**A:** No. All existing workflows continue to work identically. New features are opt-in via version detection.

### Q: Do I need to update my custom skills?

**A:** No. Custom skills work without changes. You can optionally add v2.1.12+ frontmatter fields:

```yaml
---
name: my-custom-skill
agent: Explore          # Optional: explicit agent routing
context: fork           # Optional: fork context isolation
task_management: true   # Optional: enable task tracking
---
```

### Q: Can I disable new features?

**A:** Yes. New features only activate if Claude Code v2.1.12+ is detected. To force legacy mode:

```bash
# Set environment variable
export CLAUDE_CODE_VERSION=""

# Or use older Claude Code version
```

### Q: What happens if Codex/Gemini CLI is missing?

**A:** The plugin detects missing providers and shows warnings:

```
⚠️  Codex CLI unavailable - workflow will run in degraded mode
⚠️  Gemini CLI unavailable - using Claude-only mode
```

Workflows continue with available providers.

### Q: Are there performance improvements?

**A:** Yes:

1. **Fork context** reduces memory usage in long sessions
2. **Task dependencies** enable better parallelization
3. **Wildcard permissions** reduce permission prompt friction

### Q: How do I report issues?

**A:** Open an issue on GitHub:
```
https://github.com/nyldn/claude-octopus/issues
```

Include:
- Claude Code version (`claude --version`)
- Plugin version (from `/octo:sys-setup`)
- Error messages or unexpected behavior
- Test suite output if applicable

---

## Rollback Instructions

If you need to rollback to v7.11.x:

```bash
# Uninstall current version
claude plugin uninstall nyldn-plugins/claude-octopus

# Install specific version
claude plugin install nyldn-plugins/claude-octopus@7.11.1
```

---

## Additional Resources

- **Changelog:** See `CHANGELOG.md` for detailed changes
- **Test Suite:** Run `./tests/test-v2.1.12-integration.sh` to verify
- **Setup Guide:** Run `/octo:sys-setup` for configuration help
- **GitHub Issues:** https://github.com/nyldn/claude-octopus/issues

---

## Summary

Claude Octopus v7.12.0 brings powerful new features while maintaining 100% backward compatibility. Upgrade when convenient - your existing workflows won't break, and new features activate automatically when available.

**Key Takeaways:**
- ✅ No breaking changes
- ✅ Automatic version detection
- ✅ Graceful fallback for older versions
- ✅ Enhanced features for v2.1.16+ users
- ✅ Comprehensive test suite included
