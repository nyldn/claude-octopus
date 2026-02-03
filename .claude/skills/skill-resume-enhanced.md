---
name: skill-resume-enhanced
aliases:
  - resume
  - resume-session
  - context-resume
description: |
  Enhanced session resumption skill for v7.25.0+
  Resilient to context clearing from native plan mode (EnterPlanMode/ExitPlanMode).

  Automatically reloads state from .claude-octopus/state.json and restores:
  - Prior workflow phases and their findings
  - Architectural decisions made
  - Current tasks and their status
  - Blockers and impediments
  - Metrics and execution history

  Use PROACTIVELY when:
  - Starting a new conversation after context was cleared
  - User says "resume", "continue from where we left off", "what was I working on"
  - Detecting prior state exists (.claude-octopus/state.json)

  DO NOT use for: Simple task resumption (use skill-task-management), git operations
trigger: |
  AUTOMATICALLY ACTIVATE when:
  - User says "resume", "continue", "pick up where we left off"
  - User asks "what was I working on", "where did we leave off"
  - Detecting .claude-octopus/state.json exists but no prior context in memory
---

# Enhanced Session Resume (v7.25.0+)

## Overview

Resilient session resumption that survives context clearing from native plan mode.

**Core principle:** State persists in files → Always resumable.

**New in v7.25.0:**
- Automatic detection of context clearing
- State reload from `.claude-octopus/state.json`
- Task state restoration
- Decision history replay
- Seamless multi-day project continuity

---

## How It Works

### Context Clearing Detection

```bash
# Check if state exists but memory doesn't
if [[ -f .claude-octopus/state.json ]] && [[ -z "${WORKFLOW_CONTEXT_LOADED}" ]]; then
    echo "⚠️  Context was cleared (likely by native plan mode ExitPlanMode)"
    echo "   Reloading state from persistent storage..."
    NEEDS_RESUME=true
fi
```

### State Persistence Across Context Clearing

**What survives context clearing:**
- ✅ `.claude-octopus/state.json` (decisions, context, metrics)
- ✅ `.claude-octopus/context/*.md` (phase outputs)
- ✅ Native tasks (TaskList still works)
- ✅ Git commits and WIP checkpoints
- ✅ Multi-AI synthesis files in `~/.claude-octopus/results/`

**What gets cleared:**
- ❌ Claude's memory of prior conversations
- ❌ Workflow phase outputs (but restored from files)
- ❌ Reasoning and decision context (but replayed from state)

---

## Execution Protocol

### Step 1: Detect Resume Condition

```bash
# Initialize state manager
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" init_state

# Read current state
state=$("${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" read_state)

# Check if resume needed
project_id=$(echo "$state" | jq -r '.project_id // ""')
current_workflow=$(echo "$state" | jq -r '.current_workflow // ""')
current_phase=$(echo "$state" | jq -r '.current_phase // ""')

if [[ -n "$project_id" && -n "$current_workflow" ]]; then
    echo "📋 Resuming project: $project_id"
    echo "   Last workflow: $current_workflow"
    echo "   Current phase: $current_phase"
    NEEDS_RESUME=true
else
    echo "No prior session found"
    NEEDS_RESUME=false
fi
```

### Step 2: Load Prior Context

If resume needed, load all prior state:

```bash
# Get context from each phase
discover_context=$(echo "$state" | jq -r '.context.discover // ""')
define_context=$(echo "$state" | jq -r '.context.define // ""')
develop_context=$(echo "$state" | jq -r '.context.develop // ""')
deliver_context=$(echo "$state" | jq -r '.context.deliver // ""')

# Get decisions made
decisions=$(echo "$state" | jq -r '.decisions')

# Get active blockers
blockers=$(echo "$state" | jq -r '.blockers[] | select(.status == "active")')

# Get metrics
metrics=$(echo "$state" | jq -r '.metrics')
```

### Step 3: Load Task State

```javascript
// Get all tasks from native Task system
const tasks = TaskList()

const completed = tasks.filter(t => t.status === 'completed')
const inProgress = tasks.filter(t => t.status === 'in_progress')
const pending = tasks.filter(t => t.status === 'pending')
```

### Step 4: Present Resume Summary

Display comprehensive summary of prior state:

```markdown
📋 **SESSION RESUME - Reloading Context**

**Project:** ${project_id}
**Session Start:** ${session_start}
**Last Active:** ${last_active}

═══════════════════════════════════════════════════
## PHASE PROGRESS
═══════════════════════════════════════════════════

🔍 **Discover Phase:** ${discover_context ? 'Complete' : 'Not started'}
${discover_context ? `   Key Findings: ${discover_context}` : ''}

🎯 **Define Phase:** ${define_context ? 'Complete' : 'Not started'}
${define_context ? `   Scope: ${define_context}` : ''}

🛠️ **Develop Phase:** ${develop_context ? 'Complete' : 'In progress'}
${develop_context ? `   Status: ${develop_context}` : ''}

✅ **Deliver Phase:** ${deliver_context ? 'Complete' : 'Not started'}
${deliver_context ? `   Validation: ${deliver_context}` : ''}

═══════════════════════════════════════════════════
## ARCHITECTURAL DECISIONS
═══════════════════════════════════════════════════

${decisions.map(d => `
**${d.phase.toUpperCase()}:** ${d.decision}
Rationale: ${d.rationale}
Date: ${d.date}
`).join('\n')}

═══════════════════════════════════════════════════
## CURRENT TASKS
═══════════════════════════════════════════════════

**Completed:** (${completed.length})
${completed.map(t => `✓ ${t.subject}`).join('\n')}

**In Progress:** (${inProgress.length})
${inProgress.map(t => `⚙️ ${t.subject}\n   ${t.description}`).join('\n')}

**Pending:** (${pending.length})
${pending.slice(0, 3).map(t => `- [ ] ${t.subject}`).join('\n')}
${pending.length > 3 ? `... and ${pending.length - 3} more` : ''}

═══════════════════════════════════════════════════
## ACTIVE BLOCKERS
═══════════════════════════════════════════════════

${blockers.length > 0 ? blockers.map(b => `
⚠️  ${b.description}
   Phase: ${b.phase}
   Created: ${b.created}
`).join('\n') : 'No active blockers'}

═══════════════════════════════════════════════════
## METRICS
═══════════════════════════════════════════════════

Phases Completed: ${metrics.phases_completed}/4
Execution Time: ${metrics.total_execution_time_minutes} minutes
Provider Usage:
${Object.entries(metrics.provider_usage || {}).map(([k, v]) =>
  `  - ${k}: ${v} queries`
).join('\n')}

═══════════════════════════════════════════════════
## WHAT'S NEXT?
═══════════════════════════════════════════════════

${inProgress.length > 0 ?
  `Continue working on: ${inProgress[0].subject}` :
  pending.length > 0 ?
    `Start next task: ${pending[0].subject}` :
    `All tasks complete. Ready for delivery phase.`
}
```

### Step 5: Mark Context as Loaded

```bash
# Set environment variable to prevent duplicate reloads
export WORKFLOW_CONTEXT_LOADED=true

# Update state to track resume
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_metrics "resumes" "1"
```

---

## Integration with Workflows

### Auto-Resume at Workflow Start

All Double Diamond workflows should check for prior state:

```bash
# At start of flow-discover.md, flow-define.md, etc.

# Check if context needs reloading
if [[ -f .claude-octopus/state.json ]] && [[ -z "${WORKFLOW_CONTEXT_LOADED}" ]]; then
    echo "🔄 Reloading prior session context..."

    # Call resume skill
    source "${CLAUDE_PLUGIN_ROOT}/.claude/skills/skill-resume-enhanced.md"

    # Context now loaded, proceed with workflow
fi

# Continue with normal workflow execution
```

### Resume After Native Plan Mode

**Scenario:** User ran native `EnterPlanMode`, did planning, then `ExitPlanMode` cleared context.

```bash
# When they return to octopus workflow
if [[ -f .claude-octopus/state.json ]]; then
    echo "⚠️  Detected prior octopus session"
    echo "   Native plan mode may have cleared context"
    echo "   Reloading from persistent state..."

    # Resume protocol
    # ... (Steps 1-5 above)

    echo "✅ Context restored. Ready to continue."
fi
```

---

## Example: Multi-Day Project Continuity

### Day 1: Start Project

```bash
User: "Let's build an auth system"

# Octopus runs discover phase
→ Saves findings to .claude-octopus/state.json
→ context.discover = "Researched OAuth patterns, recommend JWT with PKCE"

# Octopus runs define phase
→ Updates state.json
→ context.define = "Scope: passwordless magic links, 15min token expiry"

# User ends session
User: "Save progress for tomorrow"

→ Creates checkpoint task
→ State persists in files
```

### Day 2: Resume Project (After Context Cleared)

```bash
User: "Resume where we left off"

# Resume skill activates
→ Detects .claude-octopus/state.json exists
→ Loads prior context:
  - Discover findings
  - Define scope
  - Decisions made
  - Tasks (completed, in-progress, pending)

# Presents resume summary:
📋 SESSION RESUME

Phases Complete: Discover ✓, Define ✓
Current Phase: Develop (0% complete)
Tasks: 3 completed, 1 in-progress, 5 pending

Next: Continue implementing token refresh logic

# User continues
User: "Continue"

→ Resumes develop phase with full context
→ No information lost despite context clearing
```

---

## Best Practices

### 1. Always Initialize State at Workflow Start

```bash
# First line of every workflow
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" init_state

# Check for prior state
if [[ -f .claude-octopus/state.json ]]; then
    # Resume if needed
fi
```

### 2. Save Context After Each Phase

```bash
# After discover completes
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_context \
  "discover" \
  "$(summarize_findings)"

# After define completes
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_context \
  "define" \
  "$(summarize_scope)"

# etc.
```

### 3. Record All Architectural Decisions

```bash
# Whenever making a technical choice
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" write_decision \
  "${current_phase}" \
  "Use React 19 with Next.js 15" \
  "Modern stack with Server Components support"
```

### 4. Mark Context as Loaded

```bash
# After resume completes
export WORKFLOW_CONTEXT_LOADED=true

# Prevents duplicate reloads in same session
```

---

## Troubleshooting

### Issue: "Context keeps reloading on every command"

**Cause:** `WORKFLOW_CONTEXT_LOADED` not being set

**Solution:**
```bash
# After resume, set flag
export WORKFLOW_CONTEXT_LOADED=true
```

### Issue: "Resume shows 'No prior session' but state.json exists"

**Cause:** State file may be corrupted or empty

**Solution:**
```bash
# Check state validity
jq empty .claude-octopus/state.json

# View raw state
cat .claude-octopus/state.json | jq .

# If corrupted, restore from backup
cp .claude-octopus/state.json.backup .claude-octopus/state.json
```

### Issue: "Tasks not showing in resume"

**Cause:** Tasks may not have been created with native Task tools

**Solution:**
```bash
# Check native tasks
/tasks

# If empty, check for legacy todos
ls .claude/todos.md

# Migrate if needed
"${CLAUDE_PLUGIN_ROOT}/scripts/migrate-todos.sh"
```

---

## Testing Resume Resilience

### Test 1: Basic Resume

```bash
# Day 1
/octo:discover "OAuth patterns"
→ Completes, saves state

# Day 2 (new session, context cleared)
/octo:resume
→ Should reload discover findings
```

### Test 2: Native Plan Mode Interaction

```bash
# Start octopus workflow
/octo:embrace "Build auth system"
→ Runs discover, define phases

# User switches to native plan mode
EnterPlanMode
→ Does planning
ExitPlanMode  # Clears context

# Resume octopus workflow
/octo:develop
→ Should auto-detect context clearing
→ Should reload discover + define findings
→ Should continue without loss of information
```

### Test 3: Multi-Day Project

```bash
# Day 1
/octo:embrace "Complete feature"
→ Completes discover, define, 50% develop

# Day 2 (context cleared overnight)
/octo:resume
→ Shows all prior progress
→ Resumes from 50% develop point
```

---

## The Bottom Line

```
State persistence → Always resumable → No context loss
Even with native plan mode context clearing

Files outlive memory. Always.
```

**Context clearing is not a problem. State files are the source of truth.**

---

## Integration Summary

### v7.25.0+ Features

- ✅ Automatic context reload after clearing
- ✅ Resilient to native plan mode (EnterPlanMode/ExitPlanMode)
- ✅ Multi-day project continuity
- ✅ Task state restoration
- ✅ Decision history replay
- ✅ Seamless workflow resumption

### Migration from v7.24.0

No migration needed. Enhanced resume is automatic:
- Existing `.claude-octopus/state.json` files work as-is
- Auto-detects context clearing
- Backward compatible with all workflows

---

*State persists. Context reloads. Work continues. 🐙*
