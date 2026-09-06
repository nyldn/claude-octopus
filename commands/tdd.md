---
command: tdd
disable-model-invocation: true
description: Test-driven development with observed red and green evidence
---

# Octopus TDD

Load and follow
`${HOME}/.claude-octopus/plugin/.claude/skills/skill-tdd/SKILL.md`.

Treat `--peer-review` as an instruction to request one bounded independent test
design review through existing Octopus routing. Do not pass the token or the
remaining user text into a shell command. Without that flag or an explicit
multi-model request, run the full method on the current host with zero additional
provider dispatches.

## Step 1: Ask Clarifying Questions when needed

Do not interrupt a well-specified task. If the repository and request leave a
material choice unresolved, use `AskUserQuestion` for only the unanswered items
from this intake:

```javascript
AskUserQuestion({
  questions: [
    {
      question: "Which coverage boundary should prove the observable behavior?",
      header: "Coverage",
      multiSelect: false,
      options: [
        {label: "Public API", description: "Prove behavior at the caller-facing API."},
        {label: "Integration", description: "Prove behavior across component boundaries."},
        {label: "User flow", description: "Prove the complete user-visible path."}
      ]
    },
    {
      question: "Which test style should carry the regression?",
      header: "Test style",
      multiSelect: false,
      options: [
        {label: "Unit", description: "Use the narrowest stable public boundary."},
        {label: "Integration", description: "Exercise the real collaborating components."},
        {label: "End to end", description: "Exercise the supported runtime path."}
      ]
    },
    {
      question: "What complexity and risk level does this change carry?",
      header: "Complexity",
      multiSelect: false,
      options: [
        {label: "Focused", description: "Run the focused test and directly affected suite."},
        {label: "Standard", description: "Add the repository's normal changed-file gates."},
        {label: "High risk", description: "Add integration, race, or security coverage."}
      ]
    }
  ]
})
```

After receiving answers, incorporate them into the test boundary, test layer,
and validation depth. Repository evidence still takes precedence over a generic
coverage target.

Before implementation, state the behavior under test and show the observed red
failure. After implementation, show the focused green result and the affected
suite result. If tests are consolidated, include the behavior ledger and five-run
timings. Do not ask generic coverage questions when the repository and request
already establish the needed scope.
