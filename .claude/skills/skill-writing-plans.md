---
name: skill-writing-plans
description: |
  Create zero-context implementation plans with bite-sized tasks (2-5 min each).
  Assumes engineer has no codebase knowledge. Exact file paths, complete code, verification steps.
trigger: |
  Use when you have a spec or requirements for a multi-step task.
  Auto-invoke when user says "plan how to implement X", "create implementation plan", 
  "break down this feature into tasks".
  Use BEFORE writing any implementation code.
---

# Writing Plans

## Overview

Write comprehensive implementation plans assuming the engineer has **zero context** for the codebase and **questionable taste**.

Document everything: which files to touch, complete code, how to test, how to verify.

**Principles:** DRY. YAGNI. TDD. Frequent commits.

---

## Plan Document Structure

### Header (Required)

```markdown
# [Feature Name] Implementation Plan

**Goal:** [One sentence describing what this builds]

**Architecture:** [2-3 sentences about approach]

**Tech Stack:** [Key technologies/libraries]

**Estimated Time:** [X tasks × 5 min = Y minutes]

---

## Prerequisites

- [ ] [Any setup needed before starting]
- [ ] [Dependencies to install]
- [ ] [Files that must exist]
```

---

## Task Granularity

**Each task is ONE action (2-5 minutes):**

| Good (Single Action) | Bad (Multiple Actions) |
|---------------------|------------------------|
| "Write the failing test" | "Write tests and implement" |
| "Run test to verify it fails" | "Make it work" |
| "Implement minimal code to pass" | "Add the feature" |
| "Commit with message" | "Finish the feature" |

---

## Task Template

```markdown
### Task N: [Component Name]

**Files:**
- Create: `exact/path/to/new-file.ts`
- Modify: `exact/path/to/existing.ts` (lines 45-67)
- Test: `tests/exact/path/to/test.spec.ts`

**Step 1: Write failing test**

```typescript
// tests/exact/path/to/test.spec.ts
describe('ComponentName', () => {
  it('should do specific thing', () => {
    const result = functionName(input);
    expect(result).toBe(expected);
  });
});
```

**Step 2: Run test to verify it fails**

```bash
npm test tests/exact/path/to/test.spec.ts
```

Expected output:
```
FAIL: expected 'expected' but got undefined
```

**Step 3: Implement minimal code**

```typescript
// exact/path/to/new-file.ts
export function functionName(input: InputType): OutputType {
  // Minimal implementation
  return expected;
}
```

**Step 4: Run test to verify it passes**

```bash
npm test tests/exact/path/to/test.spec.ts
```

Expected output:
```
PASS: 1/1 tests passed
```

**Step 5: Commit**

```bash
git add tests/exact/path/to/test.spec.ts exact/path/to/new-file.ts
git commit -m "feat(component): add specific functionality"
```

---
```

---

## Example: Complete Task

```markdown
### Task 3: Add Email Validation

**Files:**
- Create: `src/validators/email.ts`
- Test: `tests/validators/email.spec.ts`

**Step 1: Write failing test**

```typescript
// tests/validators/email.spec.ts
import { validateEmail } from '../src/validators/email';

describe('validateEmail', () => {
  it('returns error for empty email', () => {
    const result = validateEmail('');
    expect(result).toEqual({ valid: false, error: 'Email required' });
  });

  it('returns error for invalid format', () => {
    const result = validateEmail('not-an-email');
    expect(result).toEqual({ valid: false, error: 'Invalid email format' });
  });

  it('returns valid for correct email', () => {
    const result = validateEmail('user@example.com');
    expect(result).toEqual({ valid: true });
  });
});
```

**Step 2: Run test to verify it fails**

```bash
npm test tests/validators/email.spec.ts
```

Expected: `Cannot find module '../src/validators/email'`

**Step 3: Implement minimal code**

```typescript
// src/validators/email.ts
interface ValidationResult {
  valid: boolean;
  error?: string;
}

export function validateEmail(email: string): ValidationResult {
  if (!email || !email.trim()) {
    return { valid: false, error: 'Email required' };
  }

  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  if (!emailRegex.test(email)) {
    return { valid: false, error: 'Invalid email format' };
  }

  return { valid: true };
}
```

**Step 4: Run test to verify it passes**

```bash
npm test tests/validators/email.spec.ts
```

Expected: `PASS: 3/3 tests passed`

**Step 5: Commit**

```bash
git add src/validators/email.ts tests/validators/email.spec.ts
git commit -m "feat(validators): add email validation with tests"
```
```

---

## Integration with Claude Octopus

### Using Octopus for Plan Execution

After creating a plan, offer execution options:

```markdown
## Execution Options

**1. Sequential (this session)**
Execute tasks one by one with verification between each.

**2. Parallel (octopus tangle)**
Use Claude Octopus to parallelize independent tasks:
```bash
./scripts/orchestrate.sh tangle "Execute implementation plan for [feature]"
```

**3. Full workflow (octopus embrace)**
Research → Define → Implement → Deliver:
```bash
./scripts/orchestrate.sh embrace "Implement [feature] per plan"
```
```

### Plan Storage (Claude Code v2.1.10)

Claude Octopus uses session-aware plan storage. Plans are automatically saved to:

```
~/.claude-octopus/plans/${CLAUDE_SESSION_ID}/YYYY-MM-DD-feature-name.md
```

This integrates with Claude Code's `plansDirectory` setting. To customize:

```json
// settings.json
{
  "plansDirectory": "~/.claude-octopus/plans"
}
```

For project-local plans, save to `docs/plans/`:

```bash
mkdir -p docs/plans
# docs/plans/2026-01-17-user-authentication.md
```

---

## Checklist for Good Plans

- [ ] Each task is 2-5 minutes (single action)
- [ ] Exact file paths (not "in the utils folder")
- [ ] Complete code (not "add validation logic")
- [ ] Exact commands with expected output
- [ ] TDD: test before implementation
- [ ] Commit after each task

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| "Add the validation" | Show exact code |
| "Update the tests" | Show exact test code |
| "In the config file" | `config/app.config.ts` line 23 |
| "Run the tests" | `npm test path/to/specific.spec.ts` |
| Large tasks (30+ min) | Break into 2-5 min steps |
| No verification | Add "Run X, expect Y" |

---

## When to Create Plans

| Scenario | Use Plan? |
|----------|-----------|
| Multi-step feature (3+ tasks) | Yes |
| Simple bug fix (1 task) | No, just do it |
| Uncertain scope | Yes (clarifies thinking) |
| Delegation to subagent | Yes (zero-context execution) |
| Complex refactoring | Yes |
| Config change | No |

---

## Related Skills

- **test-driven-development** - Each task follows TDD cycle
- **verification-before-completion** - Verify each step
- **finishing-branch** - After all tasks complete

---

## The Bottom Line

```
Plan exists → Engineer with zero context can execute
Otherwise → Not a complete plan
```

**Exact paths. Complete code. Verification steps. No assumptions.**
