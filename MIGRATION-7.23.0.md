# Migration Guide: v7.22.x → v7.23.0

**Migration Date:** February 2026
**Breaking Changes:** Task management system
**Estimated Time:** 5-10 minutes

---

## What's Changing

claude-octopus v7.23.0 migrates from the legacy `TodoWrite` tool to native Claude Code Task tools:

| Old (v7.22.x) | New (v7.23.0+) | Purpose |
|---------------|----------------|---------|
| TodoWrite | TaskCreate | Create new tasks |
| TodoWrite (read) | TaskList | View all tasks |
| TodoWrite (update) | TaskUpdate | Update task status |
| N/A | TaskGet | Get specific task details |

**Why this change?**

- ✅ Tasks show in native Claude Code UI
- ✅ Better progress visualization
- ✅ Consistent with Claude Code conventions
- ✅ Improved task dependencies (blockedBy/blocks)
- ✅ Removes dependency on external TodoWrite tool

---

## Who Needs to Migrate?

**You need to migrate if you:**
- Have existing `.claude/todos.md` or similar markdown todo files
- Use `skill-task-management` for task tracking
- Have workflows that rely on TodoWrite

**You don't need to migrate if you:**
- Are a new user (v7.23.0+ uses native tasks by default)
- Don't use task management features
- Only use state management (.claude-octopus/state.json)

---

## Migration Steps

### Option 1: Automatic Migration (Recommended)

**Step 1: Backup your todos**

```bash
cp .claude/todos.md .claude/todos.md.backup
```

**Step 2: Run migration script**

```bash
# Preview changes first
~/.claude/plugins/cache/nyldn-plugins/claude-octopus/7.23.0/scripts/migrate-todos.sh --dry-run

# If preview looks good, run migration
~/.claude/plugins/cache/nyldn-plugins/claude-octopus/7.23.0/scripts/migrate-todos.sh
```

**Step 3: Verify tasks**

```
/tasks  # View native tasks in Claude Code
```

Your old todos are now native tasks!

### Option 2: Manual Migration

For each todo item in your markdown files:

**Before (v7.22.x):**
```markdown
<!-- .claude/todos.md -->
- [ ] Implement user authentication
- [x] Set up database
- [ ] Create API endpoints
```

**After (v7.23.0):**
```javascript
// These become native tasks
TaskCreate({
  subject: "Implement user authentication",
  description: "Create auth system with JWT tokens",
  activeForm: "Implementing authentication"
})

TaskCreate({
  subject: "Set up database",
  description: "Configure PostgreSQL and run migrations",
  activeForm: "Setting up database"
})
TaskUpdate({ taskId: "2", status: "completed" })  // Was [x]

TaskCreate({
  subject: "Create API endpoints",
  description: "Build REST API for user operations",
  activeForm: "Creating API endpoints"
})
```

---

## Backward Compatibility

### Keep Using TodoWrite (Not Recommended)

If you prefer the old system, create `.claude/claude-octopus.local.md`:

```yaml
---
use_native_tasks: false
---

# Claude Octopus Local Configuration

This project uses legacy TodoWrite instead of native Task management.

Note: TodoWrite support will be removed in v7.25.0 (Q2 2026).
```

**Limitations:**
- No native UI integration
- Missing task dependency features
- No progress visualization
- Will be removed in future version

---

## What Stays the Same

**These features are unchanged:**

- ✅ State management (`.claude-octopus/state.json`)
- ✅ Multi-AI orchestration (Codex + Gemini + Claude)
- ✅ Double Diamond workflows (Discover → Define → Develop → Deliver)
- ✅ All commands (`/octo:research`, `/octo:develop`, etc.)
- ✅ Git-based checkpointing (WIP commits)

Only the **task tracking mechanism** has changed.

---

## New Features in v7.23.0

### 1. Task Dependencies

```javascript
// Task 1
TaskCreate({
  subject: "Set up OAuth configuration",
  description: "Configure Auth0 settings",
  activeForm: "Configuring OAuth"
})

// Task 2 (depends on Task 1)
TaskCreate({
  subject: "Implement login endpoint",
  description: "Create /auth/login endpoint",
  activeForm: "Implementing login",
  addBlockedBy: ["1"]  // Can't start until task 1 complete
})
```

### 2. Native UI Integration

Tasks now appear in Claude Code's native task interface:
- View: `/tasks` command
- Filter by status
- See task dependencies
- Track progress visually

### 3. Better Task Status Workflow

```
pending → in_progress → completed
            ↓
          deleted (if cancelled)
```

### 4. Active Form for Progress Indication

```javascript
TaskCreate({
  subject: "Implement authentication",
  activeForm: "Implementing authentication system"  // Shows in progress spinner
})
```

---

## Testing Your Migration

After migrating, test the new system:

### Test 1: Create a Task

```
Say: "add implementing feature X to my todos"

Verify: Task appears in /tasks
```

### Test 2: Resume Tasks

```
Say: "resume tasks"

Verify: TaskList shows all tasks with status
```

### Test 3: Checkpoint Progress

```
Say: "save progress for later"

Verify: Checkpoint task created with current state
```

### Test 4: Complete a Task

```
Say: "proceed to next steps"

Verify: Current task marked completed, next task starts
```

---

## Troubleshooting

### Issue: "TodoWrite tool not found"

**Cause:** You're on v7.23.0+ which removed TodoWrite

**Solution:** Run migration script or manually convert todos to native tasks

### Issue: "Tasks don't show in /tasks"

**Cause:** Tasks may not have been created properly

**Solution:**
```bash
# Check migration output
cat ~/.claude/archived-todos/migration-*.jsonl

# Manually create tasks if needed
```

### Issue: "I want my old todos back"

**Cause:** Migration went wrong

**Solution:**
```bash
# Restore from backup
cp .claude/todos.md.backup .claude/todos.md

# Or from archive
cp ~/.claude/archived-todos/todos.md.*.bak .claude/todos.md

# Enable backward compatibility
echo "---\nuse_native_tasks: false\n---" > .claude/claude-octopus.local.md
```

### Issue: "Task migration created duplicates"

**Cause:** Migration ran multiple times

**Solution:**
```bash
# Clear native tasks (use with caution!)
/tasks clear

# Re-run migration from backup
cp .claude/todos.md.backup .claude/todos.md
~/.claude/plugins/cache/nyldn-plugins/claude-octopus/7.23.0/scripts/migrate-todos.sh
```

---

## API Changes for Plugin Developers

### Removed APIs (v7.23.0)

- `TodoWrite` tool calls (use TaskCreate/TaskUpdate instead)
- `skill-task-management.md` section on TodoWrite

### New APIs (v7.23.0)

- `TaskCreate({ subject, description, activeForm })`
- `TaskUpdate({ taskId, status, subject, description })`
- `TaskList()` - returns array of tasks
- `TaskGet({ taskId })` - returns task details

### Updated Skills

- `skill-task-management.md` → `skill-task-management-v2.md`
- Added task dependency support (blockedBy/blocks)
- Removed TodoWrite references

---

## Timeline

| Version | Changes | Date |
|---------|---------|------|
| v7.22.01 | Last version with TodoWrite | Feb 2026 |
| **v7.23.0** | **Migration to native Tasks** | **Feb 2026** |
| v7.24.0 | Hybrid plan mode integration | Mar 2026 |
| v7.25.0 | Remove TodoWrite compatibility | Apr 2026 |

**Recommendation:** Migrate to native tasks by **March 2026** before v7.25.0 removes TodoWrite support.

---

## Getting Help

**Issues during migration?**

1. Check logs: `~/.claude-octopus/logs/`
2. Report issue: https://github.com/nyldn/claude-octopus/issues
3. Join discussion: https://github.com/nyldn/claude-octopus/discussions

**Include in report:**
- Migration script output
- Original .md file content
- Claude Code version (`/version`)
- claude-octopus version

---

## Summary

**What you need to do:**

1. ✅ Run migration script (or manually convert)
2. ✅ Test task creation/resumption
3. ✅ Verify tasks show in `/tasks`
4. ✅ Remove old .md files (archived automatically)

**Total time:** 5-10 minutes

**Benefits:**
- Native UI integration
- Better task tracking
- Task dependencies
- Progress visualization

**Questions?** See [docs/NATIVE-INTEGRATION.md](docs/NATIVE-INTEGRATION.md) for technical details.

---

*Migration completed successfully? You're ready for v7.23.0! 🎉*
