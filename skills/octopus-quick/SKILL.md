---
name: octopus-quick
version: 1.0.0
description: "Fast-track execution for small, well-understood tasks that skip full Double Diamond workflow overhead. Use when: user says 'quick fix', 'ad-hoc task', runs /octo:quick, or requests a simple bug fix, config change, typo correction, or dependency update without multi-AI orchestration."
---

# Quick Mode - Lightweight Task Execution

Streamlined execution for small tasks: `User Request -> Direct Implementation -> Atomic Commit -> Summary`

Skips multi-AI research, requirements planning, and multi-AI validation. Keeps state tracking, atomic commits, and summary generation.

## When to Use

**Use for**: One-file bug fixes, typo corrections, config changes, dependency updates, small refactorings, docstring updates.

**Do NOT use for**: New features, architecture changes, multi-file refactorings, security-sensitive changes, database schema changes, API contract changes. Escalate these to full workflows.

## Usage

```bash
/octo:quick "fix typo in README"
/octo:quick "update Next.js to v15"
/octo:quick "fix the broken import in auth.ts"
```

## Execution Steps

### Step 1: Assess the Task
Identify file(s), specific change, and dependencies/side effects.

### Step 2: Implement Directly
Use Edit, Write, or Bash tools as appropriate.

### Step 3: Atomic Commit

```bash
git add [changed-files]
git commit -m "quick: [brief description]

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

### Step 4: Record in State

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" write_decision "quick" "$(git log -1 --pretty=%s)" "Ad-hoc task executed in quick mode"
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_metrics "execution_time" "1"
```

### Step 5: Generate Summary

Save to `.claude-octopus/quick/YYYYMMDD-HHMMSS-summary.md` with task description, changes, files modified, commit hash, and timestamp.

## Escalation

If the task turns out more complex than expected, stop and suggest full workflow:
- `/octo:discover` for research
- `/octo:define` for planning
- `/octo:develop` for building
- `/octo:deliver` for validation

**Escalation triggers**: Multiple files need changes, architectural decisions required, security/performance implications, breaking changes.

## Quick Mode vs Full Workflow

| Aspect | Quick Mode | Full Workflow |
|--------|-----------|---------------|
| Time | 1-3 min | 5-15 min |
| Cost | Claude only | Codex + Gemini + Claude |
| Research | None | Comprehensive |
| Validation | Basic | Multi-AI review |
| Best for | Known solutions | Unknown solutions |
