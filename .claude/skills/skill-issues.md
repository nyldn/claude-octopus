---
name: skill-issues
aliases:
  - issues
  - issue-tracking
description: Track and manage project issues across sessions
trigger: |
  AUTOMATICALLY ACTIVATE when user mentions:
  - "issue" or "issues" or "problem"
  - "track this" or "remember this blocker"
  - "add issue" or "create issue"
  - "resolve issue" or "close issue"
  - "show issues" or "list issues"
  
  DO NOT activate for:
  - Git issues (use git commands)
  - GitHub issues (use gh CLI)
  - General problem-solving without tracking
argument-hint: "[list|add|resolve|show] [description or ID]"
---

# Issue Tracking

## Overview

Cross-session issue tracking for persistent problem management. Issues are stored in `.octo/ISSUES.md` and survive across Claude Code sessions.

**Core principle:** Track → Resolve → Learn.

---

## When to Use

**Use this skill when user wants to:**
- Track a problem or blocker for later
- Record issues discovered during development
- Review open issues across sessions
- Mark issues as resolved
- View details of specific issues

**Do NOT use for:**
- GitHub issue management (use gh CLI)
- Git-tracked issues (use git commands)
- Temporary todos (use TodoWrite)

---

## Subcommands

### 1. List Issues (Default)

**Trigger:** `/octo:issues` or `/octo:issues list`

Show all open issues in table format:

```markdown
## Open Issues

| ID | Severity | Description | Created | Phase |
|----|----------|-------------|---------|-------|
| ISS-20260203-001 | high | Auth not working | 2026-02-03 | Develop |
| ISS-20260203-002 | medium | Slow query performance | 2026-02-03 | Deliver |
```

**Implementation:**
1. Check if `.octo/ISSUES.md` exists
2. If not, initialize from template
3. Read and parse Open Issues section
4. Display in table format

---

### 2. Add Issue

**Trigger:** `/octo:issues add <description>`

Add new issue with auto-generated ID.

**Flow:**

#### Step 1: Gather Information

```markdown
**Adding new issue:** [description]

Please provide:
1. **Severity** (critical/high/medium/low):
2. **Additional context** (optional):
```

#### Step 2: Validate Severity

Ensure severity is one of: `critical`, `high`, `medium`, `low`

If invalid, ask again.

#### Step 3: Determine Current Phase

```bash
# Check if STATE.md exists
if [ -f .octo/STATE.md ]; then
  grep "current_phase:" .octo/STATE.md
else
  echo "Unknown"
fi
```

#### Step 4: Generate Issue ID

**Format:** `ISS-YYYYMMDD-NNN`

```bash
# Get today's date
TODAY=$(date +%Y%m%d)

# Find existing issues for today
grep "ISS-${TODAY}-" .octo/ISSUES.md | tail -1

# Increment sequence number
# If ISS-20260203-001 exists, next is ISS-20260203-002
```

#### Step 5: Append to ISSUES.md

Add new row to Open Issues table:

```markdown
| ISS-20260203-003 | medium | Slow query performance | 2026-02-03 | Develop |
```

**Preserve existing issues** - append only, don't overwrite.

#### Step 6: Confirm

```markdown
✅ Issue created: ISS-20260203-003

**Severity:** medium
**Description:** Slow query performance
**Created:** 2026-02-03
**Phase:** Develop

View with: /octo:issues show ISS-20260203-003
```

---

### 3. Resolve Issue

**Trigger:** `/octo:issues resolve <id>`

Mark issue as resolved and move to Resolved section.

**Flow:**

#### Step 1: Validate Issue Exists

```bash
# Check if issue ID exists in Open Issues
grep "ISS-20260203-001" .octo/ISSUES.md
```

If not found, show error:

```markdown
❌ Issue ISS-20260203-001 not found in open issues.

Use `/octo:issues list` to see all open issues.
```

#### Step 2: Ask for Resolution Notes

```markdown
**Resolving issue:** ISS-20260203-001

Please provide resolution notes:
```

#### Step 3: Move to Resolved Section

1. Extract issue row from Open Issues table
2. Remove from Open Issues
3. Add to Resolved Issues with resolution date and notes

**Resolved Issues format:**

```markdown
| ID | Severity | Description | Created | Resolved | Resolution |
|----|----------|-------------|---------|----------|------------|
| ISS-20260203-001 | high | Auth not working | 2026-02-03 | 2026-02-04 | Fixed OAuth token refresh |
```

#### Step 4: Confirm

```markdown
✅ Issue resolved: ISS-20260203-001

**Resolution date:** 2026-02-04
**Resolution notes:** Fixed OAuth token refresh

View with: /octo:issues show ISS-20260203-001
```

---

### 4. Show Issue Details

**Trigger:** `/octo:issues show <id>`

Display full details of specific issue.

**Flow:**

#### Step 1: Find Issue

Search both Open and Resolved sections for issue ID.

#### Step 2: Display Details

**For open issue:**

```markdown
## Issue Details: ISS-20260203-001

**Status:** Open
**Severity:** high
**Description:** Auth not working
**Created:** 2026-02-03
**Phase:** Develop

**Actions:**
- Resolve: `/octo:issues resolve ISS-20260203-001`
```

**For resolved issue:**

```markdown
## Issue Details: ISS-20260203-001

**Status:** Resolved
**Severity:** high
**Description:** Auth not working
**Created:** 2026-02-03
**Resolved:** 2026-02-04
**Resolution:** Fixed OAuth token refresh
```

#### Step 3: If Not Found

```markdown
❌ Issue ISS-20260203-001 not found.

Use `/octo:issues list` to see all open issues.
```

---

## File Management

### Initialize ISSUES.md

**When:** First time skill is used or `.octo/ISSUES.md` doesn't exist.

**Action:**

```bash
# Create .octo directory if needed
mkdir -p .octo

# Copy template
cp ${CLAUDE_PLUGIN_ROOT}/templates/ISSUES.md.template .octo/ISSUES.md

# Replace {{PROJECT_NAME}} with actual project name
PROJECT_NAME=$(basename $(pwd))
sed -i '' "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" .octo/ISSUES.md
```

### Preserve Existing Issues

**CRITICAL:** When adding or resolving issues, NEVER overwrite existing content.

**Pattern:**

```bash
# Read existing content
EXISTING=$(cat .octo/ISSUES.md)

# Modify specific section only
# Append new issue to Open Issues table
# OR move issue from Open to Resolved

# Write back with all content preserved
echo "$MODIFIED" > .octo/ISSUES.md
```

---

## ID Generation Algorithm

**Format:** `ISS-YYYYMMDD-NNN`

**Example:** `ISS-20260203-001`

**Implementation:**

```bash
#!/bin/bash

# Get today's date in YYYYMMDD format
TODAY=$(date +%Y%m%d)

# Find all issues created today
TODAY_ISSUES=$(grep -o "ISS-${TODAY}-[0-9]\{3\}" .octo/ISSUES.md || echo "")

if [ -z "$TODAY_ISSUES" ]; then
  # No issues today, start at 001
  NEXT_NUM="001"
else
  # Get highest number for today
  HIGHEST=$(echo "$TODAY_ISSUES" | sed "s/ISS-${TODAY}-//" | sort -n | tail -1)
  
  # Increment
  NEXT_NUM=$(printf "%03d" $((10#$HIGHEST + 1)))
fi

# Generate ID
ISSUE_ID="ISS-${TODAY}-${NEXT_NUM}"
echo "$ISSUE_ID"
```

---

## Severity Levels

| Level | Meaning | Example |
|-------|---------|---------|
| **critical** | Blocks all progress | Production down, data loss |
| **high** | Significant impact | Feature broken, security issue |
| **medium** | Should address | Performance degradation, UX issue |
| **low** | Nice to fix | Minor bug, cosmetic issue |

---

## Integration with Other Skills

### With skill-debug

```
User: "track this bug for later"

1. Use skill-issues to create issue
2. Use skill-debug to investigate if time permits
3. Link issue ID in debug notes
```

### With skill-task-management

```
User: "add fixing ISS-20260203-001 to todos"

1. Use skill-task-management to add todo
2. Reference issue ID in todo description
3. Mark issue as resolved when todo completes
```

### With flow-develop

```
User: "implement fix for ISS-20260203-001"

1. Use flow-develop to implement fix
2. Use skill-issues to resolve issue after fix
3. Link commit SHA in resolution notes
```

---

## Best Practices

### 1. Clear Descriptions

**Good:**
```
Auth token refresh fails after 15 minutes
```

**Poor:**
```
Auth broken
```

### 2. Appropriate Severity

**Critical:** Only for blockers that stop all work
**High:** Significant but workarounds exist
**Medium:** Should fix but not urgent
**Low:** Nice to have

### 3. Resolution Notes

**Good:**
```
Fixed OAuth token refresh by updating expiration logic in auth.ts
Commit: abc123
```

**Poor:**
```
Fixed
```

---

## Common Patterns

### Pattern 1: Track During Development

```
User: "track this issue: API rate limiting not working"

Action:
1. Create issue with appropriate severity
2. Record current phase from STATE.md
3. Continue development
```

### Pattern 2: Resolve After Fix

```
User: "resolve ISS-20260203-001, fixed in commit abc123"

Action:
1. Ask for resolution notes
2. Move to Resolved section
3. Record resolution date and notes
```

### Pattern 3: Review Open Issues

```
User: "what issues do we have?"

Action:
1. List all open issues
2. Show severity and phase
3. Offer to show details or resolve
```

---

## Red Flags - Don't Do This

| Action | Why It's Wrong |
|--------|----------------|
| Overwrite ISSUES.md | Lose all existing issues |
| Skip severity validation | Invalid data in file |
| Duplicate issue IDs | ID collision |
| Vague descriptions | Can't remember what issue was |
| Resolve without notes | No record of what was done |

---

## Quick Reference

| User Intent | Skill Action | Output |
|-------------|--------------|--------|
| "list issues" | Read and display Open Issues | Table of issues |
| "add issue X" | Generate ID, append to file | Issue created |
| "resolve ISS-X" | Move to Resolved section | Issue resolved |
| "show ISS-X" | Find and display details | Issue details |

---

## The Bottom Line

```
Issue tracking → Persistent memory across sessions
Otherwise → Forget problems, repeat mistakes
```

**Track everything. Resolve systematically. Learn from history.**
