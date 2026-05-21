---
name: skill-review-response
description: "How to handle code review feedback — verify before implementing, push back when wrong, never agree blindly"
trigger: |
  AUTOMATICALLY ACTIVATE when:
  - Receiving code review feedback (PR comments, review agent output)
  - Processing suggestions from /octo:review or /octo:staged-review
  - Responding to CI failure feedback
  - Handling changes-requested status on a PR
paths:
  - ".git/**"
---

# Receiving Code Review

## Core Principle

Code review requires technical evaluation, not performative agreement.

**Never blindly implement review feedback.** Verify it's correct for THIS codebase before changing anything.

## The Response Pattern

```
WHEN receiving code review feedback:

1. READ    — Complete feedback without reacting
2. RESTATE — Summarize the requirement in your own words
3. VERIFY  — Check against actual codebase state
4. EVALUATE — Is this technically sound for THIS context?
5. RESPOND — Technical acknowledgment OR reasoned pushback
6. IMPLEMENT — One item at a time, verify each change
```

## Forbidden Responses

**NEVER say:**
- "You're absolutely right!" (without verification)
- "Great catch!" (before confirming it IS a catch)
- "I'll fix that right away!" (before evaluating whether it needs fixing)
- "Done!" (without running verification — see skill-verification-gate)

**These are social performance, not technical evaluation.** They lead to:
- Implementing wrong suggestions
- Introducing bugs to "fix" non-issues
- Wasting time on style preferences disguised as bugs

## Evaluation Checklist

For each piece of feedback:

| Question | If YES | If NO |
|----------|--------|-------|
| Is the issue real? (verify in code) | Continue evaluation | Push back with evidence |
| Does the suggested fix work here? | Continue evaluation | Propose alternative |
| Does fixing this break something else? | Fix both or push back | Implement the fix |
| Is this a style preference or a real problem? | Acknowledge, deprioritize | Fix it |
| Was this already considered and rejected? | Explain the trade-off | Implement |

## How to Push Back

When feedback is wrong or doesn't apply:

```markdown
> Reviewer: "This function should handle null input"
>
> Response: "Checked — this function is only called from `processUser()`
> (line 47) which validates non-null before dispatch. Adding null handling
> here would be dead code. The caller contract guarantees non-null."
```

Provide:
1. What you checked
2. Why the suggestion doesn't apply
3. Evidence (line numbers, call sites, tests)

## Multi-Provider Review Context

In Claude Octopus workflows, review feedback comes from multiple sources:

- **Codex review** — tends toward enterprise patterns, may over-engineer
- **Gemini review** — tends toward ecosystem conformity, may suggest unnecessary deps
- **Claude review** — tends toward elegance, may under-engineer error handling
- **Sonnet review** — tends toward thoroughness, may flag low-priority issues

When providers disagree:
- Check which provider's suggestion matches the ACTUAL codebase conventions
- The codebase's existing patterns win over any provider's preferences
- If two providers flag the same issue, it's probably real

## Handling Feedback Loops

When a reviewer flags an issue and you fix it:

1. Make the fix
2. **Run verification** (skill-verification-gate) — prove the fix works
3. **Re-read the original feedback** — did you address the root cause or just the symptom?
4. If the reviewer re-reviews and finds new issues, that's normal — don't get frustrated
5. Each round should have FEWER issues, not different ones

If the same issue keeps coming back:
- You're fixing symptoms, not the root cause
- Stop and re-read the feedback from scratch
- Ask the reviewer to clarify if the issue is ambiguous

## When Review Feedback Conflicts with Requirements

If a reviewer suggests something that contradicts the spec/requirements:

1. Note the conflict explicitly
2. Check if the spec is wrong (it might be)
3. If spec is correct: implement the spec, note the reviewer's concern for future consideration
4. If spec is wrong: flag to the user before changing anything

**Requirements trump review suggestions. User intent trumps both.**
