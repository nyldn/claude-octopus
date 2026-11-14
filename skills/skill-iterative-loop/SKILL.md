---
name: skill-iterative-loop
disable-model-invocation: true
aliases:
  - iterative-loop
  - loop-execution
  - repeat-until
description: "Run tasks in a loop until goals are met — use for iterative refinement, polling, or convergence"
trigger: |
  EXPLICITLY USE when user requests iterative execution:
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

For metric runs, Metric Verification Mode replaces the general iteration limits
and 30-minute continue prompt below. Its stop budgets cannot be extended by a
checkpoint. Self-regulation revert counters do not apply because metric runs
forbid reverts in the original workspace.

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

When the user supplies `Metric: <command>`, use mechanical measurement in a
bounded candidate-copy experiment. Without a metric, use the normal loop above.

### Scope and budgets

Freeze the metric, direction, guard, and authorized editable paths before the
baseline. The guard is optional. Without a guard, accept only a measured
improvement and report that no guard ran; do not claim safety validation.
Defaults are five iterations, 30 elapsed minutes, and 14 additional
model calls. `Iterations: N` accepts integers 1 through 20. `Minutes: N` and
`Calls: N` accept positive integers. Explicit choices replace those defaults;
invalid options stop before edits or calls. Stop at the first exhausted budget
or after two rounds without measured improvement. Metric and guard subprocesses
must have deadlines no longer than the remaining elapsed budget. If the host
cannot enforce a subprocess deadline, report the missing capability and stop.
Charge retries, research, and model-assisted edits to the call budget before
dispatch. Never reset elapsed time or consumed calls on resume.

| Parameter | Meaning |
|-----------|---------|
| `Metric: <command>` | Must print one finite number |
| `Direction: higher` or `Direction: lower` | Select the improving direction |
| `Guard: <command>` | Optional. When supplied, must exit zero to accept a candidate |
| `Iterations: N`, `Minutes: N`, `Calls: N` | Override the finite defaults above |

### Preserve the user's workspace

Inspect repository status, including the staged index, dirty tracked files, and
untracked files. Snapshot the exact authorized input bytes and their hashes.
Create a unique private run directory outside the working repository, with
separate original, best, and candidate copies. Never operate on unrelated paths.
If the metric needs the whole repository, create a disposable isolated copy
containing the required authorized baseline, including relevant existing edits.
Do not silently substitute HEAD for a dirty baseline. If the host cannot create
that faithful isolated baseline without exposing unrelated data, stop and name
the limitation. Reject symlinks that would let experiments modify original files.

Do not stage, commit, stash, reset, clean, or revert the user's repository as
part of an experiment. In particular, never use blanket staging. Git history is
not the experiment store. Preserve the original index exactly.

### Execute and record

1. In the isolated baseline, run the metric and any supplied guard with deadlines.
   A baseline failure must be reported; it is not evidence that a later change is safe.
2. Record baseline hashes, metric, guard evidence, start time, budget limits,
   and consumed calls in the run's append-only `iterations.jsonl`.
3. Before each iteration, check remaining time, iterations, and calls. Copy the
   best candidate into a new candidate directory and make one scoped change.
4. Run the same metric and any supplied guard. Keep only a measured improvement
   whose guard passes when supplied. Without a guard, report that no guard ran
   and do not claim safety validation. On equal results, keep the simpler
   candidate only with evidence of reduced complexity. Failed, unverified, or worse candidates are rejected.
5. Reject by discarding only the owned candidate directory; never undo changes
   in the original workspace. Preserve logs for rejected and failed attempts.
6. Stop on budget exhaustion, two stalled rounds, cancellation, or missing
   evidence. Report the best measured result without claiming the target passed
   when required validation is missing.

Before publishing the best candidate, re-read every destination and verify it
still matches the snapshot taken at the start. Also verify the repository HEAD
and index have not changed. On a concurrent edit or index change, stop and
preserve the candidate for review. Publish only the exact authorized files,
then rerun the required checks against delivered bytes. Do not create a commit
unless the user separately requested one.

Example ledger record, with paths and hashes referring only to this run:

```json
{"iteration":1,"timestamp":"2026-11-07T12:00:00Z","metric":72.5,"best":72.5,"status":"kept","description":"One measured change","artifact_sha256":"<candidate hash>","elapsed_seconds":45,"calls_used":1}
```

Use `kept`, `rejected`, or `error` for attempted rounds. Preserve rejected
candidate evidence and failed guard outputs without changing the original.

### Resume and reporting

Resume only from the explicitly selected run directory, never from a shared
per-day log. Verify its artifact hashes, frozen metric and guard, limits,
elapsed start time, consumed calls, best candidate, and publication state.
A changed contract requires a new baseline within the remaining budget.
If elapsed budget expired while interrupted, report that stop without dispatch.
Report baseline and each attempted round, actual checks, accepted/rejected
changes, consumption, delivered hashes, and the stop reason. Unknown monetary
cost stays unknown. These are host-managed steps, not an executable supervisor.

## The Bottom Line

```
Iterative loop → Clear goal + Max iterations + Progress tracking + Exit strategy
Otherwise → Infinite loops + Wasted effort + Unclear when done
```

**Define the goal. Set the limit. Track progress. Know when to stop.**
