---
command: staged-review
description: "Two-stage review: spec compliance then code quality"
aliases:
  - two-stage-review
  - full-review
---

# Staged Review — Two-Stage Pipeline

## 🤖 INSTRUCTIONS FOR CLAUDE

### MANDATORY COMPLIANCE — DO NOT SKIP

**When the user explicitly invokes `/octo:staged-review`, you MUST execute the structured workflow below.** You are PROHIBITED from doing the task directly, skipping the review phases, or deciding the task is "too simple" for this workflow. The user chose this command deliberately — respect that choice.

### EXECUTION MECHANISM — NON-NEGOTIABLE

**You MUST dispatch work to external providers (Codex, Gemini, etc.) for this command. You are PROHIBITED from:**
- ❌ Executing the entire task using only Claude-native tools
- ❌ Using a single Agent subagent instead of multi-provider dispatch
- ❌ Skipping provider dispatch because "I can handle this alone"

**Multi-LLM orchestration is the purpose of this command.** Single-model execution defeats its purpose.

---

🐙 **CLAUDE OCTOPUS ACTIVATED** — Two-Stage Review Pipeline

---

When the user invokes this command (e.g., `/octo:staged-review` or `/octo:staged-review src/auth/`):

## Step 1: Determine Review Scope

```javascript
AskUserQuestion({
  questions: [
    {
      question: "What should be reviewed?",
      header: "Review Scope",
      multiSelect: false,
      options: [
        {label: "Staged changes", description: "git diff --cached — what you're about to commit"},
        {label: "Recent commit", description: "Changes in the last commit (HEAD~1..HEAD)"},
        {label: "Working tree", description: "All uncommitted changes"},
        {label: "Specific path", description: "A file or directory (provide path as argument)"}
      ]
    }
  ]
})
```

If invoked with arguments (e.g., `/octo:staged-review src/auth/`), use that path directly and skip the question.

## Step 2: Execute Staged Review

Read and follow the full skill instructions from:
`${HOME}/.claude-octopus/plugin/.claude/skills/skill-staged-review.md`

The skill runs two stages:
1. **Stage 1** (Spec Compliance) — Validate against intent contract
2. **Gate check** — Stage 1 must pass before Stage 2
3. **Stage 2** (Code Quality) — Stub detection + multi-LLM quality review (Codex for logic, Gemini for security, Claude for architecture — synthesized into unified findings)
4. **Combined report** — Unified verdict

### Post-Completion — Interactive Next Steps

**CRITICAL: After the skill completes, you MUST ask the user what to do next.**

```javascript
AskUserQuestion({
  questions: [
    {
      question: "Review complete. What would you like to do?",
      header: "Next Steps",
      multiSelect: false,
      options: [
        {label: "Fix blocking issues", description: "Address the issues flagged in the review"},
        {label: "Run /octo:review", description: "Follow up with full multi-LLM review"},
        {label: "Post to PR", description: "Post the review findings to the open PR"},
        {label: "Done", description: "No further action needed"}
      ]
    }
  ]
})
```

## Related Commands

- `/octo:review` — Expert multi-LLM code review with inline PR comments
- `/octo:deliver` — Full delivery phase with validation and testing
- `/octo:develop` — Development phase with quality gates

## Validation Gates

- Review scope determined (from arguments or user input)
- Skill loaded and executed (not simulated)
- Combined report presented to user
- Next steps offered

### Prohibited Actions

- Simulating the review without running the skill
- Skipping Stage 1 when an intent contract exists
- Ending without presenting next steps
