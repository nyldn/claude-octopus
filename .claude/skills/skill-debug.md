---
name: skill-debug
aliases:
  - debug
  - systematic-debugging
description: |
  Four-phase debugging process: Investigate → Analyze → Hypothesize → Implement.
  "Iron Law: NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST."
trigger: |
  Use when encountering any bug, test failure, or unexpected behavior.
  Auto-invoke when user says "fix this bug", "why is X failing", "debug Y".
  ESPECIALLY use when under time pressure or after multiple failed fix attempts.
---

# Systematic Debugging

## The Iron Law

```
NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST
```

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

### 4. If Fix Doesn't Work

| Attempts | Action |
|----------|--------|
| < 3 | Return to Phase 1, re-analyze with new information |
| ≥ 3 | **STOP.** Question the architecture. |

### 5. After 3+ Failed Fixes: Question Architecture

**Pattern indicating architectural problem:**
- Each fix reveals new coupling/problem elsewhere
- Fixes require "massive refactoring"
- Each fix creates new symptoms

**STOP and question fundamentals:**
- Is this pattern fundamentally sound?
- Are we sticking with it through inertia?
- Should we refactor architecture vs. continue fixing symptoms?

**Discuss with user before attempting more fixes.**

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
./scripts/orchestrate.sh probe "Investigate auth failure from 4 angles"

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
