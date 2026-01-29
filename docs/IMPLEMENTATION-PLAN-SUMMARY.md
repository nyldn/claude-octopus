# Implementation Plan Summary: HIGH PRIORITY UX Features

**Quick Reference Guide**

---

## Overview

Three interconnected features that transform multi-AI orchestration UX from opaque to transparent:

| Feature | User Benefit | Effort | Files Changed |
|---------|-------------|--------|---------------|
| **Enhanced Spinner Verbs** | Know exactly what each provider is doing | 1 day | orchestrate.sh + 5 skills |
| **Enhanced Progress Indicators** | See real-time status of all providers | 1 day | orchestrate.sh + hooks |
| **Timeout Visibility** | Get warnings before timeout, clear guidance | 0.5 day | orchestrate.sh + docs |

**Total Effort:** 2.5 days implementation + 0.5 days testing = 3 days
**Release:** v7.15.0

---

## Feature 1: Enhanced Spinner Verbs

### What Changes
```diff
- activeForm: "Running multi-AI discover workflow"
+ activeForm: "🔴 Researching technical patterns (Codex)"
+ activeForm: "🟡 Exploring ecosystem and options (Gemini)"
+ activeForm: "🔵 Synthesizing research findings"
```

### Key Files
1. `/Users/chris/git/claude-octopus/plugin/scripts/orchestrate.sh`
   - Add `get_active_form_verb()` function (~50 lines)
   - Add `update_task_progress()` function (~15 lines)
   - Integrate into agent execution loop (~10 lines)

2. `/Users/chris/git/claude-octopus/plugin/.claude/skills/flow-*.md` (4 files)
   - Update task documentation to note dynamic updates

### Implementation Checklist
- [ ] Add helper functions (lines 565+)
- [ ] Define verb mappings (all phases × all providers)
- [ ] Hook into agent execution loop (line ~6500)
- [ ] Update skill documentation
- [ ] Test with control pipe monitoring

### Test Command
```bash
export CLAUDE_CODE_TASK_ID="test-123"
export CLAUDE_CODE_CONTROL_PIPE="/tmp/test.pipe"
mkfifo "$CLAUDE_CODE_CONTROL_PIPE"
tail -f "$CLAUDE_CODE_CONTROL_PIPE" &
./scripts/orchestrate.sh probe "Test query"
```

---

## Feature 2: Enhanced Progress Indicators

### What Changes
```diff
  Provider Availability:
  🔴 Codex CLI: Available ✓
  🟡 Gemini CLI: Available ✓
  🔵 Claude: Available ✓
+
+ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
+ 🐙 LIVE PROGRESS: Discover Phase (1/3 providers)
+ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
+
+ Provider Status:
+ ✅ 🔴 Codex CLI: Completed (23s) - $0.02
+ ⏳ 🟡 Gemini CLI: Running... (11s elapsed)
+ ⏸️  🔵 Claude: Waiting
+
+ Progress: 1/3 providers
+ 💰 Cost So Far: $0.02
+ ⏱️  Time: 34s elapsed
```

### Key Files
1. `/Users/chris/git/claude-octopus/plugin/scripts/orchestrate.sh`
   - Add progress tracking functions (~150 lines)
   - Initialize on workflow start (~10 lines)
   - Update during execution (~20 lines)

2. `/Users/chris/git/claude-octopus/plugin/.claude/hooks/visual-feedback.sh` (NEW)
   - Create hook script (~50 lines)
   - Monitor progress file
   - Format live display

3. `/Users/chris/git/claude-octopus/plugin/.claude-plugin/hooks.json`
   - Add Notification hook for periodic updates

### Implementation Checklist
- [ ] Add progress JSON file structure
- [ ] Add `init_progress_tracking()` function
- [ ] Add `update_agent_status()` function
- [ ] Add `format_progress_display()` function
- [ ] Create visual-feedback.sh hook
- [ ] Update hooks.json with 10-second interval
- [ ] Test real-time updates

### Test Command
```bash
# Terminal 1: Monitor progress file
watch -n 1 'cat ~/.claude-octopus/progress-*.json | jq .'

# Terminal 2: Run workflow
./scripts/orchestrate.sh probe "Test query"
```

---

## Feature 3: Timeout Visibility

### What Changes
```diff
  ⏳ 🟡 Gemini CLI: Running... (11s elapsed)
+ ⏳ 🟡 Gemini CLI: Running... (4m 32s / 5m timeout)
+ ⚠️  WARNING: Approaching timeout (28s remaining)
+
+ 💡 Tip: Increase timeout with: --timeout 600
```

### Key Files
1. `/Users/chris/git/claude-octopus/plugin/scripts/orchestrate.sh`
   - Modify `update_agent_status()` to track timeout (~15 lines)
   - Modify `format_progress_display()` to show warnings (~20 lines)
   - Enhance `run_with_timeout()` error messages (~10 lines)
   - Add `check_timeout_warnings()` function (~20 lines)

2. `/Users/chris/git/claude-octopus/plugin/docs/CLI-REFERENCE.md`
   - Add timeout configuration section

3. `/Users/chris/git/claude-octopus/plugin/docs/TROUBLESHOOTING.md` (NEW)
   - Create troubleshooting guide with timeout solutions

### Implementation Checklist
- [ ] Add timeout_ms and remaining_ms to progress tracking
- [ ] Calculate 80% threshold for warnings
- [ ] Display timeout info in status
- [ ] Improve timeout error messages
- [ ] Document timeout best practices
- [ ] Create troubleshooting guide

### Test Command
```bash
# Test warning at 80% threshold
./scripts/orchestrate.sh probe "Test" --timeout 30

# Test timeout exceeded
./scripts/orchestrate.sh probe "Long operation" --timeout 5

# Test increased timeout
./scripts/orchestrate.sh probe "Test" --timeout 600
```

---

## Integration Points

These three features work together:

```
orchestrate.sh execution
    ↓
Task spinner updates (Feature 1)
    ↓
Progress JSON file (Feature 2)
    ↓
Visual feedback hook reads progress (Feature 2)
    ↓
Displays with timeout warnings (Feature 3)
    ↓
User sees complete picture
```

---

## Daily Implementation Plan

### Day 1: Core Development
**Morning (4 hours):**
- [ ] Feature 1: Add spinner verb functions
- [ ] Feature 1: Integrate into agent loop
- [ ] Feature 2: Add progress tracking functions

**Afternoon (4 hours):**
- [ ] Feature 2: Create visual-feedback.sh hook
- [ ] Feature 2: Update hooks.json
- [ ] Feature 3: Add timeout tracking to progress

**Deliverables:** Core functionality working in orchestrate.sh

### Day 2: Integration & Testing
**Morning (4 hours):**
- [ ] Feature 1: Update all workflow skill docs
- [ ] Feature 3: Enhance timeout error messages
- [ ] Test all features together

**Afternoon (4 hours):**
- [ ] Fix integration issues
- [ ] Refine display formatting
- [ ] End-to-end testing in Claude Code

**Deliverables:** All features integrated and tested

### Day 3: Documentation & Release
**Morning (3 hours):**
- [ ] Update VISUAL-INDICATORS.md
- [ ] Update CLI-REFERENCE.md
- [ ] Create TROUBLESHOOTING.md
- [ ] Update CHANGELOG.md

**Afternoon (2 hours):**
- [ ] Final testing with real workflows
- [ ] Bump version to 7.15.0
- [ ] Create release notes
- [ ] Deploy to registry

**Deliverables:** v7.15.0 released with documentation

---

## File Change Summary

### New Files (3)
```
.claude/hooks/visual-feedback.sh          (50 lines)
docs/TROUBLESHOOTING.md                   (100 lines)
docs/IMPLEMENTATION-PLAN-UX-FEATURES.md   (1500 lines) ✓
```

### Modified Files (8)
```
scripts/orchestrate.sh                    (+300 lines)
.claude-plugin/hooks.json                 (+15 lines)
.claude/skills/flow-discover.md           (+20 lines)
.claude/skills/flow-define.md             (+20 lines)
.claude/skills/flow-develop.md            (+20 lines)
.claude/skills/flow-deliver.md            (+20 lines)
docs/VISUAL-INDICATORS.md                 (+100 lines)
docs/CLI-REFERENCE.md                     (+80 lines)
CHANGELOG.md                              (+50 lines)
```

**Total New Code:** ~350 lines
**Total Documentation:** ~250 lines
**Total Impact:** ~600 lines across 11 files

---

## Success Criteria

### Feature 1: Enhanced Spinner Verbs
- [x] Task spinner updates with provider-specific verbs
- [x] Different verbs for each phase (discover, define, develop, deliver)
- [x] Visual indicators (🔴🟡🔵) show which provider is active
- [x] Updates happen automatically via CLAUDE_CODE_CONTROL pipe

### Feature 2: Enhanced Progress Indicators
- [x] Live status display updates every 10 seconds
- [x] Shows completed, running, and waiting providers
- [x] Displays elapsed time and cost per provider
- [x] Progress percentage (e.g., "2/3 providers")
- [x] Works via Notification hook

### Feature 3: Timeout Visibility
- [x] Shows timeout limit in running status
- [x] Warnings at 80% threshold
- [x] Remaining time displayed
- [x] Actionable guidance provided
- [x] Enhanced error messages on timeout

---

## Risk Assessment

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Performance degradation | Medium | Low | Efficient JSON updates, 10s intervals |
| Hook compatibility issues | Medium | Low | Check Claude Code version, graceful degradation |
| Display clutter | Low | Medium | Consolidated status blocks, --quiet flag |
| File I/O overhead | Low | Low | Minimal writes, efficient jq usage |

---

## Rollback Plan

If issues arise after deployment:

1. **Disable hooks:** Update hooks.json to remove Notification hook
2. **Disable progress tracking:** Add `--no-progress` flag check
3. **Revert version:** Roll back to v7.14.0 if critical issues
4. **Hotfix release:** v7.15.1 with fixes if minor issues

All features are additive - no breaking changes to existing functionality.

---

## Next Steps

1. **Review:** Get approval on implementation plan
2. **Schedule:** Block 3 days for implementation
3. **Branch:** Create feature branch `feature/ux-improvements-v7.15`
4. **Implement:** Follow Day 1-3 plan above
5. **Test:** Comprehensive testing with real workflows
6. **Release:** Deploy v7.15.0 to registry
7. **Announce:** Share release notes highlighting UX improvements

---

## References

- **Full Implementation Plan:** `/Users/chris/git/claude-octopus/plugin/docs/IMPLEMENTATION-PLAN-UX-FEATURES.md`
- **Current Visual Indicators:** `/Users/chris/git/claude-octopus/plugin/docs/VISUAL-INDICATORS.md`
- **Orchestrate.sh:** `/Users/chris/git/claude-octopus/plugin/scripts/orchestrate.sh`
- **Example UX Update:** `/Users/chris/git/claude-octopus/plugin/docs/UPDATE-UX-IMPROVEMENT.md`

---

**Status:** Ready for implementation
**Estimated Completion:** 3 days from start
**Release Target:** v7.15.0
