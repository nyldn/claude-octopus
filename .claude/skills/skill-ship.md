---
name: skill-ship
description: Finalize and deliver completed work with Multi-AI validation
trigger: |
  AUTOMATICALLY ACTIVATE when user mentions:
  - "ship" or "deliver" or "finalize"
  - "done" or "complete the project"
---

# Ship Project - Multi-AI Delivery Validation

Finalize and deliver completed work with Multi-AI security audit, lessons capture, and archival.

**Core principle:** Verify ready -> Multi-AI audit -> Capture lessons -> Archive -> Ship.

---

## When to Use

**Use this skill when user asks:**
- "Ship the project" or "We're done"
- "Finalize this" or "Let's deliver"
- "Complete the project" or "Ready to ship"
- "Mark as shipped" or "Time to deliver"

**Do NOT use for:**
- Code review (use /octo:review or flow-deliver)
- Implementation (use /octo:develop)
- Research (use /octo:research)

---

## The Process

### Phase 1: Verify Project Ready to Ship

#### Step 1: Check .octo/ Exists

```bash
if [[ ! -d ".octo" ]]; then
    echo "No project initialized"
    exit 1
fi
```

**If .octo/ does not exist:**

```markdown
## Cannot Ship

**Status:** No project initialized

No Claude Octopus project found in this directory.

Run `/octo:embrace [description]` to start a new project.
```

**STOP. Do not proceed.**

#### Step 2: Read STATE.md Status

```bash
# Check if STATE.md exists and read status
if [[ -f ".octo/STATE.md" ]]; then
    # Read current status
    STATUS=$(grep -E "^status:" .octo/STATE.md | cut -d':' -f2 | xargs || echo "unknown")
    CURRENT_PHASE=$(grep -E "^current_phase:" .octo/STATE.md | cut -d':' -f2 | xargs || echo "unknown")
else
    STATUS="unknown"
    CURRENT_PHASE="unknown"
fi

echo "Status: $STATUS"
echo "Current Phase: $CURRENT_PHASE"
```

#### Step 3: Validate Ready State

**Ship is allowed when:**
- `status` = "complete" OR
- `current_phase` = "4" (Deliver phase) OR
- All four phases have entries in STATE.md history

**If not ready:**

```markdown
## Project Not Ready to Ship

**Current Status:** {status}
**Current Phase:** {current_phase}

### To prepare for shipping:

1. Complete remaining phases:
   - [ ] Phase 1: Discover - Use `/octo:discover`
   - [ ] Phase 2: Define - Use `/octo:define`
   - [ ] Phase 3: Develop - Use `/octo:develop`
   - [ ] Phase 4: Deliver - Use `/octo:deliver`

2. Or override with: "ship anyway" (not recommended)
```

**STOP unless user says "ship anyway".**

---

### Phase 2: Multi-AI Security Audit

#### Step 1: Display Visual Indicators

```bash
# Check provider availability
command -v codex &> /dev/null && codex_status="Available" || codex_status="Not installed"
command -v gemini &> /dev/null && gemini_status="Available" || gemini_status="Not installed"
```

**Output:**

```markdown
## Multi-AI Security Audit

**Providers:**
- Codex CLI: ${codex_status} - Code security analysis
- Gemini CLI: ${gemini_status} - Edge case and vulnerability detection
- Claude: Available - Synthesis and final validation

**Estimated Time:** 3-5 minutes
**Estimated Cost:** $0.02-0.08
```

#### Step 2: Execute orchestrate.sh Security Audit

**You MUST execute this via Bash tool:**

```bash
# Run Multi-AI security audit for delivery
"${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh" ink "Security audit for delivery - comprehensive review of all code changes for production readiness"
```

**CRITICAL: You are PROHIBITED from:**
- Skipping Multi-AI validation
- Doing single-provider analysis instead
- Claiming you're "simulating" the audit
- Proceeding without running orchestrate.sh

#### Step 3: Verify Audit Completed

```bash
# Find the latest validation file
VALIDATION_FILE=$(find ~/.claude-octopus/results -name "ink-validation-*.md" -mmin -10 2>/dev/null | head -n1)

if [[ -z "$VALIDATION_FILE" ]]; then
    echo "AUDIT FAILED: No validation file found"
    exit 1
fi

echo "AUDIT COMPLETE: $VALIDATION_FILE"
```

#### Step 4: Display Audit Summary

Read validation file and present:
- Overall status (PASSED / PASSED WITH WARNINGS / FAILED)
- Quality score
- Critical issues (must fix before ship)
- Warnings (should fix)

**If FAILED with critical issues:**
```markdown
## Audit Failed - Cannot Ship

Critical issues must be resolved before shipping:

1. [Issue 1 from validation]
2. [Issue 2 from validation]

Resolve issues and run `/octo:ship` again.
```

**STOP if critical issues found.**

---

### Phase 3: Capture Lessons Learned

#### Step 1: Ask User for Lessons

```markdown
## Lessons Learned

Before finalizing, let's capture what we learned from this project.

**Please answer the following:**

1. **What went well?** (What worked better than expected?)

2. **What could improve?** (What would you do differently?)

3. **Key learnings?** (What insights will you carry forward?)

*Reply with your answers, or type "skip" to proceed without capturing lessons.*
```

**Wait for user response.**

#### Step 2: Append to LESSONS.md

If user provides lessons (not "skip"):

```bash
# Generate timestamp
TIMESTAMP=$(date '+%Y-%m-%d')

# Ensure LESSONS.md exists
touch .octo/LESSONS.md

# Append lessons
cat >> .octo/LESSONS.md << EOF

## ${TIMESTAMP} - Project Delivery

### What Went Well
- ${USER_WHAT_WENT_WELL}

### What Could Improve
- ${USER_WHAT_COULD_IMPROVE}

### Key Learnings
- ${USER_KEY_LEARNINGS}

EOF
```

**Count total lessons:**
```bash
LESSON_COUNT=$(grep -c "^## " .octo/LESSONS.md 2>/dev/null || echo "0")
echo "Total lessons captured: $LESSON_COUNT"
```

---

### Phase 4: Archive Project State

#### Step 1: Create Archive Directory

```bash
# Generate timestamp for archive
ARCHIVE_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
ARCHIVE_DIR=".octo/archive/${ARCHIVE_TIMESTAMP}"

# Create archive directory
mkdir -p "$ARCHIVE_DIR"
```

#### Step 2: Copy State Files to Archive

```bash
# Archive STATE.md if exists
if [[ -f ".octo/STATE.md" ]]; then
    cp .octo/STATE.md "$ARCHIVE_DIR/"
fi

# Archive PROJECT.md if exists
if [[ -f ".octo/PROJECT.md" ]]; then
    cp .octo/PROJECT.md "$ARCHIVE_DIR/"
fi

# Archive ROADMAP.md if exists
if [[ -f ".octo/ROADMAP.md" ]]; then
    cp .octo/ROADMAP.md "$ARCHIVE_DIR/"
fi

# Archive ISSUES.md if exists
if [[ -f ".octo/ISSUES.md" ]]; then
    cp .octo/ISSUES.md "$ARCHIVE_DIR/"
fi

echo "Archived to: $ARCHIVE_DIR"
```

**IMPORTANT: NEVER archive LESSONS.md** - lessons are preserved across projects.

#### Step 3: Verify Archive

```bash
# List archived files
ls -la "$ARCHIVE_DIR"
```

---

### Phase 5: Create Delivery Summary

#### Step 1: Update STATE.md

```bash
# Update status to shipped
sed -i '' 's/^status:.*/status: shipped/' .octo/STATE.md 2>/dev/null || \
    sed -i 's/^status:.*/status: shipped/' .octo/STATE.md

# Append history entry
cat >> .octo/STATE.md << EOF

## History - $(date '+%Y-%m-%d %H:%M')

- **Event:** Project shipped
- **Archive:** .octo/archive/${ARCHIVE_TIMESTAMP}/
- **Validation:** ${VALIDATION_FILE}

EOF
```

#### Step 2: Create Shipped Checkpoint

```bash
# Create git checkpoint tag
CHECKPOINT_TAG="octo-checkpoint-shipped-${ARCHIVE_TIMESTAMP}"

git tag -a "$CHECKPOINT_TAG" -m "Project shipped - $(date '+%Y-%m-%d %H:%M:%S')"

echo "Checkpoint created: $CHECKPOINT_TAG"
```

#### Step 3: Count Metrics

```bash
# Count resolved issues
ISSUES_RESOLVED=$(grep -c "^\- \[x\]" .octo/ISSUES.md 2>/dev/null || echo "0")

# Count total lessons
LESSONS_COUNT=$(grep -c "^## " .octo/LESSONS.md 2>/dev/null || echo "0")

echo "Issues resolved: $ISSUES_RESOLVED"
echo "Lessons captured: $LESSONS_COUNT"
```

---

### Phase 6: Display Completion

Present final summary:

```markdown
## Project Shipped!

**Delivered:** {timestamp}
**Phases Completed:** 4/4
**Issues Resolved:** {ISSUES_RESOLVED}
**Lessons Captured:** {LESSONS_COUNT}

### Multi-AI Audit Summary

- **Security Score:** {score}/100
- **Quality Score:** {score}/100
- **Providers Used:** Codex + Gemini + Claude

### Archive

Location: `.octo/archive/{ARCHIVE_TIMESTAMP}/`

Contents:
- STATE.md
- PROJECT.md
- ROADMAP.md
- ISSUES.md

### Checkpoint

Tag: `{CHECKPOINT_TAG}`

Restore with: `/octo:rollback {CHECKPOINT_TAG}`

---

**To start a new project:** `/octo:embrace`

*Multi-AI validation powered by Claude Octopus*
*Providers: Codex | Gemini | Claude*
```

---

## Error Handling

| Error | Resolution |
|-------|------------|
| No .octo/ directory | Suggest `/octo:embrace` |
| Project not ready | Show remaining phases |
| orchestrate.sh fails | Show error logs, suggest retry |
| Critical audit issues | Block ship, show issues |
| Git tag fails | Warn but continue (non-blocking) |

---

## Safety Measures

| Measure | Implementation |
|---------|----------------|
| **Pre-ship audit** | orchestrate.sh Multi-AI validation required |
| **Lessons preservation** | LESSONS.md never archived, always preserved |
| **Archive before ship** | State files copied to archive directory |
| **Git checkpoint** | Tag created for rollback capability |
| **No file deletion** | Archive copies, doesn't delete source files |

---

## Integration with Other Skills

### With /octo:deliver

```
User runs /octo:deliver to validate
→ Deliver phase complete
→ User runs /octo:ship to finalize
```

### With /octo:rollback

```
User ships project
→ Checkpoint created
→ Later: /octo:rollback octo-checkpoint-shipped-*
```

### With /octo:status

```
After ship: status shows "shipped"
→ Suggests /octo:embrace for new project
```

---

## Red Flags - Never Do

| Action | Why It's Wrong |
|--------|----------------|
| Skip Multi-AI audit | Security vulnerabilities missed |
| Archive LESSONS.md | Loses accumulated project knowledge |
| Delete source files | Should copy, not move |
| Ship without ready check | Incomplete work shipped |
| Skip checkpoint creation | No rollback recovery path |

---

## Quick Reference

| Step | Command | Purpose |
|------|---------|---------|
| 1 | Check .octo/STATE.md | Verify ready to ship |
| 2 | orchestrate.sh ink | Multi-AI security audit |
| 3 | Ask user | Capture lessons learned |
| 4 | mkdir + cp | Archive state files |
| 5 | Update STATE.md | Mark as shipped |
| 6 | git tag | Create shipped checkpoint |

---

## The Bottom Line

```
Ship → Ready + Audit passed + Lessons captured + Archived + Checkpoint created
Otherwise → Not shipped
```

**Verify ready. Run Multi-AI audit. Capture lessons. Archive state. Create checkpoint. Ship.**
