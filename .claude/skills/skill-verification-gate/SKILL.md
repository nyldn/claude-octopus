---
name: skill-verification-gate
effort: low
description: "Evidence before claims — run verification commands before declaring work complete, fixed, or passing"
trigger: |
  AUTOMATICALLY ACTIVATE when:
  - About to claim work is complete, fixed, or passing
  - Before committing, creating PRs, or marking tasks done
  - After subagent reports success (verify independently)
  - Before moving to next task in a workflow
paths:
  - "**/test*"
  - "**/*.test.*"
---

# Verification Gate

## The Iron Law

```
NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE
```

If you haven't run the verification command in this turn, you cannot claim it passes.

## The Gate

Before claiming any success or expressing satisfaction:

1. **IDENTIFY** — What command proves this claim?
2. **RUN** — Execute the full command (fresh, not cached)
3. **READ** — Full output, check exit code, count failures
4. **VERIFY** — Does output actually confirm the claim?
5. **ONLY THEN** — State the claim WITH evidence

Skip any step = the claim is unverified.

## What Counts as Evidence

| Claim | Requires | NOT Sufficient |
|-------|----------|----------------|
| Tests pass | Test command output showing 0 failures | Previous run, "should pass" |
| Build succeeds | Build command exit 0 | Linter passing |
| Bug fixed | Reproduce original symptom: now passes | "Code changed, should work" |
| Regression test works | Red (fail without fix) → Green (pass with fix) | Test passes once |
| Subagent completed task | `git diff` shows expected changes | Subagent says "done" |
| Requirements met | Line-by-line checklist against spec | Tests passing |
| Provider dispatch worked | Output contains expected content | No error ≠ success |

## Red Flags — STOP and Verify

If you catch yourself thinking any of these, STOP:

| Thought | What to do instead |
|---------|-------------------|
| "Should work now" | Run the verification |
| "I'm confident" | Confidence ≠ evidence |
| "Just this once" | No exceptions |
| "The linter passed" | Linter ≠ tests ≠ build |
| "The agent said it worked" | Verify independently |
| "It's a small change" | Small changes cause big bugs |

## Multi-Provider Context

In Claude Octopus workflows, verification is especially critical because:

- **Provider outputs can be hallucinated** — Codex/Gemini/Copilot may claim success without evidence
- **Consensus ≠ correctness** — three models agreeing doesn't mean they're right
- **Synthesis files may be stale** — check timestamps, don't assume freshness
- **orchestrate.sh exit code 0 ≠ quality** — the script ran, but did it produce good output?

After any multi-provider workflow:
```bash
# Verify synthesis file exists and is recent
ls -la ~/.claude-octopus/results/*-synthesis-*.md | tail -1

# Verify it has content (not just headers)
wc -l ~/.claude-octopus/results/*-synthesis-*.md | tail -1
```

## When to Apply

**ALWAYS before:**
- Committing code
- Creating PRs
- Marking tasks complete
- Moving to next workflow phase
- Reporting results to user
- Claiming a bug is fixed

**In orchestrate.sh workflows:**
- After `probe` (discover) — verify synthesis file exists
- After `grasp` (define) — verify consensus score meets threshold
- After `tangle` (develop) — verify tests pass, not just that code was written
- After `ink` (deliver) — verify review actually ran, not just that it was dispatched

## Examples

### Correct: Evidence-Based Claim
```
$ npm test
  ✓ user.create() saves to database (45ms)
  ✓ user.create() validates email (12ms)
  Tests: 2 passed, 2 total

All 2 tests pass. ← Claim backed by output.
```

### Incorrect: Claim Without Evidence
```
I've implemented the feature. It should work now. The tests should pass.
← No test was run. "Should" is not evidence.
```

### Correct: Regression Test Red-Green
```
1. Write test → run → FAIL (expected, proves test detects the bug)
2. Implement fix → run → PASS (proves fix works)
3. Revert fix → run → FAIL (proves test isn't false-positive)
4. Restore fix → run → PASS (final confirmation)
```

## Integration with Other Skills

This skill is referenced by:
- `flow-develop.md` — verification gate after implementation
- `flow-deliver.md` — verification gate before delivery
- `skill-code-review.md` — verify review findings before reporting
- `skill-tdd.md` — red-green cycle requires evidence at each step
- `skill-factory.md` — autonomous pipeline must verify at every phase
