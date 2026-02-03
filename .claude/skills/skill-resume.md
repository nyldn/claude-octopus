---
name: skill-resume
description: Restore context from previous session and continue workflow
trigger: |
  AUTOMATICALLY ACTIVATE when user mentions:
  - "resume" or "continue" or "pick up where I left off"
  - "what was I doing" or "restore session"
---

# Session Restoration

## Overview

Restore context from a previous session and seamlessly continue the workflow where you left off.

**Core principle:** Check state → Load adaptive context → Display restoration summary → Route to appropriate action.

---

## When to Use

**Use this skill when user says:**
- "Resume" or "continue working"
- "Pick up where I left off"
- "What was I doing?"
- "Restore session"
- "Continue from last time"

**Do NOT use for:**
- Starting new projects (use /octo:embrace)
- Checking current status only (use /octo:status)
- Modifying state directly (use octo-state.sh)

---

## The Process

### Phase 1: Check Project Initialization

#### Step 1: Verify .octo/ Directory Exists

```bash
if [[ ! -d ".octo" ]]; then
    echo "No project state found"
    exit 1
fi
```

**If .octo/ does not exist, display:**

```markdown
## Session Restoration Failed

**No project state found.**

There is no `.octo/` directory in this project, which means no previous session state exists.

### Get Started

Run `/octo:embrace [your project description]` to start a new project.

**Example:**
```
/octo:embrace build a REST API with user authentication
```

This will:
1. Initialize .octo/ directory with STATE.md, PROJECT.md, ROADMAP.md
2. Begin the Double Diamond workflow
3. Create session state you can resume later
```

**Stop here** - do not proceed to Phase 2.

---

### Phase 2: Read Current State

#### Step 1: Execute octo-state.sh read_state

```bash
./scripts/octo-state.sh read_state
```

**Expected output format:**
```
schema=2.0
last_updated=2026-02-02T10:30:00Z
current_phase=2
current_position=define-requirements
status=in_progress
```

#### Step 2: Parse State Variables

Extract these key values:
- `current_phase` - Phase number (1-4)
- `current_position` - Description of current position within phase
- `status` - Workflow status (in_progress, blocked, complete, paused, etc.)
- `last_updated` - Timestamp of last state modification

---

### Phase 3: Load Adaptive Context

#### Step 1: Get Context Tier (Auto Mode)

```bash
./scripts/octo-state.sh get_context_tier auto
```

This automatically selects the appropriate context tier based on current status:

| Status | Tier Selected | Context Loaded |
|--------|---------------|----------------|
| ready, planned, planning, complete, shipped | planning | STATE.md + PROJECT.md + ROADMAP.md |
| building, in_progress | execution | + phase plans + recent summaries |
| blocked, paused | execution | + phase plans + recent summaries |

#### Step 2: Store Context for Reference

The context returned includes:
- Current state details
- Project vision and requirements
- Phase-specific plans and summaries
- Codebase analysis (if brownfield project)

---

### Phase 4: Extract History and Blockers

#### Step 1: Read Last 3 History Entries from STATE.md

```bash
# Extract history section from STATE.md
grep -A 4 "^## History" .octo/STATE.md | tail -n 3
```

**Expected format:**
```
- [2026-02-02T10:30:00Z] Phase 2: Completed requirements review (complete)
- [2026-02-02T09:15:00Z] Phase 2: Started define phase (in_progress)
- [2026-02-01T16:45:00Z] Phase 1: Completed discovery (complete)
```

#### Step 2: Extract Blockers from STATE.md

```bash
# Extract blockers section
sed -n '/^## Blockers/,/^## /p' .octo/STATE.md | head -n -1 | tail -n +2
```

**Expected format:**
- If blockers exist: List of blocker items
- If no blockers: `(none)`

#### Step 3: Read Project Title from PROJECT.md

```bash
# Get project title (first H1)
head -n 5 .octo/PROJECT.md | grep "^# " | head -1 | sed 's/^# //'
```

---

### Phase 5: Display Restoration Summary

#### Step 1: Build and Display Summary

```markdown
## Session Restored

**Project:** {project_title from PROJECT.md}
**Last Active:** {last_updated from STATE.md}
**Phase:** {current_phase} - {phase_name}
**Position:** {current_position}
**Status:** {status}

### Where You Left Off

{Last 3 entries from STATE.md history}

### Current Blockers

{Blockers from STATE.md or "None"}

### Ready to Continue

{Intelligent suggestion based on status - see routing table below}
```

#### Step 2: Map Phase Number to Name

| Phase | Name |
|-------|------|
| 1 | Discover |
| 2 | Define |
| 3 | Develop |
| 4 | Deliver |

---

### Phase 6: Intelligent Routing

#### Step 1: Route Based on Status

| Status | Action | Message |
|--------|--------|---------|
| `in_progress` | Continue current phase | "Continue with current phase. Context loaded." |
| `blocked` | Review blockers | "Review blockers first: `/octo:issues`" |
| `complete` | Ready for next phase | "Phase complete. Ready for `/octo:ship`" |
| `paused` | Resume project | "Project paused. Resume with `/octo:embrace`" |
| `ready` | Begin workflow | "Ready to begin. Run `/octo:embrace` to start." |
| `planning` | Continue planning | "Continue planning. Use `/octo:define` to refine." |
| `building` | Continue building | "Continue implementation. Use `/octo:develop`." |
| `shipped` | Project delivered | "Project delivered! Review lessons in LESSONS.md." |
| `complete_with_gaps` | Review gaps | "Phase complete with gaps. Review ISSUES.md before proceeding." |

#### Step 2: Phase-Specific Guidance (for in_progress status)

**Phase 1 (Discover):**
```
Continue research and exploration.
- Use `/octo:research [topic]` for multi-AI research
- Use `/octo:debate [question]` for decision support
- Check `.octo/phases/phase1/` for research notes
```

**Phase 2 (Define):**
```
Continue requirements clarification.
- Use `/octo:prd` to write product requirements
- Use `/octo:define` to refine scope
- Check `.octo/phases/phase2/` for requirements docs
```

**Phase 3 (Develop):**
```
Continue implementation.
- Use `/octo:develop` to build features
- Use `/octo:tdd` for test-driven development
- Check `.octo/phases/phase3/` for implementation plan
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

### Example 1: No Project State Found

```markdown
## Session Restoration Failed

**No project state found.**

There is no `.octo/` directory in this project, which means no previous session state exists.

### Get Started

Run `/octo:embrace [your project description]` to start a new project.
```

---

### Example 2: Successful Restoration (In Progress)

```markdown
## Session Restored

**Project:** User Authentication System
**Last Active:** 2026-02-02T10:30:00Z
**Phase:** 2 - Define
**Position:** define-requirements
**Status:** in_progress

### Where You Left Off

- [2026-02-02T10:30:00Z] Phase 2: Started requirements review (in_progress)
- [2026-02-01T16:45:00Z] Phase 1: Completed discovery (complete)
- [2026-02-01T14:20:00Z] Phase 1: Research synthesis complete (in_progress)

### Current Blockers

None

### Ready to Continue

Continue with current phase. Context loaded.

Continue requirements clarification.
- Use `/octo:prd` to write product requirements
- Use `/octo:define` to refine scope
- Check `.octo/phases/phase2/` for requirements docs
```

---

### Example 3: Blocked Project Restoration

```markdown
## Session Restored

**Project:** E-commerce Platform
**Last Active:** 2026-02-01T18:00:00Z
**Phase:** 3 - Develop
**Position:** implement-payment-gateway
**Status:** blocked

### Where You Left Off

- [2026-02-01T18:00:00Z] Phase 3: Payment integration blocked (blocked)
- [2026-02-01T15:30:00Z] Phase 3: Started payment gateway integration (in_progress)
- [2026-02-01T12:00:00Z] Phase 3: Completed user auth implementation (complete)

### Current Blockers

- Missing Stripe API credentials
- Payment webhook endpoint not configured
- SSL certificate pending for payment domain

### Ready to Continue

Review blockers first: `/octo:issues`

**To unblock:**
1. Configure Stripe API credentials in environment
2. Set up webhook endpoint at /api/webhooks/stripe
3. Complete SSL certificate setup for payments subdomain
```

---

### Example 4: Paused Project Restoration

```markdown
## Session Restored

**Project:** Data Analytics Dashboard
**Last Active:** 2026-01-28T09:00:00Z
**Phase:** 2 - Define
**Position:** requirements-gathering
**Status:** paused

### Where You Left Off

- [2026-01-28T09:00:00Z] Phase 2: Project paused by user (paused)
- [2026-01-27T16:00:00Z] Phase 2: Stakeholder feedback pending (in_progress)
- [2026-01-27T10:00:00Z] Phase 1: Discovery complete (complete)

### Current Blockers

- Waiting for stakeholder availability

### Ready to Continue

Project paused. Resume with `/octo:embrace`

When ready to continue:
1. Review `.octo/PROJECT.md` for project context
2. Check `.octo/STATE.md` for pause reason
3. Run `/octo:embrace` to resume workflow
```

---

## Best Practices

### 1. Always Use octo-state.sh for State Reading

**Good:**
```bash
./scripts/octo-state.sh read_state
./scripts/octo-state.sh get_context_tier auto
```

**Poor:**
```bash
# Parse STATE.md manually
grep "Current Phase" .octo/STATE.md
```

### 2. Provide Full Context Restoration

**Good:**
- Load adaptive context tier
- Show last 3 history entries
- Display any blockers
- Give phase-specific guidance

**Poor:**
- Only show current phase
- Ignore history
- No next steps

### 3. Route Intelligently Based on Status

**Good:**
```
Status: blocked → "Review blockers first: /octo:issues"
```

**Poor:**
```
Status: blocked → "Continue working"
```

---

## Red Flags - Don't Do This

| Action | Why It's Wrong |
|--------|----------------|
| Skip .octo/ existence check | Will fail with confusing errors |
| Ignore blockers on resume | User won't know why they stopped |
| Restart from beginning | Loses all previous context and progress |
| Skip history display | User loses continuity of what was done |
| Use hardcoded context tier | Should adapt based on current status |

---

## Integration with Other Skills

### With /octo:status

```
/octo:resume → Full restoration with context
/octo:status → Quick dashboard without restoration
```

### With /octo:embrace

```
No .octo/ exists → /octo:resume suggests /octo:embrace
.octo/ exists but paused → /octo:resume suggests resuming with /octo:embrace
```

### With flow-* skills

```
User runs /octo:resume
→ Context restored
→ User continues with /octo:develop (or appropriate phase skill)
```

---

## Quick Reference

| User Input | Action Required |
|------------|-----------------|
| "resume" | Check .octo/ → Read state → Load context → Display summary → Route |
| "continue" | Same as resume |
| "pick up where I left off" | Same as resume |
| "what was I doing" | Same as resume, emphasize history |
| "restore session" | Same as resume |

---

## The Bottom Line

```
Check .octo/ → Read state → Load adaptive context → Show history + blockers → Route intelligently
Otherwise → User loses previous context and wastes time re-discovering where they were
```

**Never restart from beginning if state exists. Restore context, show history, route intelligently.**
