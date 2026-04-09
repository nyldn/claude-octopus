---
name: skill-debug
aliases:
  - debug
  - systematic-debugging
description: "Debug issues methodically — use when stuck on errors, test failures, or unexpected behavior"
trigger: |
  AUTOMATICALLY ACTIVATE when encountering bugs or failures:
  - "fix this bug" or "debug Y" or "troubleshoot X"
  - "why is X failing" or "why isn't X working" or "why doesn't X work"
  - "why did X not work" or "why didn't X happen"
  - "X does not work" or "X is broken" or "X is not working"
  - "investigate Y" or "figure out why Z"
  - "The X button does not work" or "X preview button does not work"

  ESPECIALLY use when under time pressure or after multiple failed fix attempts.

  DO NOT activate for:
  - "Why do we use X?" (explanation, not debugging)
  - "Why should I choose X?" (decision support, not debugging)
  - Known issues with clear solutions
  - Documentation or architecture questions
execution_mode: enforced
pre_execution_contract:
  - visual_indicators_displayed
validation_gates:
  - orchestrate_sh_executed
  - debug_output_exists
---

# Systematic Debugging

## MANDATORY COMPLIANCE — DO NOT SKIP

**When this skill is invoked, you MUST follow the 4-phase debugging process below. You are PROHIBITED from:**
- Jumping straight to a fix without completing Phase 1 (Root Cause Investigation)
- Skipping the hypothesis step and guessing at solutions
- Deciding the bug is "obvious" and bypassing the systematic process
- Attempting more than 3 fixes without stopping to ask the user

**Systematic debugging finds root causes in 15-30 minutes. Random fixes waste 2-3 hours. Follow the process.**

---

**Your first output line MUST be:** `🐙 **CLAUDE OCTOPUS ACTIVATED** - Systematic Debugging`

## The Iron Law

<HARD-GATE>
NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST
</HARD-GATE>

Random fixes waste time and create new bugs. Quick patches mask underlying issues.

**If you haven't completed Phase 1, you cannot propose fixes.**

## When to Use

**Use for ANY technical issue:**
- Test failures
- Bugs in production
- Unexpected behavior
- Performance problems
- Build failures
- Integration issues

**Use ESPECIALLY when:**
- Under time pressure (emergencies make guessing tempting)
- "Just one quick fix" seems obvious
- You've already tried multiple fixes
- Previous fix didn't work

## The Four Phases

```
┌──────────────────┐
│ Phase 1: ROOT    │ ← Understand WHAT and WHY
│ CAUSE            │
└────────┬─────────┘
         ↓
┌──────────────────┐
│ Phase 2: PATTERN │ ← Find working examples
│ ANALYSIS         │
└────────┬─────────┘
         ↓
┌──────────────────┐
│ Phase 3:         │ ← Form and test hypothesis
│ HYPOTHESIS       │
└────────┬─────────┘
         ↓
┌──────────────────┐
│ Phase 4:         │ ← Fix root cause, not symptom
│ IMPLEMENTATION   │
└──────────────────┘
```

**You MUST complete each phase before proceeding.**

---

## Phase 1: Root Cause Investigation

**BEFORE attempting ANY fix:**

### 1. Read Error Messages Carefully
- Don't skip past errors or warnings
- Read stack traces completely
- Note line numbers, file paths, error codes
- Error messages often contain the exact solution

### 2. Reproduce Consistently
- Can you trigger it reliably?
- What are the exact steps?
- Does it happen every time?
- **If not reproducible → gather more data, don't guess**

### 3. Check Recent Changes
```bash
git diff HEAD~5
git log --oneline -10
```
- What changed that could cause this?
- New dependencies, config changes?
- Environmental differences?

### 4. Gather Evidence in Multi-Component Systems

**When system has multiple components (API → service → database):**

```bash
# Add diagnostic instrumentation at EACH boundary
echo "=== Layer 1: API endpoint ==="
echo "Input: $INPUT"

echo "=== Layer 2: Service layer ==="
echo "Received: $DATA"

echo "=== Layer 3: Database ==="
echo "Query: $QUERY"
```

**Run once to gather evidence showing WHERE it breaks.**

### 5. Trace Data Flow

When error is deep in call stack:
- Where does bad value originate?
- What called this with bad value?
- Keep tracing up until you find the source
- **Fix at source, not at symptom**

---

## Phase 2: Pattern Analysis

### 1. Find Working Examples
- Locate similar working code in same codebase
- What works that's similar to what's broken?

### 2. Compare Against References
- If implementing a pattern, read reference implementation COMPLETELY
- Don't skim - read every line
- Understand the pattern fully before applying

### 3. Identify Differences
- What's different between working and broken?
- List every difference, however small
- Don't assume "that can't matter"

### 4. Understand Dependencies
- What other components does this need?
- What settings, config, environment?
- What assumptions does it make?

---

## Phase 3: Hypothesis and Testing

### 1. Form Single Hypothesis
- State clearly: "I think X is the root cause because Y"
- **Write it down**
- Be specific, not vague

### 2. Test Minimally
- Make the SMALLEST possible change to test hypothesis
- One variable at a time
- **Don't fix multiple things at once**

### 3. Verify Before Continuing

| Result | Action |
|--------|--------|
| Hypothesis confirmed | Proceed to Phase 4 |
| Hypothesis wrong | Form NEW hypothesis, return to Phase 3.1 |
| Still unclear | Gather more evidence, return to Phase 1 |

### 4. When You Don't Know
- Say "I don't understand X"
- Don't pretend to know
- Ask for help or research more

---

## Phase 4: Implementation

### 1. Create Failing Test Case
- Simplest possible reproduction
- Automated test if possible
- **MUST have before fixing**
- Use TDD skill for proper test

### 2. Implement Single Fix
- Address the root cause identified
- **ONE change at a time**
- No "while I'm here" improvements
- No bundled refactoring

### 3. Verify Fix
- Test passes now?
- No other tests broken?
- Issue actually resolved?

### 4. If Fix Doesn't Work — 3-Strike Rule

| Attempts | Action |
|----------|--------|
| < 3 | Return to Phase 1, re-analyze with new information |
| ≥ 3 | **STOP.** Show your work. Ask the user. |

**Anti-rationalization rules:**
- "Should work now" → **RUN IT.** Confidence is not evidence.
- "I already tested earlier" → Code changed since then. **Test again.**
- "It's a trivial change" → Trivial changes break production. **Verify.**
- "I'm pretty sure this fixes it" → Pretty sure is not verified. **Run the test.**

### 5. After 3+ Failed Fixes: Question Architecture

**Pattern indicating architectural problem:**
- Each fix reveals new coupling/problem elsewhere
- Fixes require "massive refactoring"
- Each fix creates new symptoms

**STOP and question fundamentals:**
- Is this pattern fundamentally sound?
- Are we sticking with it through inertia?
- Should we refactor architecture vs. continue fixing symptoms?

**Discuss with user before attempting more fixes. Do not attempt a 4th fix without explicit user approval.**

---

## Self-Regulation Score (Debug Fix Loops)

When debugging involves multiple fix attempts, track a **WTF score** to detect runaway fix loops. This complements the 3-Strike Rule above with quantitative drift detection.

**Track these signals** (default weights, override via `~/.claude-octopus/loop-config.conf`):

| Event | Score Impact |
|-------|-------------|
| Revert (git revert, undo, roll back a fix) | **+15%** |
| Touching files unrelated to the bug | **+20%** |
| A fix that requires changing >3 files | **+5%** |
| After the 15th fix attempt | **+1% per additional fix** |
| All remaining issues are Low severity | **+10%** |

**If WTF score exceeds 20%** — STOP immediately, even if under the 3-strike limit. Show the score breakdown and ask the user whether to continue.

**Also watch for stuck patterns**: If the same error message appears 3+ times across fix attempts, or you see A→B→A→B oscillation (fix X breaks Y, fix Y breaks X), announce the cycle and HALT on second detection.

Report the score with each fix attempt:
```
Fix attempt 2 | Self-regulation: 15% (1 revert, 0 unrelated files)
```

---

## Strategy Rotation

After 2 failed fix attempts, stop and reconsider the root cause before trying another fix. If the strategy-rotation hook fires, it means you have been repeating a failing approach. Do not continue down the same path — return to Phase 1 and investigate from a different angle.

---

## Red Flags - STOP and Follow Process

If you catch yourself thinking:
- "Quick fix for now, investigate later"
- "Just try changing X and see"
- "Skip the test, I'll manually verify"
- "It's probably X, let me fix that"
- "I don't fully understand but this might work"
- "One more fix attempt" (when already tried 2+)

**ALL of these mean: STOP. Return to Phase 1.**

---

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "Issue is simple" | Simple issues have root causes too. |
| "Emergency, no time" | Systematic is FASTER than thrashing. |
| "Just try this first" | First fix sets the pattern. Do it right. |
| "I see the problem" | Seeing symptoms ≠ understanding root cause. |
| "One more attempt" | 3+ failures = architectural problem. |

---

## Platform Debugging

If you suspect the issue is with the Claude Code environment itself (e.g., network errors, context limits, tool failures):

- **Run `/debug`**: This native command generates a debug bundle to help troubleshoot platform issues.
- **Check `/debug` output**: Look for "Context limit", "API error", or "Tool execution failed".

## Auto-Freeze on Debug

When debugging a specific module, automatically activate freeze mode to prevent accidental edits outside the investigated area. This is a safety measure that keeps your debugging focused.

### How It Works

At the start of Phase 1 (Root Cause Investigation), identify the primary module directory being debugged and activate freeze mode:

```bash
# Determine the module directory from the error location or user-specified target
# Example: if debugging src/auth/login.ts, freeze to src/auth/
freeze_dir="$(cd "<module-directory>" 2>/dev/null && pwd)"
echo "${freeze_dir}" > "/tmp/octopus-freeze-${CLAUDE_SESSION_ID:-$$}.txt"
```

This ensures that during investigation (Phases 1-3), you cannot accidentally modify files outside the module under investigation. When you reach Phase 4 (Implementation), the freeze boundary keeps your fix scoped to the right module.

**Auto-freeze activates when:**
- The bug is localized to a specific directory (e.g., `src/auth/`, `lib/database/`)
- The user specifies a file or module to debug

**Auto-freeze does NOT activate when:**
- The bug spans multiple modules
- The root cause location is unknown at investigation start
- The user explicitly opts out

After debugging completes, remind the user to run `/octo:unfreeze` if needed, or remove the state file automatically.

---

## Integration with Claude Octopus

When using octopus workflows for debugging:

| Workflow | Debugging Integration |
|----------|----------------------|
| `probe` | Research error patterns, similar issues |
| `grasp` | Define the problem scope clearly |
| `tangle` | Implement the fix with TDD |
| `squeeze` | Verify fix doesn't introduce vulnerabilities |
| `grapple` | Debate architectural alternatives after 3+ failures |

### Multi-Agent Debugging

For complex bugs, use parallel exploration:

```bash
# Phase 1 parallelized
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh probe "Investigate auth failure from 4 angles"

# Perspectives:
# Agent 1: Error message analysis
# Agent 2: Recent changes review
# Agent 3: Data flow tracing
# Agent 4: Environment comparison
```

---

## Quick Reference

| Phase | Key Activities | Success Criteria |
|-------|----------------|------------------|
| **1. Root Cause** | Read errors, reproduce, check changes | Understand WHAT and WHY |
| **2. Pattern** | Find working examples, compare | Identify differences |
| **3. Hypothesis** | Form theory, test minimally | Confirmed or new hypothesis |
| **4. Implementation** | Create test, fix, verify | Bug resolved, tests pass |

---

## The Bottom Line

```
Proposing fix → Root cause investigation completed
Otherwise → Not systematic debugging
```

Systematic approach: 15-30 minutes to fix.
Random fixes approach: 2-3 hours of thrashing.

**No shortcuts for debugging.**
