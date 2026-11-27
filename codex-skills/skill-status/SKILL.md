---
name: skill-status
description: "Show where you are in the workflow and what to do next — use for progress checks and orientation"
disable-model-invocation: true
---

> **Host: Codex CLI** — This skill was designed for Claude Code and adapted for Codex.
> Invoke installed skills by their `$skill-name`. Known Octopus commands are mapped below. A remaining `/octo:*` reference is a Claude Code command; do not execute it in Codex or invent an equivalent.
> Before the first helper call, derive the absolute plugin root from this loaded skill's path by finding its ancestor containing `.codex-plugin/plugin.json`. Verify that root, bind `OCTO_ROOT`, `CODEX_PLUGIN_ROOT`, and `CLAUDE_PLUGIN_ROOT` to the same root, and export all three in each fresh shell before launching child processes. Use the verified absolute helper path when needed. Do not infer the root from the user's project or assume exports survive tool calls. Stop and report a missing installation if the root cannot be verified.
> Use the active Codex shell and subagent tools. Do not claim a provider, model, or host subagent is available until the current session exposes it.
> Claude-native tool calls in examples are prompt templates to adapt, not Codex call signatures. If a mandatory verification agent or tool is unavailable or unauthorized, report that verification did not run and stop the affected completion step. Never claim a skipped check passed.
> Attribute commits only to actual contributors; do not copy fixed model attribution trailers from examples.
> For host tool equivalents, see `codex-skills/blocks/codex-host-adapter.md`.

> Invoke this entry as `$skill-status` in Codex. Code-fenced Claude command examples are reference text, not Codex shell commands.


# Project Status Dashboard

## Overview

Display current project status, roadmap progress, blockers, and intelligent next-action suggestions based on workflow state.

**Core principle:** Read state → Display dashboard → Route intelligently.


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


## The Process

### Phase 1: Read Current State

Run this read-only check from the project directory. It reads the project
dashboard state when `.octo/STATE.md` exists, or the checkout's workflow
state when there is no project state file.

```bash
plugin_root="${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}}"
if [[ -f .octo/STATE.md ]]; then
    if [[ ! -r .octo/STATE.md ]]; then
        printf '%s\n' 'Cannot read .octo/STATE.md.' >&2
        exit 1
    fi
    "$plugin_root/scripts/octo-state.sh" read_state
else
    workflow_state=$("$plugin_root/bin/octopus" state-path) || exit 1
    if [[ -e "$workflow_state" || -L "$workflow_state" ]]; then
        OCTOPUS_STATE_PROJECT_ROOT="$PWD" "$plugin_root/scripts/state-manager.sh" show_summary
    elif [[ -d .octo ]]; then
        printf '%s\n' 'Project state is missing from .octo/STATE.md.' >&2
        exit 1
    else
        printf '%s\n' 'No project initialized.' >&2
        exit 1
    fi
fi
```

If the check says "No project initialized," suggest starting a workflow in
this checkout. For any other error, report the read failure. Stop the dashboard
on either error.

If the check returns a workflow summary, report the saved workflow, phase and
active blocker count. Use a project roadmap only if one exists. The workflow
summary has no project status or position fields. Recommend a next action from
the saved phase when it supplies enough context.

The project dashboard state uses key-value output:
```
schema=1.0
last_updated=2026-02-02T10:30:00Z
current_phase=2
current_position=define-requirements
status=in_progress
```

Extract key-value pairs:
- `current_phase` - Phase number (1-4)
- `current_position` - Specific position within phase
- `status` - Current workflow status
- `last_updated` - Last state modification timestamp


### Phase 2: Read Roadmap

Read `.octo/ROADMAP.md` when it exists. Otherwise, omit roadmap progress.

```bash
if [[ -f .octo/ROADMAP.md ]]; then
    cat .octo/ROADMAP.md
fi
```

Parse ROADMAP.md to identify:
- Phase names (Discover, Define, Develop, Deliver)
- Phase descriptions
- Success criteria for each phase
- Dependencies between phases


### Phase 3: Display Dashboard

#### Step 1: Build Status Dashboard

Use the fields that the check returned. This example shows a project with a
saved roadmap:

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


### Phase 4: Intelligent Routing

#### Step 1: Map Status to Suggestion

Use this routing table when the project state reader returns a status. For
workflow state, use the reported phase and blockers to guide the next action.

| Status | Suggestion |
|--------|-----------|
| `ready` | "Run `/octo:embrace [description]` to start the workflow" |
| `planning` | "Continue planning in current phase. Use `$flow-define` to refine requirements." |
| `building` | "Continue implementation. Use `$flow-develop` to build features." |
| `in_progress` | "Continue with current phase. Check .octo/phases/phase{N}/ for details." |
| `blocked` | "Review blockers above. Use `$skill-issues` to track and resolve issues." |
| `complete` | "Phase complete. Proceed to next phase or run `$skill-ship` to finalize." |
| `complete_with_gaps` | "Phase complete with known gaps. Review .octo/ISSUES.md before proceeding." |
| `shipped` | "Project delivered! Review .octo/LESSONS.md for retrospective." |
| `paused` | "Project paused. Resume with `/octo:embrace` or check .octo/STATE.md for context." |

#### Step 2: Phase-Specific Routing

If `status=in_progress`, provide phase-specific guidance:

**Phase 1 (Discover):**
```
Continue research and exploration.
- Use `$octopus-research [topic]` for multi-AI research
- Use `$skill-debate [question]` for decision support
```

**Phase 2 (Define):**
```
Continue requirements clarification.
- Use `$skill-prd` to write product requirements
- Use `$flow-define` to refine scope
```

**Phase 3 (Develop):**
```
Continue implementation.
- Use `$flow-develop` to build features
- Use `$skill-tdd` for test-driven development
- Use `$skill-code-review` for code quality checks
```

**Phase 4 (Deliver):**
```
Continue validation and delivery.
- Use `$flow-deliver` for final review
- Use `$octopus-security-audit` for security audit
- Use `$skill-ship` to finalize delivery
```


## Example Outputs

### Example 1: Project Not Initialized

```markdown
## Project Status

**Status:** Not initialized

Start a Claude Octopus workflow in this checkout to create workflow state.
```


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
- Use `$skill-prd` to write product requirements
- Use `$flow-define` to refine scope
- Check `.octo/phases/phase2/` for detailed plans
```


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

Review blockers above. Use `$skill-issues` to track and resolve issues.

**To unblock:**
1. Configure OAuth credentials in .env
2. Finalize database schema with `$flow-define`
3. Set up rate limiting configuration
```


### Phase 5: Recent Activity Summary (Cross-Session)

When the user asks "what have I been working on", "summarize recent work", or "update project memory", generate a cross-session activity summary.

#### Step 1: Gather Recent Activity

```bash
# Recent git commits (last 7 days or last 20 commits)
git log --oneline --since="7 days ago" --no-merges 2>/dev/null | head -20

# Recent tags/releases
git tag --sort=-creatordate | head -5

# Recent branches worked on
git branch --sort=-committerdate | head -5

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
- v8.10.0 - Antigravity CLI headless fix
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


## Integration with Other Skills

### With flow-* skills

```
User asks "what's next?"
→ skill-status shows current phase
→ User runs $flow-develop to continue
```

### With skill-task-management

```
User asks "show status"
→ skill-status displays dashboard
→ skill-task-management shows active todos
```

### With /octo:embrace

```
User asks "status" and neither project nor workflow state exists
→ skill-status suggests starting a workflow in this checkout
```


## Best Practices

### 1. Use the Installed State Readers

Use `octo-state.sh read_state` for project state and
`state-manager.sh show_summary` for workflow state.

### 2. Provide Actionable Next Steps

**Good:**
```
Continue with `$flow-develop` to implement features.
Check `.octo/phases/phase3/` for implementation plan.
```

**Poor:**
```
You're in phase 3.
```


## Red Flags - Don't Do This

| Action | Why It's Wrong |
|--------|----------------|
| Modify STATE.md directly | Use octo-state.sh write_state instead |
| Assume all state lives in .octo/ | Workspace-only workflows lose their dashboard |
| Show status without next action | User doesn't know what to do |
| Hardcode phase names | Read from ROADMAP.md for accuracy |
| Ignore blockers | User needs to know what's blocking progress |


## Quick Reference

| User Input | Action Required |
|------------|-----------------|
| "status" | Read project or workflow state → Display available fields |
| "what's next" | Read state → Route based on status/phase |
| "where am I" | Display current phase and position |
| "show progress" | Display roadmap with completion markers |
| "any blockers" | Extract and display blockers from STATE.md |
| "what have I been working on" | Git log + results → Cross-session activity summary |
| "update project memory" | Activity summary → Suggest CLAUDE.md additions |


## The Bottom Line

```
Status check → Read state + roadmap → Display dashboard + intelligent routing
Otherwise → User doesn't know where they are or what to do next
```

**Check initialization. Read state. Display clearly. Route intelligently.**
