---
name: skill-task-management
version: 1.0.0
description: "Track TODOs, checkpoint progress, and resume work across sessions using native Claude Code Task tools (TaskCreate, TaskUpdate, TaskList, TaskGet). Use when: user says 'add to todos', 'save progress', 'resume tasks', 'pick up where we left off', 'checkpoint this', or 'proceed to next steps'."
---

# Task Management & Orchestration (v7.23.0+)

**Core principle:** Track, Checkpoint, Resume, Complete — using native Claude Code Task tools.

Uses: `TaskCreate`, `TaskUpdate`, `TaskList`, `TaskGet`. Tasks show in native Claude Code UI.

## When to Use

**Activate when user wants to:** add to todo list, save/checkpoint progress, resume work, proceed to next steps, continue from where they left off.

**Do NOT use for:** git commits (use skill-finish-branch), simple list queries, pushing code.

---

## Core Capabilities

### 1. Adding Tasks

Gather task description, dependencies, and priority. Use `TaskCreate` with clear subject, detailed description, and activeForm. Confirm creation to user.

### 2. Saving Progress / Checkpointing

1. **Assess state**: Check `git status`, current branch, uncommitted work
2. **Create checkpoint**: Either WIP git commit or TaskCreate with checkpoint details (completed items, in-progress items, next steps, branch, last commit)
3. **Update tasks**: Mark completed tasks done, current task in_progress
4. **Provide resume instructions**: Branch name, task count summary, "say 'resume tasks' to continue"

### 3. Resuming Tasks

1. **Load state**: TaskList filtered by status + find checkpoint tasks
2. **Check git**: WIP commits, current branch, status
3. **Present**: Show completed/in-progress/pending breakdown with task subjects
4. **Ask**: Continue next task, modify plan, or see details

### 4. Proceeding to Next Steps

Mark current in_progress task as completed, find next pending unblocked task, mark it in_progress, begin work immediately.

---

## Migration from TodoWrite (v7.22.x → v7.23.0+)

Run `"${CLAUDE_PLUGIN_ROOT}/scripts/migrate-todos.sh"` to automatically convert `.claude/todos.md` files to TaskCreate calls. Old files archived to `.claude/archived-todos/`.

**Opt-out:** Create `.claude/claude-octopus.local.md` with `use_native_tasks: false` to use legacy TodoWrite.

---

## Integration with Other Skills

- **skill-finish-branch**: Checkpoint first, then prepare PR
- **flow-develop**: Add high-level task, then break down and implement
- **skill-debug**: Checkpoint current work, debug, return to checkpoint

---

## Best Practices

1. **Clear subjects**: "Implement token refresh with 15-minute expiration" not "Do auth stuff"
2. **Use dependencies**: `addBlockedBy` for tasks with prerequisites
3. **Rich checkpoints**: Include completed items, in-progress state, next steps, branch/commit info, and decision rationale

---

## Quick Reference

| User Intent | Skill Action | Tool Used |
|-------------|--------------|-----------|
| "add to todos" | Gather details, create task | TaskCreate |
| "save progress" | Create checkpoint task + WIP commit | TaskCreate + git |
| "resume tasks" | Load task state, show status, ask direction | TaskList |
| "proceed to next" | Complete current, start next | TaskUpdate |
| "checkpoint this" | Create detailed checkpoint task | TaskCreate |

## Task Status Workflow

`pending → in_progress → completed` (or `deleted` if cancelled)
