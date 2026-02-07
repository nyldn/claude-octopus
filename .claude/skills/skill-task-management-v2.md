---
name: skill-task-management
aliases:
  - task-management
  - todo-orchestration
description: Task management using native Claude Code TaskCreate/TaskUpdate tools
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

# Task Management & Orchestration (v7.23.0+)

## Overview

Systematic task orchestration for multi-step work, progress checkpointing, and seamless task resumption across sessions.

**Core principle:** Track → Checkpoint → Resume → Complete.

**v7.23.0 Migration:** This skill now uses native Claude Code Task tools:
- `TaskCreate` - Create new tasks
- `TaskUpdate` - Update task status/details
- `TaskList` - View all tasks
- `TaskGet` - Get specific task details

**Benefits:**
- ✅ Tasks show in native Claude Code UI
- ✅ Better progress tracking and visualization
- ✅ Consistent with Claude Code conventions
- ✅ No dependency on external TodoWrite tool

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

**After getting details, use TaskCreate to add:**

```javascript
TaskCreate({
  subject: "[Brief task description]",
  description: "[Detailed description including dependencies and context]",
  activeForm: "Working on [task description]"
})
```

**Then confirm to user:**

```
✅ Task created: [Task description]

View all tasks with TaskList or use /tasks command.
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

**Option B: Task-based checkpoint (preferred for tracking)**

Create checkpoint task with detailed state:

```javascript
TaskCreate({
  subject: "Checkpoint: [Brief description]",
  description: `
📍 CHECKPOINT: ${new Date().toISOString()}

Completed:
✓ [Task 1]
✓ [Task 2]

In Progress:
⚙️ [Current task with details]

Next Steps:
- [ ] [Next task 1]
- [ ] [Next task 2]
- [ ] [Next task 3]

Context:
- Branch: ${branchName}
- Last commit: ${lastCommit}
- Files changed: ${filesChanged}
  `,
  activeForm: "Checkpoint saved"
})
```

#### Step 3: Update Existing Tasks

Mark completed tasks as done:

```javascript
// For each completed task
TaskUpdate({
  taskId: "[task-id]",
  status: "completed"
})
```

Mark current task as in_progress:

```javascript
TaskUpdate({
  taskId: "[current-task-id]",
  status: "in_progress"
})
```

#### Step 4: Provide Resume Instructions

```markdown
✅ Progress saved!

To resume this work:
1. Run: git checkout [branch-name]
2. View tasks: TaskList
3. Say: "resume tasks" or "pick up where we left off"

Current state:
- Branch: [branch-name]
- Tasks: [X completed, Y in progress, Z pending]
- Last checkpoint: [timestamp]
```

---

### 3. Resuming Tasks

When user says "resume tasks" or "pick up where we left off":

#### Step 1: Load Task State

```javascript
// Get all tasks
const tasks = TaskList()

// Filter by status
const completed = tasks.filter(t => t.status === 'completed')
const inProgress = tasks.filter(t => t.status === 'in_progress')
const pending = tasks.filter(t => t.status === 'pending')

// Find checkpoint task (if exists)
const checkpoint = tasks.find(t => t.subject.startsWith('Checkpoint:'))
```

#### Step 2: Check Git State

```bash
# Check for WIP commits
git log --oneline -10 | grep WIP

# Check current branch
git branch --show-current

# Check git status
git status
```

#### Step 3: Present Current State

```markdown
📋 **Resuming from last checkpoint**

**Branch:** [branch-name]
**Last checkpoint:** [timestamp from WIP commit or checkpoint task]

**Completed:** (${completed.length} tasks)
${completed.map(t => `✓ ${t.subject}`).join('\n')}

**In Progress:** (${inProgress.length} tasks)
${inProgress.map(t => `⚙️ ${t.subject}`).join('\n')}

**Next Steps:** (${pending.length} tasks)
${pending.map((t, i) => `${i + 1}. [ ] ${t.subject}`).join('\n')}

**Would you like me to:**
1. Continue with the next task?
2. Modify the plan?
3. See more details about current state?
```

#### Step 4: Execute Based on Choice

- If "continue with next task" → Get first pending task, mark as in_progress, and begin work:
  ```javascript
  const nextTask = pending[0]
  TaskUpdate({ taskId: nextTask.id, status: 'in_progress' })
  // Begin working on nextTask
  ```

- If "modify the plan" → Use AskUserQuestion to understand changes, then update tasks

- If "see more details" → Show git diff, file changes, recent commits, task descriptions

---

### 4. Proceeding to Next Steps

When user says "proceed to next steps":

#### Step 1: Check Current Task Status

```javascript
const tasks = TaskList()
const currentTask = tasks.find(t => t.status === 'in_progress')

if (currentTask) {
  console.log(`Current task: ${currentTask.subject}`)
  console.log(`Status: ${currentTask.status}`)
}
```

#### Step 2: Complete Current and Move Forward

```javascript
// Mark current task as complete
if (currentTask) {
  TaskUpdate({
    taskId: currentTask.id,
    status: 'completed'
  })
  console.log(`✓ ${currentTask.subject}`)
}

// Get next pending task
const nextTask = tasks.find(t => t.status === 'pending' && !t.blockedBy?.length)

if (nextTask) {
  // Mark as in progress
  TaskUpdate({
    taskId: nextTask.id,
    status: 'in_progress'
  })
  console.log(`\n⚙️ ${nextTask.subject}`)
  console.log(`\nProceeding with: ${nextTask.description}`)
}
```

#### Step 3: Execute Next Task

Begin working on the next task immediately after marking it as in_progress.

---

## Migration from TodoWrite (v7.22.x → v7.23.0+)

### For Users with Existing .md Todo Files

If you have existing `.claude/todos.md` or similar files:

#### Option 1: Automatic Migration

```bash
# Run migration script
"${CLAUDE_PLUGIN_ROOT}/scripts/migrate-todos.sh"
```

This will:
1. Parse existing .md todo files
2. Convert to TaskCreate calls
3. Preserve task order and status
4. Archive old .md files to `.claude/archived-todos/`

#### Option 2: Manual Migration

For each todo item in your .md file:

```markdown
<!-- Old format in todos.md -->
- [ ] Implement user authentication
- [x] Set up database
- [ ] Create API endpoints
```

Convert to:

```javascript
// New format using native tasks
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
// Mark as completed since it was [x]
TaskUpdate({ taskId: "...", status: "completed" })

TaskCreate({
  subject: "Create API endpoints",
  description: "Build REST API for user operations",
  activeForm: "Creating API endpoints"
})
```

### Backward Compatibility

**Opt-out for users who prefer old system:**

Create `.claude/claude-octopus.local.md` with:

```yaml
---
use_native_tasks: false
---

# Claude Octopus Local Configuration

This project uses legacy TodoWrite tool instead of native Task management.
```

When `use_native_tasks: false`, skill falls back to TodoWrite behavior.

---

## Integration with Other Skills

### With skill-finish-branch

```
User: "save progress and prepare for PR"

1. Use skill-task-management to checkpoint (create tasks for current state)
2. Then use skill-finish-branch to prepare PR
```

### With flow-develop

```
User: "add implementation of auth system to todos"

1. Use skill-task-management to add high-level task
2. Use flow-develop to break down and implement
3. Update tasks as work progresses
```

### With skill-debug

```
User: "checkpoint this, I found a bug"

1. Use skill-task-management to save current progress (checkpoint task)
2. Use skill-debug to investigate the bug
3. Return to saved checkpoint after fix
```

---

## Best Practices

### 1. Clear Task Subjects and Descriptions

**Good task:**
```javascript
TaskCreate({
  subject: "Implement token refresh with 15-minute expiration",
  description: `
Create token refresh endpoint that:
- Validates refresh token from secure HTTP-only cookie
- Issues new access token with 15min expiry
- Rotates refresh token for security
- Returns 401 if refresh token invalid/expired

Dependencies: OAuth provider setup must be complete
  `,
  activeForm: "Implementing token refresh logic"
})
```

**Poor task:**
```javascript
TaskCreate({
  subject: "Do auth stuff",
  description: "Fix things",
  activeForm: "Working"
})
```

### 2. Use Task Dependencies

For tasks with prerequisites:

```javascript
// First task
TaskCreate({
  subject: "Set up OAuth provider configuration",
  description: "Configure Auth0 application settings",
  activeForm: "Configuring OAuth provider"
})

// Dependent task
TaskCreate({
  subject: "Implement token refresh endpoint",
  description: "Create /auth/refresh endpoint",
  activeForm: "Implementing refresh endpoint",
  addBlockedBy: ["1"]  // Blocked by task #1
})
```

### 3. Context Preservation in Checkpoints

When checkpointing, always include:
- What's completed (prevents re-doing work)
- What's in progress (enables quick resume)
- What's next (provides clear path forward)
- Why decisions were made (preserves reasoning)

Example checkpoint task:

```javascript
TaskCreate({
  subject: "Checkpoint: Auth implementation 70% complete",
  description: `
📍 CHECKPOINT: 2026-02-03T14:30:00Z

Completed:
✓ OAuth provider configuration (Auth0)
✓ Token exchange endpoint (/auth/login)
✓ User session middleware

In Progress:
⚙️ Token refresh logic (70% done)
  - Validation complete
  - Token rotation TODO
  - Cookie handling TODO

Next:
- [ ] Complete token rotation logic
- [ ] Add logout endpoint
- [ ] Add session expiration handling
- [ ] Write integration tests

Branch: feature/auth-system
Last commit: abc123f "Add session middleware"

Decisions Made:
- Using Auth0 (rationale: enterprise-grade, handles complexity)
- 15-minute access token expiry (security vs UX balance)
- HTTP-only cookies for refresh tokens (XSS protection)
  `,
  activeForm: "Checkpoint saved"
})
```

---

## Common Patterns

### Pattern 1: End-of-Day Checkpoint

```
User: "save progress, I'm done for today"

Action:
1. Create WIP commit with current state
2. Create checkpoint task with completed/pending breakdown
3. Mark in-progress tasks with current status
4. Provide resume instructions for tomorrow
```

### Pattern 2: Context Switch

```
User: "checkpoint this, need to work on something else"

Action:
1. Save current branch state (WIP commit)
2. Create checkpoint task with detailed context
3. Mark current task as pending (will resume later)
4. Ready for resume when user returns
```

### Pattern 3: Collaboration Handoff

```
User: "save progress for Claude to pick up"

Action:
1. Create comprehensive checkpoint task
2. Document all context and decisions
3. Mark in-progress tasks with current state
4. Ensure new session can load task state and resume seamlessly
```

---

## Red Flags - Don't Do This

| Action | Why It's Wrong |
|--------|----------------|
| Checkpoint without documenting context | Next session won't know what was happening |
| Skip WIP commit for code changes | Lose work if something breaks |
| Generic "proceed to next" without checking TaskList | Might skip incomplete work |
| Vague task subjects/descriptions | Unclear what needs to be done |
| Resume without showing TaskList state | User doesn't know where they are |
| Create tasks without activeForm | No progress indication in UI |

---

## Quick Reference

| User Intent | Skill Action | Tool Used |
|-------------|--------------|-----------|
| "add to todos" | Gather details, create task | TaskCreate |
| "save progress" | Create checkpoint task + WIP commit | TaskCreate + git |
| "resume tasks" | Load task state, show status, ask direction | TaskList |
| "proceed to next" | Complete current, start next | TaskUpdate |
| "checkpoint this" | Create detailed checkpoint task | TaskCreate |

---

## Task Status Workflow

```
pending → in_progress → completed
                ↓
              deleted (if no longer needed)
```

**Best practices:**
- Create tasks in `pending` state
- Mark `in_progress` when starting work
- Mark `completed` only when fully done
- Use `deleted` for cancelled/obsolete tasks

---

## The Bottom Line

```
Task management → Clear state + Easy resume + Native UI
Otherwise → Lost context + Duplicate work + No visibility
```

**Track everything. Checkpoint frequently. Resume seamlessly. Use native tools.**

---

## Example: Full Workflow

```javascript
// User: "add implementing auth to my todos"

// Step 1: Create main task
TaskCreate({
  subject: "Implement user authentication system",
  description: `
Build complete auth system with:
- OAuth 2.0 (Auth0 provider)
- JWT token management
- Refresh token rotation
- Session middleware
- Logout functionality
  `,
  activeForm: "Planning authentication implementation"
})

// User works on it...

// User: "save progress for tomorrow"

// Step 2: Create checkpoint
TaskCreate({
  subject: "Checkpoint: Auth implementation in progress",
  description: `
📍 Checkpoint: 2026-02-03T18:30:00Z

Completed:
✓ OAuth configuration
✓ Login endpoint

In Progress:
⚙️ Token refresh (50%)

Next:
- [ ] Complete refresh logic
- [ ] Add logout
- [ ] Write tests

Branch: feature/auth
Commit: abc123f
  `,
  activeForm: "Checkpoint saved"
})

// Step 3: Update main task status
TaskUpdate({
  taskId: "1",
  status: "in_progress"
})

// User: "resume tasks" (next day)

// Step 4: Load and present state
const tasks = TaskList()
// Present: "You have 1 in_progress task, last checkpoint 2026-02-03T18:30:00Z"
// Show details from checkpoint task

// User: "continue"

// Step 5: Resume work
const currentTask = tasks.find(t => t.status === 'in_progress')
// Begin working on token refresh where they left off
```
