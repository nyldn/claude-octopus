---
name: skill-iterative-loop
aliases:
  - iterative-loop
  - loop-execution
  - repeat-until
description: |
  Execute tasks in loops with conditions, performing iterative improvements until goals are met.
  Handles "loop N times", "keep trying until", and iterative refinement patterns.
  
  Use PROACTIVELY when user requests iterative execution:
  - "loop X times", "loop around N times"
  - "loop around 5 times auditing, enhancing, testing"
  - "keep trying until", "iterate until", "run until X passes"
  - "loop until Y works", "repeat N times", "try N times"
  
  DO NOT use for: single execution requests, manual retry requests,
  or infinite loops without max iterations.
trigger: |
  AUTOMATICALLY ACTIVATE when user requests iterative execution:
  - "loop X times" or "loop around N times"
  - "loop around 5 times auditing, enhancing, testing"
  - "keep trying until" or "iterate until"
  - "run until X passes" or "loop until Y works"
  - "repeat N times" or "try N times"

  DO NOT activate for:
  - Single execution requests
  - Manual retry requests
  - Infinite loops (require max iterations)
---

# Iterative Loop Execution

## Overview

Systematic iterative execution with clear goals, exit conditions, and progress tracking.

**Core principle:** Define goal → Set max iterations → Execute → Evaluate → Loop or complete.

---

## When to Use

**Use this skill when user wants to:**
- Execute a task multiple times with refinements
- Loop until a condition is met
- Iteratively improve something (code, tests, performance)
- Retry operations with modifications
- Progressive enhancement in rounds

**Do NOT use for:**
- Single execution ("run tests once")
- Manual step-by-step work
- Infinite loops without bounds
- Simple retry logic (use skill-debug)

---

## The Process

### Phase 1: Loop Setup

#### Step 1: Understand the Intent

```markdown
**Loop Intent:**

Goal: [what should be achieved]
Success criteria: [how do we know we're done]
Max iterations: [safety limit]
Per-iteration tasks: [what to do each loop]
```

#### Step 2: Clarify Parameters

Use AskUserQuestion if unclear:

- **Max iterations:** How many times maximum?
- **Success condition:** What indicates we can stop early?
- **Per-iteration actions:** What exactly to do each round?
- **Failure handling:** What if it never succeeds?

#### Step 3: Safety Checks

```markdown
**Safety Validation:**

- [ ] Max iterations defined (no infinite loops)
- [ ] Success condition is measurable
- [ ] Each iteration makes progress
- [ ] Failure exit strategy exists
- [ ] User aware of potential duration
```

**Never proceed without max iterations defined.**

---

### Phase 2: Loop Execution

#### Step 1: Initialize Loop

```markdown
**Starting Iterative Loop**

Goal: [description]
Max iterations: [N]
Success criteria: [condition]

---

### Iteration 1 / [N]
```

#### Step 2: Execute Iteration

For each iteration:

```markdown
**Iteration [current] / [max]**

**Actions:**
1. [Action 1]
   → [result/output]
2. [Action 2]
   → [result/output]
3. [Action 3]
   → [result/output]

**Evaluation:**
- Success criteria met? [Yes/No]
- Progress made? [Yes/No]
- Issues found: [list any issues]

**Status:** [Continue/Success/Need intervention]

---
```

#### Step 3: Progress Tracking

Use TodoWrite to track iterations:

```
Iteration Progress:
✓ Iteration 1 - [what was done]
✓ Iteration 2 - [what was done]
⚙️ Iteration 3 - [in progress]
- Iteration 4 - [pending]
- Iteration 5 - [pending]
```

---

### Phase 3: Exit Conditions

#### Exit Condition 1: Success

```markdown
🎉 **Success! Loop complete.**

**Goal achieved:** [description]
**Iterations used:** [N] / [max]

**Final state:**
[description of what was achieved]

**Summary of iterations:**
1. Iteration 1: [what happened]
2. Iteration 2: [what happened]
...
N. Iteration N: [what happened] ✓ Success
```

#### Exit Condition 2: Max Iterations Reached

```markdown
⚠️ **Max iterations reached without full success**

**Iterations completed:** [max]
**Goal:** [description]
**Current state:** [how close we got]

**Progress made:**
- [Improvement 1]
- [Improvement 2]
- [Improvement 3]

**Remaining issues:**
- [Issue 1]
- [Issue 2]

**Options:**
1. Accept current state (substantial progress made)
2. Continue with [N] more iterations
3. Change approach (current method may not work)

What would you like to do?
```

#### Exit Condition 3: No Progress Detected

```markdown
🛑 **Stopping early: No progress detected**

**Iteration:** [N] / [max]
**Reason:** Last [M] iterations showed no improvement

**Analysis:**
This suggests the current approach may be fundamentally flawed.

**Recommendation:**
Rather than continue looping, let's:
1. Analyze why no progress is being made
2. Consider alternative approaches
3. Re-evaluate the goal or success criteria

Shall we pause and reassess?
```

---

## Common Patterns

### Pattern 1: Loop with Testing

```
User: "Loop around 5 times auditing, enhancing, testing, until it's done"

Implementation:

**Loop Goal:** Code passes all quality gates
**Max Iterations:** 5
**Per-iteration:**
1. Audit code for issues
2. Enhance/fix identified issues
3. Run tests
4. Check if all pass

**Success:** All tests pass + no issues found

Execute:
Iteration 1:
- Audit → Found 8 issues
- Fix → Fixed 8 issues
- Test → 2 tests still failing
- Continue

Iteration 2:
- Audit → Found 2 new issues from fixes
- Fix → Fixed 2 issues
- Test → All tests pass ✓
- Success! Stopping early (2/5 iterations used)
```

### Pattern 2: Performance Optimization Loop

```
User: "Keep trying optimizations until we hit < 100ms response time"

Implementation:

**Loop Goal:** Response time < 100ms
**Max Iterations:** 10
**Per-iteration:**
1. Measure current performance
2. Identify bottleneck
3. Apply optimization
4. Re-measure

**Success:** Response time < 100ms

Execute:
Iteration 1: 450ms → Cache database queries → 280ms (Continue)
Iteration 2: 280ms → Add index to frequent query → 150ms (Continue)
Iteration 3: 150ms → Implement response compression → 85ms (Success!)
```

### Pattern 3: Retry with Backoff

```
User: "Try deploying, retry up to 3 times if it fails"

Implementation:

**Loop Goal:** Successful deployment
**Max Iterations:** 3
**Per-iteration:**
1. Attempt deployment
2. Check status
3. If failed, wait before retry

**Success:** Deployment succeeds

Execute:
Iteration 1: Deploy → Failed (API timeout) → Wait 10s
Iteration 2: Deploy → Failed (API timeout) → Wait 20s
Iteration 3: Deploy → Success ✓
```

### Pattern 4: Incremental Refinement

```
User: "Iterate 4 times improving the error messages based on user feedback"

Implementation:

**Loop Goal:** Error messages meet clarity standard
**Max Iterations:** 4
**Per-iteration:**
1. Review current error messages
2. Identify confusing ones
3. Rewrite for clarity
4. Evaluate against criteria

**Success:** All messages rated 8+/10 for clarity

Execute each iteration with progressive improvement
```

---

## Integration with Other Skills

### With skill-debug

```
Loop for debugging:
"Keep debugging until all tests pass, max 5 tries"

Each iteration:
- Use skill-debug to investigate failure
- Apply fix
- Re-run tests
- Evaluate
```

### With skill-audit

```
Loop for comprehensive checking:
"Loop 3 times auditing different aspects"

Iteration 1: Audit security
Iteration 2: Audit performance
Iteration 3: Audit accessibility
```

### With skill-tdd

```
Loop for TDD cycles:
"Do 5 red-green-refactor cycles"

Each iteration:
- Write failing test (red)
- Make it pass (green)
- Refactor (refactor)
- Evaluate and continue
```

---

## Best Practices

### 1. Always Define Max Iterations

**Good:**
```
Loop max 5 times trying to fix the issue
```

**Dangerous:**
```
Keep trying until it works
(What if it never works? Infinite loop!)
```

### 2. Measurable Success Criteria

**Good:**
```
Success: All 15 tests pass AND code coverage > 80%
```

**Poor:**
```
Success: Code looks better
(Too subjective)
```

### 3. Make Progress Visible

```
**Progress Tracking:**

Iteration 1: 5/15 tests passing
Iteration 2: 10/15 tests passing
Iteration 3: 13/15 tests passing
Iteration 4: 15/15 tests passing ✓
```

### 4. Early Exit on Success

Don't continue looping if goal is achieved:

```
**Iteration 2/5:** All tests pass!

Stopping early - goal achieved.
No need to continue to iteration 3.
```

### 5. Detect Stalls

```
Iteration 4: 10/15 tests passing
Iteration 5: 10/15 tests passing
Iteration 6: 10/15 tests passing

⚠️ No progress in 3 iterations - stopping to reassess approach
```

---

## Red Flags - Don't Do This

| Action | Why It's Dangerous |
|--------|-------------------|
| No max iterations | Could loop forever |
| Vague success criteria | Don't know when to stop |
| No progress tracking | Can't tell if making progress |
| Ignoring stalls | Waste time on ineffective approach |
| Same action each loop | If not working, need different approach |

---

## Safety Mechanisms

### 1. Iteration Limit

```python
MAX_ITERATIONS = user_specified or 10  # Always have a limit
```

### 2. Progress Detection

```
If last 3 iterations show same result:
  → Stop and ask user
```

### 3. Time Limit (for long operations)

```
If total time > 30 minutes:
  → Checkpoint progress
  → Ask user if should continue
```

### 4. User Checkpoints

```
Every N iterations:
  → Show progress
  → Ask if should continue or adjust approach
```

---

## Quick Reference

| Pattern | Max Iterations | Success Criteria | Early Exit |
|---------|---------------|------------------|------------|
| Test until pass | 5-10 | All tests pass | Yes |
| Performance optimization | 10-20 | Metric < target | Yes |
| Retry with backoff | 3-5 | Operation succeeds | Yes |
| Incremental refinement | 3-7 | Quality threshold met | Maybe |
| Comprehensive audit | 3-5 | All areas covered | No |

---

## The Bottom Line

```
Iterative loop → Clear goal + Max iterations + Progress tracking + Exit strategy
Otherwise → Infinite loops + Wasted effort + Unclear when done
```

**Define the goal. Set the limit. Track progress. Know when to stop.**
