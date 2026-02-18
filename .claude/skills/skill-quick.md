---
name: octopus-quick
description: Quick execution for ad-hoc tasks without workflow overhead
aliases:
  - quick
  - quick-mode
  - adhoc
trigger: |
  Use this skill when user says "quick fix", "ad-hoc task", or explicitly
  requests fast execution without full workflow overhead.
---

# Quick Mode - Lightweight Task Execution ⚡

Fast-track execution for small tasks that don't need full Double Diamond workflow overhead.

## When to Use Quick Mode

### ✅ Use Quick Mode For:

**Bug Fixes:**
- One-file bug fixes with known solution
- Typo corrections
- Logic error fixes
- Import/export corrections

**Configuration Changes:**
- Update environment variables
- Modify config files
- Adjust settings
- Update dependencies

**Small Refactorings:**
- Rename variables/functions
- Extract helper functions
- Simplify logic in single file
- Code cleanup

**Documentation:**
- Fix typos in README
- Update comments
- Add/update docstrings
- Clarify documentation

**Dependency Management:**
- Update package versions
- Add new dependency
- Remove unused dependency

### ❌ Don't Use Quick Mode For:

**Complex Work:**
- New features
- Architecture changes
- Multi-file refactorings
- Security-sensitive changes
- Performance optimizations requiring research
- Database schema changes
- API contract changes

**Use full workflows for complex work to ensure quality.**

---

## Execution Flow

Quick mode follows a streamlined process:

```
User Request → Direct Implementation → Atomic Commit → Summary
```

**What Quick Mode SKIPS:**
- ❌ Multi-AI research (probe/discover)
- ❌ Requirements planning (grasp/define)
- ❌ Multi-AI validation (ink/deliver)
- ❌ Plan-checker verification

**What Quick Mode KEEPS:**
- ✅ State tracking (records in state.json)
- ✅ Atomic commits (git commit with description)
- ✅ Summary generation (stored in .claude-octopus/quick/)
- ✅ Change documentation

---

## Usage

### Via Command

```bash
/octo:quick "add dark mode toggle to settings"
```

### Via Skill Invocation

```bash
Use skill: octopus-quick
Task: "fix typo in README.md line 42"
```

### Examples

```
/octo:quick "update Next.js to v15"
/octo:quick "fix the broken import in auth.ts"
/octo:quick "add error handling to login function"
/octo:quick "remove console.log statements"
```

---

## Implementation

### Step 1: Understand the Task

Quickly assess:
- What file(s) need to change?
- What's the specific change?
- Any dependencies or side effects?

### Step 2: Make the Change

Implement directly using appropriate tools:
- **Edit** - For modifying existing files
- **Write** - For creating new files (rare in quick mode)
- **Bash** - For file operations, dependency updates

### Step 3: Create Atomic Commit

**Always create a descriptive commit:**

```bash
# Stage changes
git add [changed-files]

# Create commit with clear message
git commit -m "quick: [brief description]

[Detailed explanation if needed]

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

**Commit message format:**
- Prefix with `quick:` to indicate quick mode
- Brief description in present tense
- Optional detailed explanation
- Co-authored tag

### Step 4: Record in State

```bash
# Update state with quick task execution
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" write_decision \
  "quick" \
  "$(git log -1 --pretty=%s)" \
  "Ad-hoc task executed in quick mode"

# Update metrics
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_metrics \
  "execution_time" \
  "1"  # Estimated in minutes
```

### Step 5: Generate Summary

```bash
# Create quick task summary
mkdir -p .claude-octopus/quick

summary_file=".claude-octopus/quick/$(date +%Y%m%d-%H%M%S)-summary.md"

cat > "$summary_file" <<EOF
# Quick Task: $(git log -1 --pretty=%s)

## Task Description
$TASK_DESCRIPTION

## Changes Made
$(git diff HEAD~1..HEAD --stat)

## Files Modified
$(git diff --name-only HEAD~1..HEAD)

## Commit
$(git rev-parse HEAD)

## Timestamp
$(date -u +%Y-%m-%dT%H:%M:%SZ)

---
*Executed in Quick Mode - minimal overhead execution*
EOF

echo "📝 Summary saved to: $summary_file"
```

---

## Complete Example

**User Request:**
```
/octo:quick "fix typo in README - change 'recieve' to 'receive'"
```

**Execution:**

1. **Read the file**
   ```
   Read README.md to locate the typo
   ```

2. **Make the change**
   ```
   Edit README.md: replace "recieve" with "receive"
   ```

3. **Commit atomically**
   ```bash
   git add README.md
   git commit -m "quick: fix typo in README (recieve → receive)

   Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
   ```

4. **Record in state**
   ```bash
   state-manager.sh write_decision "quick" \
     "Fixed typo in README" \
     "Ad-hoc documentation fix"
   ```

5. **Generate summary**
   ```bash
   Created: .claude-octopus/quick/20260129-143045-summary.md
   ```

6. **Report to user**
   ```
   ✅ Fixed typo in README.md
   📝 Commit: abc123f
   📋 Summary: .claude-octopus/quick/20260129-143045-summary.md
   ```

---

## Benefits of Quick Mode

### Speed ⚡
- No multi-AI orchestration overhead
- Direct implementation
- Faster for simple tasks

### Cost Savings 💰
- No external provider API calls
- Only uses Claude (included with Claude Code)
- Efficient for ad-hoc work

### Still Tracked 📊
- Commits recorded
- State updated
- Summaries generated
- Full audit trail maintained

### Appropriate Scope 🎯
- Right tool for small tasks
- Doesn't over-engineer simple changes
- Reserves full workflows for complex work

---

## When Quick Mode Isn't Enough

If during execution you realize the task is more complex than expected:

**Stop and escalate to full workflow:**

```
This task is more complex than anticipated. I recommend using the full
workflow instead:

- For research: /octo:discover "research authentication patterns"
- For planning: /octo:define "define auth requirements"
- For building: /octo:develop "implement auth system"
- For validation: /octo:deliver "validate auth implementation"

Would you like me to switch to a full workflow?
```

**Indicators to escalate:**
- Multiple files need changes
- Requires architectural decisions
- Needs research or comparison
- Security implications
- Performance implications
- Breaking changes

---

## Directory Structure

Quick mode creates summaries in a dedicated directory:

```
.claude-octopus/
└── quick/
    ├── 20260129-143045-summary.md
    ├── 20260129-150122-summary.md
    └── 20260129-161530-summary.md
```

Each summary includes:
- Task description
- Changes made
- Files modified
- Commit hash
- Timestamp

---

## Comparison: Quick Mode vs Full Workflow

| Aspect | Quick Mode ⚡ | Full Workflow 🐙 |
|--------|-------------|------------------|
| **Time** | 1-3 minutes | 5-15 minutes |
| **Cost** | Claude only | Codex + Gemini + Claude |
| **Providers** | 1 (Claude) | 3 (multi-AI) |
| **Research** | None | Comprehensive |
| **Planning** | None | Detailed |
| **Validation** | Basic | Multi-AI review |
| **Best For** | Simple fixes | Complex features |
| **When to Use** | Known solution | Unknown solution |

---

## Best Practices

### DO:
- ✅ Use quick mode for straightforward tasks
- ✅ Create descriptive commit messages
- ✅ Generate summaries for audit trail
- ✅ Update state even in quick mode
- ✅ Escalate to full workflow if complexity increases

### DON'T:
- ❌ Use quick mode for new features
- ❌ Skip commits (always commit atomically)
- ❌ Skip state updates (maintain consistency)
- ❌ Use quick mode for security-sensitive changes
- ❌ Force quick mode when full workflow is appropriate

---

## Troubleshooting

### "Quick mode is taking too long"
→ Task is probably too complex. Escalate to full workflow.

### "Change broke tests"
→ Quick mode assumes simple, safe changes. Use full workflow for risky changes.

### "Need to research best approach"
→ Quick mode is for known solutions only. Use /octo:discover for research.

### "Multiple files need changes"
→ Consider /octo:develop for coordinated multi-file changes.

---

## Summary

Quick mode is the right tool for simple, straightforward tasks with known solutions. It provides fast execution while maintaining essential tracking and documentation.

For everything else, use the full Double Diamond workflow to ensure quality through multi-AI orchestration.

**Remember: Fast is good, but correct is better. When in doubt, use the full workflow.**
