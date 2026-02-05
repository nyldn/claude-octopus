---
name: skill-verify
description: "Evidence gate: verify before claiming success"
trigger: |
  Use when about to claim work is complete, fixed, or passing.
  Auto-invoke before: commits, PRs, task completion, moving to next task.
  ALWAYS use before expressing satisfaction ("Done!", "Fixed!", "All passing!").
execution_mode: enforced
pre_execution_contract:
  - visual_indicators_displayed
validation_gates:
  - orchestrate_sh_executed
  - output_artifact_exists
---

# Verification Before Completion

## The Iron Law

```
NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE
```

Claiming work is complete without verification is dishonesty, not efficiency.

**If you haven't run the verification command in this message, you cannot claim it passes.**

---

## The Gate Function

```
BEFORE claiming any status or expressing satisfaction:

1. IDENTIFY → What command proves this claim?
2. RUN      → Execute the FULL command (fresh, complete)
3. READ     → Full output, check exit code, count failures
4. VERIFY   → Does output confirm the claim?
               - If NO: State actual status with evidence
               - If YES: State claim WITH evidence
5. CLAIM    → ONLY THEN make the claim

Skip any step = lying, not verifying
```

---

## What Requires Verification

| Claim | Requires | NOT Sufficient |
|-------|----------|----------------|
| "Tests pass" | Test output showing 0 failures | Previous run, "should pass" |
| "Linter clean" | Linter output showing 0 errors | Partial check, extrapolation |
| "Build succeeds" | Build command exit code 0 | Linter passing |
| "Bug fixed" | Original symptom no longer occurs | "Code changed" |
| "Regression test works" | Red-green cycle verified | Test passes once |
| "Requirements met" | Line-by-line checklist | Tests passing |

---

## Examples

### Correct: Evidence-Based Claim
```
Running tests...
$ npm test

  ✓ user.create() saves to database (45ms)
  ✓ user.create() validates email (12ms)
  ✓ user.create() hashes password (23ms)

Tests: 3 passed, 3 total
Time: 0.8s

All 3 tests pass. Ready for review.
```

### Incorrect: Claim Without Evidence
```
I've implemented the user creation feature. It should work now.
The tests should pass.
```

### Correct: Regression Test Red-Green
```
1. Write test:
   test('rejects empty email', () => { ... })

2. Run test (should FAIL):
   $ npm test
   FAIL: expected 'Email required', got undefined
   ✓ Test fails as expected

3. Implement fix

4. Run test (should PASS):
   $ npm test
   PASS: 1/1
   ✓ Test passes

5. Revert fix temporarily:
   $ git stash
   $ npm test
   FAIL: expected 'Email required', got undefined
   ✓ Confirms test catches the bug

6. Restore fix:
   $ git stash pop
   $ npm test
   PASS: 1/1

Red-green cycle verified. Regression test is valid.
```

---

## Red Flags - STOP

If you catch yourself:
- Using "should", "probably", "seems to"
- Expressing satisfaction before verification ("Great!", "Done!")
- About to commit/push/PR without running tests
- Trusting that previous run is still valid
- Thinking "just this once"

**ALL of these mean: STOP. Run verification first.**

---

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "Should work now" | RUN the verification. |
| "I'm confident" | Confidence ≠ evidence. |
| "Just this once" | No exceptions. |
| "Linter passed" | Linter ≠ tests ≠ build. |
| "I'm tired" | Exhaustion ≠ excuse. |
| "Partial check is enough" | Partial proves nothing. |

---

## Verification Commands by Type

### Tests
```bash
# Run and capture output
npm test                  # JavaScript/TypeScript
pytest                    # Python
cargo test                # Rust
go test ./...             # Go

# Expected: "X passed, 0 failed"
```

### Build
```bash
npm run build             # Node.js
cargo build --release     # Rust
go build ./...            # Go

# Expected: Exit code 0, no errors
```

### Linting
```bash
npm run lint              # ESLint
ruff check .              # Python
cargo clippy              # Rust

# Expected: 0 errors (warnings OK)
```

### Type Checking
```bash
npm run typecheck         # TypeScript
mypy .                    # Python
cargo check               # Rust

# Expected: 0 errors
```

---

## Integration with Claude Octopus

### Quality Gates

Octopus workflows have built-in quality gates:

| Workflow | Verification Point |
|----------|-------------------|
| `tangle` | 75% success threshold before proceeding |
| `ink` | Full test suite before delivery |
| `squeeze` | Red team validation before clearance |

### Before Octopus Phase Transitions

```bash
# Before moving from tangle → ink
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh preflight

# Verifies:
# - All agents completed
# - Quality gate passed
# - No errors in logs
```

### Before PR Creation

```bash
# Full verification before PR
npm test && npm run lint && npm run build

# Then create PR with evidence
gh pr create --body "$(cat <<'EOF'
## Verification
- Tests: 42/42 passing
- Lint: 0 errors
- Build: Success
EOF
)"
```

---

## Checklist Before Claiming Complete

- [ ] Ran test command in THIS session
- [ ] Read FULL output (not just summary)
- [ ] Exit code was 0
- [ ] No failures, errors, or warnings
- [ ] No skipped tests that matter
- [ ] Evidence included in claim

**Missing any checkbox? Do not claim completion.**

---

## The Bottom Line

```
Claiming success → Verification evidence exists in this message
Otherwise → Not verified
```

**Run the command. Read the output. THEN claim the result.**

No shortcuts for verification. This is non-negotiable.
