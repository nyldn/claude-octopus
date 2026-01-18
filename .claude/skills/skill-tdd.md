---
name: skill-tdd
aliases:
  - tdd
  - test-driven-development
description: |
  Enforce TDD discipline: write failing test first, watch it fail, write minimal code.
  "Iron Law: NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST."
trigger: |
  Use when implementing any feature, bugfix, or behavior change.
  Auto-invoke when user says "implement X", "add feature Y", "fix bug Z".
  DO NOT use for: throwaway prototypes, config files, documentation.
---

# Test-Driven Development (TDD)

## The Iron Law

```
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
```

**Violating the letter of this rule is violating the spirit of this rule.**

Write code before the test? **Delete it. Start over.**

- Don't keep it as "reference"
- Don't "adapt" it while writing tests
- Don't look at it
- Delete means delete

## Red-Green-Refactor Cycle

```
   ┌─────────┐
   │   RED   │ ← Write ONE failing test
   └────┬────┘
        ↓
   ┌─────────┐
   │  VERIFY │ ← Watch it FAIL (mandatory)
   └────┬────┘
        ↓
   ┌─────────┐
   │  GREEN  │ ← Write MINIMAL code to pass
   └────┬────┘
        ↓
   ┌─────────┐
   │  VERIFY │ ← Watch it PASS (mandatory)
   └────┬────┘
        ↓
   ┌─────────┐
   │REFACTOR │ ← Clean up (stay green)
   └────┬────┘
        ↓
     [REPEAT]
```

## Phase 1: RED - Write Failing Test

Write ONE minimal test showing what should happen.

**Good Test:**
```typescript
test('retries failed operations 3 times', async () => {
  let attempts = 0;
  const operation = () => {
    attempts++;
    if (attempts < 3) throw new Error('fail');
    return 'success';
  };

  const result = await retryOperation(operation);

  expect(result).toBe('success');
  expect(attempts).toBe(3);
});
```
- Clear name describing behavior
- Tests real code, not mocks
- One thing only

**Bad Test:**
```typescript
test('retry works', async () => {  // Vague name
  const mock = jest.fn()           // Tests mock, not code
    .mockRejectedValueOnce(new Error())
    .mockResolvedValueOnce('success');
  // ...
});
```

## Phase 2: VERIFY RED - Watch It Fail

**MANDATORY. Never skip.**

```bash
npm test path/to/test.test.ts
```

Confirm:
- Test **fails** (not errors)
- Failure message is what you expected
- Fails because feature is **missing** (not typos)

| Outcome | Action |
|---------|--------|
| Test passes | You're testing existing behavior. Fix the test. |
| Test errors | Fix error, re-run until it fails correctly. |
| Test fails correctly | Proceed to GREEN. |

## Phase 3: GREEN - Minimal Code

Write the **simplest** code to pass the test. Nothing more.

**Good:**
```typescript
async function retryOperation<T>(fn: () => Promise<T>): Promise<T> {
  for (let i = 0; i < 3; i++) {
    try { return await fn(); }
    catch (e) { if (i === 2) throw e; }
  }
  throw new Error('unreachable');
}
```

**Bad (YAGNI violation):**
```typescript
async function retryOperation<T>(
  fn: () => Promise<T>,
  options?: {
    maxRetries?: number;           // Not needed yet
    backoff?: 'linear' | 'expo';   // Not needed yet
    onRetry?: (n: number) => void; // Not needed yet
  }
): Promise<T> { /* ... */ }
```

## Phase 4: VERIFY GREEN - Watch It Pass

**MANDATORY.**

```bash
npm test path/to/test.test.ts
```

Confirm:
- Test passes
- **All other tests** still pass
- Output is clean (no errors, warnings)

| Outcome | Action |
|---------|--------|
| Test fails | Fix the code, not the test. |
| Other tests fail | Fix them now. |
| All pass | Proceed to REFACTOR. |

## Phase 5: REFACTOR - Clean Up

**Only after GREEN:**
- Remove duplication
- Improve names
- Extract helpers

**Keep tests green throughout. Don't add new behavior.**

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "Too simple to test" | Simple code breaks. Test takes 30 seconds. |
| "I'll test after" | Tests passing immediately prove nothing. |
| "Already manually tested" | Ad-hoc ≠ systematic. No record, can't re-run. |
| "Deleting X hours is wasteful" | Sunk cost fallacy. Unverified code is debt. |
| "Need to explore first" | Fine. Throw away exploration, start with TDD. |
| "TDD will slow me down" | TDD is faster than debugging. |

## Red Flags - STOP and Start Over

If you catch yourself:
- Writing code before test
- Test passes immediately (didn't watch it fail)
- Rationalizing "just this once"
- "I already manually tested it"
- "Keep as reference" or "adapt existing code"
- "This is different because..."

**ALL of these mean: Delete code. Start over with TDD.**

## Bug Fix Example

**Bug:** Empty email accepted

**RED:**
```typescript
test('rejects empty email', async () => {
  const result = await submitForm({ email: '' });
  expect(result.error).toBe('Email required');
});
```

**VERIFY RED:**
```bash
$ npm test
FAIL: expected 'Email required', got undefined
```

**GREEN:**
```typescript
function submitForm(data: FormData) {
  if (!data.email?.trim()) {
    return { error: 'Email required' };
  }
  // ...
}
```

**VERIFY GREEN:**
```bash
$ npm test
PASS
```

## Verification Checklist

Before marking work complete:

- [ ] Every new function/method has a test
- [ ] Watched each test fail before implementing
- [ ] Each test failed for expected reason
- [ ] Wrote minimal code to pass each test
- [ ] All tests pass
- [ ] Output clean (no errors, warnings)

**Can't check all boxes? You skipped TDD. Start over.**

## Integration with Claude Octopus

When using octopus workflows:

| Workflow | TDD Integration |
|----------|-----------------|
| `probe` (research) | Research testing patterns for the domain |
| `grasp` (define) | Define test requirements in spec |
| `tangle` (develop) | **Enforce TDD for each implementation task** |
| `ink` (deliver) | Verify all tests pass before delivery |
| `squeeze` (security) | Red team tests security controls |

## When Stuck

| Problem | Solution |
|---------|----------|
| Don't know how to test | Write the API you wish existed. Assert first. |
| Test too complicated | Design too complicated. Simplify interface. |
| Must mock everything | Code too coupled. Use dependency injection. |
| Test setup huge | Extract helpers. Still complex? Simplify design. |

## The Bottom Line

```
Production code exists → Test exists that failed first
Otherwise → Not TDD
```

No exceptions without explicit user permission.
