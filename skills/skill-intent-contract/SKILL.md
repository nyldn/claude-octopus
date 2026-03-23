---
name: skill-intent-contract
version: 1.0.0
description: "Capture user goals, success criteria, and boundaries upfront as a persistent intent contract, then validate outputs against them at workflow completion. Use when: user invokes a major workflow (/octo:embrace, /octo:discover, /octo:plan), asks to 'plan' or 'set goals' for a multi-phase task, or scope drift needs to be prevented."
---

# Intent Contract System

Create a persistent record of user intent in `.claude/session-intent.md` that captures goals, success criteria, and boundaries — then validate final outputs against them.

---

## Intent Contract Structure

```markdown
# Intent Contract
**Created**: [ISO timestamp]
**Workflow**: [discover/embrace/review/etc.]
**Status**: [active/validating/completed]

## Job Statement
[User's goal in plain language]

## Success Criteria
### Good Enough
- [Minimum viable criterion]
### Exceptional
- [Excellence criterion]

## Boundaries
- [What to avoid / out of scope]

## Context & Constraints
**Stakeholders**: [Who] | **Timeline**: [When] | **Technical**: [Platform/deps]

## Validation Checklist
- [ ] Meets "good enough" criteria
- [ ] Respects all boundaries
- [ ] Works for all stakeholders
```

**Do NOT create for:** Quick single-action commands, simple file reads, or conversational questions.

---

## Implementation

### Step 1: Capture Intent

After clarifying questions, use AskUserQuestion to gather:
1. **Goal** — What the user is trying to accomplish (JTBD)
2. **Success criteria** — What defines "good enough" and "exceptional"
3. **Boundaries** — What this should NOT be or do

### Step 2: Write Intent Contract

Create `.claude/session-intent.md` with the captured information.

### Step 3: Reference During Execution

Periodically read the intent contract at key decision points:
```
Checking against intent contract: [reference specific criterion]
```

### Step 4: Validate at End

Check each success criterion (met/not met/partial) and each boundary (respected/violated). Generate a validation report:

```markdown
# Validation Report
## Success Criteria Check
- [✓/✗/~] Criterion: [Explanation]
## Boundary Check
- [✓/✗] Boundary: [Explanation]
## Gaps & Next Steps
## Overall Assessment
```

### Step 5: Update Status

Update `Status` in the intent contract: `active` → `validating` → `completed` or `incomplete`.

---

## Workflow Integration

| Workflow | Intent Contract Flow |
|----------|---------------------|
| Embrace | Create after clarifying Qs → reference in all 4 phases → validate at end |
| Discover | Create after clarifying Qs → reference during research → validate at synthesis |
| Plan | Capture comprehensive intent → route to workflows → validate at end |
