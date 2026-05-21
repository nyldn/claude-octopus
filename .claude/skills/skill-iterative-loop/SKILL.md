---
name: skill-iterative-loop
aliases:
  - iterative-loop
  - loop-execution
  - repeat-until
description: "Run tasks in a loop until goals are met — use for iterative refinement, polling, or convergence"
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

## Strategy Rotation

If the strategy-rotation hook fires, immediately change approach. Do not retry the same approach. Explain what you'll do differently before the next attempt. The hook fires after consecutive failures of the same tool — this is a strong signal that the current approach is fundamentally wrong, not just slightly off.

---

## Self-Regulation (MANDATORY)

Every iterative loop MUST track a **Self-Regulation Score** that accumulates danger signals. This prevents runaway loops where the agent keeps "fixing" things without real progress.

### Sliding-Window Stuck Detection

Maintain a mental window of the **last 10 iterations** (or fewer if less than 10 have run). After each iteration, check for repeated patterns:

**Single-state repetition:** Did the same outcome/error occur 3+ times consecutively?
- Same test failure, same error message, same files modified → **STUCK**

**Multi-step cycle detection:** Is there an A→B→A→B oscillation?
- Iteration N touches file X, N+1 touches file Y, N+2 touches file X again, N+3 touches Y again → **CYCLE DETECTED**
- Compare the *files modified* and *error messages* across iterations, not just success/failure

**On first detection:** Announce the pattern to the user. Attempt ONE diagnostic retry with explicit acknowledgment: "This pattern has repeated — here's what I'll do differently: [specific change]."

**On second detection:** **HALT immediately.** Display the detected cycle and ask the user whether to continue with a completely different approach or stop.

### WTF-Likelihood Score

Track a cumulative score starting at 0%. Each event adds to the score.

**Default weights** (override via `~/.claude-octopus/loop-config.conf`):

| Event | Score Impact |
|-------|-------------|
| Revert (git revert, undo, roll back) | **+15%** |
| Touching files unrelated to the stated goal | **+20%** |
| A fix that requires changing >3 files | **+5%** |
| After the 15th fix attempt | **+1% per additional fix** |
| All remaining issues are Low severity | **+10%** |

**If WTF score exceeds 20%:** **STOP immediately.** Show:
1. The current WTF score and what contributed to it
2. Work completed so far
3. Ask the user: "Continue with a different approach, or stop here?"

**Hard cap:** 50 iterations regardless of score or progress. No exceptions.

### Configurable Weights

At loop start, check for `~/.claude-octopus/loop-config.conf`. If it exists, read the key=value pairs and use them instead of defaults. Format:

```conf
# Loop Self-Regulation Configuration
WINDOW_SIZE=10
REVERT_PENALTY=15
UNRELATED_FILES_PENALTY=20
LARGE_FIX_PENALTY=5
AFTER_FIX_15_PENALTY=1
ALL_LOW_SEVERITY_PENALTY=10
WTF_THRESHOLD=20
HARD_CAP=50
STUCK_THRESHOLD=3
```

If the file does not exist, use the defaults shown above. Users can create this file to tune sensitivity for their workflow.

### How to Track

You do NOT need external tools for this. Track mentally during the loop:
- After each iteration, mentally note: files touched, outcome, whether a revert happened
- Compare against the sliding window of recent iterations
- Accumulate the WTF score
- Report both the iteration count AND the self-regulation score in each iteration summary:

```
Iteration 5/20 | Self-regulation: 10% (1 revert, 0 unrelated files)
```

### Interaction with Strategy Rotation

The strategy-rotation hook and self-regulation are complementary:
- Strategy rotation fires on consecutive **tool** failures (same tool, same error)
- Self-regulation fires on **outcome** patterns (cycles, reverts, scope creep)
- Both can fire independently. If both fire, **HALT** — the loop is definitely stuck.

---

## Safety Mechanisms

### 1. Iteration Limit

```python
MAX_ITERATIONS = user_specified or 10  # Always have a limit
HARD_CAP = 50  # Absolute maximum regardless of user setting
```

### 2. Self-Regulation Score

```
Track WTF score across iterations.
If score > 20%: STOP and ask user.
```

### 3. Sliding-Window Detection

```
Track last 10 iterations.
If repeated pattern detected twice: STOP and ask user.
```

### 4. Progress Detection

```
If last 3 iterations show same result:
  → Stop and ask user
```

### 5. Time Limit (for long operations)

```
If total time > 30 minutes:
  → Checkpoint progress
  → Ask user if should continue
```

### 6. User Checkpoints

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

## Metric Verification Mode

When the user specifies a **Metric** command, switch to mechanical metric verification mode. This replaces subjective evaluation with automated measurement, git-backed experiments, and automatic rollback on regression.

**Falls back to standard loop behavior (above) when no metric is specified.**

### Key Principles

- **One change per iteration (atomic)** — never combine multiple unrelated changes
- **Mechanical verification only** — no subjective "looks good"; the metric command decides
- **Automatic rollback on regression** — `git revert HEAD --no-edit` if metric worsens
- **Simplicity wins** — equal metric results + less code = KEEP the simpler version
- **Git is memory** — every experiment is committed with `experiment:` prefix before verification
- **Guard commands must also pass** — even if metric improves, a failing guard reverts the change

### Parameters

| Parameter | Format | Required | Description |
|-----------|--------|----------|-------------|
| Metric | `Metric: <shell command>` | Yes (for this mode) | Command whose stdout is a number (the metric value) |
| Direction | `Direction: higher\|lower` | Yes | Whether higher or lower metric values are better |
| Guard | `Guard: <shell command>` | No | Must exit 0 for a change to be kept; run after metric |
| Iterations | `Iterations: N` | No | Max iterations (default: unbounded, runs until interrupted) |

### Experiment Log

All results are logged as JSONL to `.claude-octopus/experiments/<YYYY-MM-DD>.jsonl`.

Each line is a JSON object:
```json
{"iteration": 1, "timestamp": "2026-03-21T14:30:00Z", "metric": 72.5, "best": 72.5, "status": "kept", "description": "Add index to users table", "commit": "abc1234"}
```

Fields:
- `iteration` — iteration number (starting from 1; iteration 0 is baseline)
- `timestamp` — ISO 8601 timestamp
- `metric` — measured value from the metric command
- `best` — best metric value seen so far
- `status` — `"kept"` (improvement), `"reverted"` (regression), or `"error"` (metric/guard crashed)
- `description` — one-line summary of what was changed
- `commit` — short git SHA of the experiment commit (before potential revert)

### Execution Contract

You MUST follow this exact sequence for each iteration. No steps may be skipped or reordered.

#### Iteration 0: Establish Baseline

1. Create the experiment log directory if it does not exist:
   ```bash
   mkdir -p .claude-octopus/experiments
   ```
2. **Check for existing experiment log** — if `.claude-octopus/experiments/<today>.jsonl` exists, read it to determine the current best metric value and iteration count. Resume from the next iteration number.
3. Run the metric command and capture the output number. This is the **baseline**.
4. Log the baseline:
   ```json
   {"iteration": 0, "timestamp": "...", "metric": <baseline>, "best": <baseline>, "status": "baseline", "description": "Baseline measurement", "commit": "<current HEAD short SHA>"}
   ```
5. Report the baseline value to the user.

#### Each Subsequent Iteration (1..N)

**Step 1: Review state.** Read the experiment log (`.claude-octopus/experiments/<today>.jsonl`), review git history (`git log --oneline -10`), and identify what has been tried, what worked, and what failed.

**Step 2: Pick the next change.** Based on what worked/failed/is untried, decide on ONE focused change. Do NOT combine multiple unrelated changes.

**Step 3: Make the change.** Implement exactly one atomic change.

**Step 4: Git commit BEFORE verification.** Commit with the `experiment:` prefix:
```bash
git add -A && git commit -m "experiment: <one-line description of the change>"
```
This ensures every experiment is recorded in git history regardless of outcome.

**Step 5: Run mechanical verification.** Execute the metric command and capture the numeric result.

**Step 6: Evaluate and act.**

- **If metric improved** (higher when Direction=higher, lower when Direction=lower):
  - If a Guard command is specified, run it now.
    - If guard passes (exit 0) → **KEEP** the commit. Update best metric.
    - If guard fails (exit non-zero) → **REVERT**: `git revert HEAD --no-edit`. Log status as `"reverted"`.
  - If no guard → **KEEP** the commit. Update best metric.

- **If metric stayed the same:**
  - Check if the change reduces code complexity or size. If simpler → **KEEP** (simplicity wins).
  - Otherwise → **REVERT**: `git revert HEAD --no-edit`. Log status as `"reverted"`.

- **If metric worsened:**
  - **REVERT**: `git revert HEAD --no-edit`. Log status as `"reverted"`.

- **If metric command crashed (non-zero exit, no numeric output):**
  - Attempt a quick fix (one try only). If fix works, re-measure.
  - If still broken → **REVERT**: `git revert HEAD --no-edit`. Log status as `"error"`.

**Step 7: Log the result.** Append a JSONL entry to `.claude-octopus/experiments/<today>.jsonl`.

**Step 8: Report iteration summary.** Display:
```
Iteration N: <description>
  Metric: <value> (best: <best>) — <kept|reverted|error>
```

**Step 9: Repeat** — go to Step 1 of the next iteration, unless:
- Iterations limit reached → stop and report final summary
- User interrupts → stop and report final summary

### Resume Behavior

If an experiment log already exists for today:
1. Read the log to determine the last iteration number and current best metric value
2. Resume from the next iteration number
3. Use the recorded best value as the comparison baseline
4. This allows stopping and resuming experiments across sessions

### Final Summary

When the loop completes (iterations exhausted or user stops), report:

```
Experiment Complete
  Iterations: N
  Baseline: <initial metric>
  Final best: <best metric>
  Improvement: <delta> (<percentage>%)
  Kept: K changes, Reverted: R changes, Errors: E
```

### Example

```
/octo:loop Metric: npm test -- --coverage | grep 'All files' | awk '{print $10}' Direction: higher Guard: npm test Iterations: 20
```

This will:
1. Measure baseline code coverage percentage
2. Each iteration: make one change, commit as `experiment: ...`, measure coverage
3. If coverage improves AND `npm test` passes → keep
4. If coverage drops OR tests fail → `git revert HEAD --no-edit`
5. After 20 iterations, report total improvement

---

## The Bottom Line

```
Iterative loop → Clear goal + Max iterations + Progress tracking + Exit strategy
Otherwise → Infinite loops + Wasted effort + Unclear when done
```

**Define the goal. Set the limit. Track progress. Know when to stop.**
