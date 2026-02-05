---
name: skill-task-management
aliases:
  - task-management
  - todo-orchestration
description: Task orchestration, checkpointing, and multi-session workflows
trigger: |
  AUTOMATICALLY ACTIVATE when user requests task management:
  - "add to the todo's" or "add this to todos"
  - "resume tasks" or "continue tasks" or "pick up where we left off"
  - "save progress" or "save progress for Claude to pick up"
  - "save progress to pickup later" or "checkpoint this"
  - "proceed to next steps" or "continue to next"

  DO NOT activate for:
  - Git operations (use skill-finish-branch)
  - Simple todo list viewing
  - Task completion with push (use skill-finish-branch)
---

# Task Management & Orchestration

## Overview

Systematic task orchestration for multi-step work, progress checkpointing, and seamless task resumption across sessions.

**Core principle:** Track → Checkpoint → Resume → Complete.

---

## When to Use

**Use this skill when user wants to:**
- Add items to the todo list
- Save current progress for later continuation
- Resume previously saved work
- Checkpoint progress in long-running tasks
- Proceed to next steps in a workflow
- Continue from where they left off

**Do NOT use for:**
- Creating git commits (use skill-finish-branch)
- Simple todo list queries ("what's on my list?")
- Task completion that involves pushing code

---

## Core Capabilities

### 1. Adding Tasks to Todo List

When user says "add to the todo's" or similar:

```markdown
**What would you like to add to the todo list?**

I'll help you capture this task. Please provide:
- Task description (what needs to be done)
- Any dependencies or prerequisites
- Priority (if applicable)
```

**After getting details, use TodoWrite tool to add:**

```
Adding to todo list:
✓ [Task description]

Current todo list now has N items.
```

---

### 2. Saving Progress / Checkpointing

When user says "save progress" or "checkpoint this":

#### Step 1: Assess Current State

```bash
# Check git status
git status

# Check current branch
git branch --show-current

# Check uncommitted work
git diff --stat
```

#### Step 2: Create Progress Checkpoint

**Option A: Git-based checkpoint (if git repo)**

```bash
# Create a work-in-progress commit
git add .
git commit -m "WIP: [description of current state]

Progress checkpoint - work in progress
Not ready for review or merge

Current state:
- [What's completed]
- [What's in progress]
- [What's next]

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

**Option B: Todo-based checkpoint (if no git or user prefers)**

Use TodoWrite to create detailed checkpoint:

```
📍 CHECKPOINT: [Timestamp]

Completed:
✓ [Task 1]
✓ [Task 2]

In Progress:
⚙️ [Current task with details]

Next Steps:
- [ ] [Next task 1]
- [ ] [Next task 2]
- [ ] [Next task 3]
```

#### Step 3: Provide Resume Instructions

```markdown
✅ Progress saved!

To resume this work:
1. Run: git checkout [branch-name]
2. Review todo list
3. Say: "resume tasks" or "pick up where we left off"

Current branch: [branch-name]
Last checkpoint: [timestamp]
```

---

### 3. Resuming Tasks

When user says "resume tasks" or "pick up where we left off":

#### Step 1: Locate Latest Checkpoint

```bash
# Check for WIP commits
git log --oneline -10 | grep WIP

# Check current branch
git branch --show-current

# Check git status
git status
```

#### Step 2: Present Current State

```markdown
📋 **Resuming from last checkpoint**

**Branch:** [branch-name]
**Last checkpoint:** [timestamp from WIP commit or todo]

**Completed:**
✓ [Completed task 1]
✓ [Completed task 2]

**In Progress:**
⚙️ [Current task]

**Next Steps:**
1. [ ] [Next task 1]
2. [ ] [Next task 2]
3. [ ] [Next task 3]

**Would you like me to:**
1. Continue with the next task?
2. Modify the plan?
3. See more details about current state?
```

#### Step 3: Execute Based on Choice

- If "continue with next task" → Mark first pending task as in_progress and begin work
- If "modify the plan" → Use AskUserQuestion to understand changes
- If "see more details" → Show git diff, file changes, recent commits

---

### 4. Proceeding to Next Steps

When user says "proceed to next steps":

#### Step 1: Check Current Task Status

```markdown
Checking current task status...

Current task: [task description]
Status: [in_progress/completed]
```

#### Step 2: Complete Current and Move Forward

```
Marking current task as complete...
✓ [Current task]

Moving to next task...
⚙️ [Next task description]

Proceeding with: [next task description]
```

#### Step 3: Execute Next Task

Begin working on the next task immediately after marking it as in_progress.

---

## Integration with Other Skills

### With skill-finish-branch

```
User: "save progress and prepare for PR"

1. Use skill-task-management to checkpoint
2. Then use skill-finish-branch to prepare PR
```

### With flow-tangle

```
User: "add implementation of auth system to todos"

1. Use skill-task-management to add high-level task
2. Use flow-tangle to break down and implement
```

### With skill-debug

```
User: "checkpoint this, I found a bug"

1. Use skill-task-management to save current progress
2. Use skill-debug to investigate the bug
3. Return to saved checkpoint after fix
```

---

## Best Practices

### 1. Clear Checkpoints

**Good checkpoint:**
```
WIP: User authentication flow - OAuth integration complete

Completed:
- OAuth provider configuration
- Token exchange endpoint
- User session middleware

In Progress:
- Token refresh logic (70% done)

Next:
- Add logout endpoint
- Add session expiration
- Write integration tests
```

**Poor checkpoint:**
```
WIP: stuff done
```

### 2. Granular Todo Items

**Good todo items:**
```
- [ ] Implement token refresh with 15-minute expiration
- [ ] Add logout endpoint that clears session cookie
- [ ] Write integration test for complete auth flow
```

**Poor todo items:**
```
- [ ] Do auth stuff
- [ ] Fix things
- [ ] Make it work
```

### 3. Context Preservation

When checkpointing, always include:
- What's completed (prevents re-doing work)
- What's in progress (enables quick resume)
- What's next (provides clear path forward)
- Why decisions were made (preserves reasoning)

---

## Common Patterns

### Pattern 1: End-of-Day Checkpoint

```
User: "save progress, I'm done for today"

Action:
1. Create WIP commit with current state
2. Document completed and pending items
3. Provide resume instructions for tomorrow
```

### Pattern 2: Context Switch

```
User: "checkpoint this, need to work on something else"

Action:
1. Save current branch state
2. Create detailed todo with context
3. Ready for resume when user returns
```

### Pattern 3: Collaboration Handoff

```
User: "save progress for Claude to pick up"

Action:
1. Create comprehensive checkpoint
2. Document all context and decisions
3. Provide clear next steps
4. Ensure new session can resume seamlessly
```

---

## Red Flags - Don't Do This

| Action | Why It's Wrong |
|--------|----------------|
| Checkpoint without documenting context | Next session won't know what was happening |
| Skip WIP commit for code changes | Lose work if something breaks |
| Generic "proceed to next" without checking current status | Might skip incomplete work |
| Add vague todos | Unclear what needs to be done |
| Resume without showing current state | User doesn't know where they are |

---

## Quick Reference

| User Intent | Skill Action | Output |
|-------------|--------------|--------|
| "add to todos" | Gather details, use TodoWrite | Todo item added |
| "save progress" | Create WIP commit + checkpoint | Resumable state saved |
| "resume tasks" | Load checkpoint, show state, ask direction | Ready to continue |
| "proceed to next" | Complete current, start next | Next task in progress |
| "checkpoint this" | Create detailed progress snapshot | Full context preserved |

---

## The Bottom Line

```
Task management → Clear state + Easy resume
Otherwise → Lost context + Duplicate work
```

**Track everything. Checkpoint frequently. Resume seamlessly.**
