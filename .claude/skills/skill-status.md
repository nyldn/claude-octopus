---
name: skill-status
description: Show project progress dashboard and suggest next actions
trigger: |
  AUTOMATICALLY ACTIVATE when user asks about:
  - "status" or "progress" or "where am I"
  - "what's next" or "next step"
  - "show status" or "project status"
  - "what have I been working on" or "summarize recent work"
  - "update project memory" or "update CLAUDE.md"
---

# Project Status Dashboard

## Overview

Display current project status, roadmap progress, blockers, and intelligent next-action suggestions based on workflow state.

**Core principle:** Read state → Display dashboard → Route intelligently.

---

## When to Use

**Use this skill when user asks:**
- "What's the status?" or "Show me progress"
- "Where am I in the workflow?"
- "What should I do next?"
- "What's the current phase?"
- "Are there any blockers?"
- "What have I been working on?" or "Summarize recent work"
- "Update project memory" or "Update CLAUDE.md"

**Do NOT use for:**
- Creating new projects (use /octo:embrace)
- Modifying state (use octo-state.sh write_state)
- Detailed phase planning (use flow-* skills)

---

## The Process

### Phase 1: Check Project Initialization

#### Step 1: Verify .octo/ Directory Exists

```bash
# Check if project is initialized
if [[ ! -d ".octo" ]]; then
    echo "No project initialized"
    exit 1
fi
```

**If .octo/ does not exist:**

```markdown
## Project Status

**Status:** Not initialized

No Claude Octopus project found in this directory.

### Get Started

Run `/octo:embrace [your project description]` to initialize a new project and start the Double Diamond workflow.

**Example:**
```
/octo:embrace build a user authentication system
```

This will:
1. Create .octo/ directory structure
2. Initialize STATE.md, PROJECT.md, ROADMAP.md
3. Begin Discover phase (research and exploration)
```

**Stop here** - do not proceed to Phase 2.

---

### Phase 2: Read Current State

#### Step 1: Execute octo-state.sh read_state

```bash
# Read current state from STATE.md
./scripts/octo-state.sh read_state
```

**Expected output format:**
```
schema=1.0
last_updated=2026-02-02T10:30:00Z
current_phase=2
current_position=define-requirements
status=in_progress
```

#### Step 2: Parse State Variables

Extract key-value pairs:
- `current_phase` - Phase number (1-4)
- `current_position` - Specific position within phase
- `status` - Current workflow status
- `last_updated` - Last state modification timestamp

---

### Phase 3: Read Roadmap

#### Step 1: Read ROADMAP.md

```bash
# Read roadmap for phase overview
cat .octo/ROADMAP.md
```

#### Step 2: Extract Phase Information

Parse ROADMAP.md to identify:
- Phase names (Discover, Define, Develop, Deliver)
- Phase descriptions
- Success criteria for each phase
- Dependencies between phases

---

### Phase 4: Display Dashboard

#### Step 1: Build Status Dashboard

```markdown
## Project Status

**Phase:** Phase {current_phase} - {phase_name}
**Position:** {current_position}
**Status:** {status}
**Last Updated:** {last_updated}

### Roadmap Progress

- [x] Phase 1: Discover - complete
- [ ] Phase 2: Define - in_progress  <-- YOU ARE HERE
- [ ] Phase 3: Develop - not_started
- [ ] Phase 4: Deliver - not_started

### Current Phase Details

**Phase 2: Define (Grasp)**
- **Goal:** Clarify requirements and scope
- **Position:** {current_position}
- **Status:** {status}

### Blockers

{blockers or "None"}

### Suggested Next Action

{intelligent routing based on status}
```

#### Step 2: Determine Phase Completion Status

Map `current_phase` and `status` to completion markers:

| Phase | Status | Marker |
|-------|--------|--------|
| 1 | complete | `[x] Phase 1: Discover - complete` |
| 2 | in_progress | `[ ] Phase 2: Define - in_progress  <-- YOU ARE HERE` |
| 3 | not_started | `[ ] Phase 3: Develop - not_started` |
| 4 | not_started | `[ ] Phase 4: Deliver - not_started` |

---

### Phase 5: Intelligent Routing

#### Step 1: Map Status to Suggestion

Use this routing table:

| Status | Suggestion |
|--------|-----------|
| `ready` | "Run `/octo:embrace [description]` to start the workflow" |
| `planning` | "Continue planning in current phase. Use `/octo:define` to refine requirements." |
| `building` | "Continue implementation. Use `/octo:develop` to build features." |
| `in_progress` | "Continue with current phase. Check .octo/phases/phase{N}/ for details." |
| `blocked` | "Review blockers above. Use `/octo:issues` to track and resolve issues." |
| `complete` | "Phase complete. Proceed to next phase or run `/octo:ship` to finalize." |
| `complete_with_gaps` | "Phase complete with known gaps. Review .octo/ISSUES.md before proceeding." |
| `shipped` | "Project delivered! Review .octo/LESSONS.md for retrospective." |
| `paused` | "Project paused. Resume with `/octo:embrace` or check .octo/STATE.md for context." |

#### Step 2: Phase-Specific Routing

If `status=in_progress`, provide phase-specific guidance:

**Phase 1 (Discover):**
```
Continue research and exploration.
- Use `/octo:research [topic]` for multi-AI research
- Use `/octo:debate [question]` for decision support
```

**Phase 2 (Define):**
```
Continue requirements clarification.
- Use `/octo:prd` to write product requirements
- Use `/octo:define` to refine scope
```

**Phase 3 (Develop):**
```
Continue implementation.
- Use `/octo:develop` to build features
- Use `/octo:tdd` for test-driven development
- Use `/octo:review` for code quality checks
```

**Phase 4 (Deliver):**
```
Continue validation and delivery.
- Use `/octo:deliver` for final review
- Use `/octo:security` for security audit
- Use `/octo:ship` to finalize delivery
```

---

## Example Outputs

### Example 1: Project Not Initialized

```markdown
## Project Status

**Status:** Not initialized

No Claude Octopus project found in this directory.

### Get Started

Run `/octo:embrace [your project description]` to initialize a new project and start the Double Diamond workflow.

**Example:**
```
/octo:embrace build a user authentication system
```
```

---

### Example 2: Active Project in Define Phase

```markdown
## Project Status

**Phase:** Phase 2 - Define (Grasp)
**Position:** define-requirements
**Status:** in_progress
**Last Updated:** 2026-02-02T10:30:00Z

### Roadmap Progress

- [x] Phase 1: Discover - complete
- [ ] Phase 2: Define - in_progress  <-- YOU ARE HERE
- [ ] Phase 3: Develop - not_started
- [ ] Phase 4: Deliver - not_started

### Current Phase Details

**Phase 2: Define (Grasp)**
- **Goal:** Clarify requirements and scope
- **Position:** define-requirements
- **Status:** in_progress

### Blockers

None

### Suggested Next Action

Continue requirements clarification.
- Use `/octo:prd` to write product requirements
- Use `/octo:define` to refine scope
- Check `.octo/phases/phase2/` for detailed plans
```

---

### Example 3: Blocked Project

```markdown
## Project Status

**Phase:** Phase 3 - Develop (Tangle)
**Position:** implement-auth
**Status:** blocked
**Last Updated:** 2026-02-02T14:15:00Z

### Roadmap Progress

- [x] Phase 1: Discover - complete
- [x] Phase 2: Define - complete
- [ ] Phase 3: Develop - blocked  <-- YOU ARE HERE
- [ ] Phase 4: Deliver - not_started

### Current Phase Details

**Phase 3: Develop (Tangle)**
- **Goal:** Implement features
- **Position:** implement-auth
- **Status:** blocked

### Blockers

- Missing OAuth provider credentials
- Database schema not finalized
- API rate limiting not configured

### Suggested Next Action

Review blockers above. Use `/octo:issues` to track and resolve issues.

**To unblock:**
1. Configure OAuth credentials in .env
2. Finalize database schema with `/octo:define`
3. Set up rate limiting configuration
```

---

### Phase 6: Recent Activity Summary (Cross-Session)

When the user asks "what have I been working on", "summarize recent work", or "update project memory", generate a cross-session activity summary.

#### Step 1: Gather Recent Activity

```bash
# Check if we're inside a git repository
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # Recent git commits (last 7 days or last 20 commits)
    git log --oneline --since="7 days ago" --no-merges 2>/dev/null | head -20

    # Recent tags/releases
    git tag --sort=-creatordate | head -5

    # Recent branches worked on
    git branch --sort=-committerdate | head -5
else
    echo "Not a git repository; skipping git activity summary."
fi

# Recent orchestration results (if any)
ls -lt ~/.claude-octopus/results/ 2>/dev/null | head -10
```

#### Step 2: Summarize Activity

Build a concise summary grouped by theme:

```markdown
## Recent Activity (Last 7 Days)

### Commits
- [theme 1]: brief summary of related commits
- [theme 2]: brief summary of related commits

### Releases
- v8.10.0 - Gemini CLI headless fix
- v8.9.0 - Contextual Codex model routing

### Active Branches
- main (current)

### Orchestration Sessions
- [count] workflows executed, [count] synthesis files generated
```

#### Step 3: Suggest CLAUDE.md Updates

If the recent activity reveals patterns not captured in `CLAUDE.md`, suggest specific additions:

```markdown
### Suggested CLAUDE.md Updates

Based on recent activity, consider adding:
- [specific suggestion based on new patterns, conventions, or decisions]
- [specific suggestion based on new tooling or workflow changes]
```

**Only suggest updates that reflect durable project knowledge** (conventions, architecture decisions, provider configs) — NOT transient status like "currently working on X".

---

## Integration with Other Skills

### With flow-* skills

```
User asks "what's next?"
→ skill-status shows current phase
→ User runs /octo:develop to continue
```

### With skill-task-management

```
User asks "show status"
→ skill-status displays dashboard
→ skill-task-management shows active todos
```

### With /octo:embrace

```
User asks "status" but no .octo/ exists
→ skill-status suggests /octo:embrace
→ User initializes new project
```

---

## Best Practices

### 1. Always Check for .octo/ First

**Good:**
```bash
if [[ ! -d ".octo" ]]; then
    echo "Not initialized"
    exit 1
fi
```

**Poor:**
```bash
# Assume .octo/ exists and fail later
cat .octo/STATE.md
```

### 2. Use octo-state.sh for State Reading

**Good:**
```bash
./scripts/octo-state.sh read_state
```

**Poor:**
```bash
# Parse STATE.md manually
grep "Current Phase" .octo/STATE.md
```

### 3. Provide Actionable Next Steps

**Good:**
```
Continue with `/octo:develop` to implement features.
Check `.octo/phases/phase3/` for implementation plan.
```

**Poor:**
```
You're in phase 3.
```

---

## Red Flags - Don't Do This

| Action | Why It's Wrong |
|--------|----------------|
| Modify STATE.md directly | Use octo-state.sh write_state instead |
| Skip .octo/ existence check | Will fail with confusing errors |
| Show status without next action | User doesn't know what to do |
| Hardcode phase names | Read from ROADMAP.md for accuracy |
| Ignore blockers | User needs to know what's blocking progress |

---

## Quick Reference

| User Input | Action Required |
|------------|-----------------|
| "status" | Check .octo/ → Read state → Display dashboard |
| "what's next" | Read state → Route based on status/phase |
| "where am I" | Display current phase and position |
| "show progress" | Display roadmap with completion markers |
| "any blockers" | Extract and display blockers from STATE.md |
| "what have I been working on" | Git log + results → Cross-session activity summary |
| "update project memory" | Activity summary → Suggest CLAUDE.md additions |

---

## The Bottom Line

```
Status check → Read state + roadmap → Display dashboard + intelligent routing
Otherwise → User doesn't know where they are or what to do next
```

**Check initialization. Read state. Display clearly. Route intelligently.**
