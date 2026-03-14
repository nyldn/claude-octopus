---
command: review
description: Expert multi-LLM code review with inline PR comments — competes with CC Code Review
---

# /octo:review

🐙 **CLAUDE OCTOPUS ACTIVATED** — Multi-LLM Code Review

Providers:
🔴 Codex CLI — logic and correctness
🟡 Gemini CLI — security and edge cases
🔵 Claude — architecture and synthesis
🟣 Perplexity — CVE lookup (if available)

---

When the user invokes this command (e.g., `/octo:review <arguments>`):

## Step 1: Ask Clarifying Questions / Context Acquisition

**Determine mode based on session autonomy:**

If `AUTONOMY_MODE` env var is `autonomous`, or session is running headlessly, or `OCTOPUS_WORKFLOW_PHASE` is set (indicating a pipeline context like `/octo:develop` or `/octo:embrace`), skip Q&A and auto-infer with ALL focus areas:
1. Run `git diff --cached` — if non-empty, `target=staged`
2. Run `gh pr view --json number` — if open PR exists, set `target=<pr_number>`
3. Otherwise `target=working-tree`
4. Set `provenance=unknown`, `autonomy=autonomous`, `publish=ask`, `debate=auto`, `focus=["correctness","security","architecture","tdd"]`

**Otherwise (supervised mode), use AskUserQuestion:**

```javascript
AskUserQuestion({
  questions: [
    {
      question: "What should be reviewed?",
      header: "Target",
      multiSelect: false,
      options: [
        {label: "Staged changes", description: "git diff --cached — what you're about to commit"},
        {label: "Open PR", description: "Review the current branch's open pull request"},
        {label: "Working tree", description: "All uncommitted changes"},
        {label: "Specific path", description: "A file or directory"}
      ]
    },
    {
      question: "What should the fleet focus on?",
      header: "Focus",
      multiSelect: true,
      options: [
        {label: "Correctness", description: "Logic bugs, edge cases, regressions"},
        {label: "Security & Edge Cases", description: "OWASP, race conditions, partial failures"},
        {label: "Architecture", description: "API contracts, integration, breaking changes"},
        {label: "TDD discipline", description: "Verify failing-test-first evidence and minimal implementation"},
        {label: "All areas (Recommended)", description: "Correctness + Security + Architecture + TDD"}
      ]
    },
    {
      question: "How was this code produced?",
      header: "Provenance",
      multiSelect: false,
      options: [
        {label: "Human-authored", description: "Standard review"},
        {label: "AI-assisted", description: "Review for over-abstraction and weak tests"},
        {label: "Autonomous / Dark Factory", description: "Elevated rigor: verify tests, wiring, operational safety"},
        {label: "Unknown", description: "Assume less context, verify from code and tests"}
      ]
    },
    {
      question: "Should findings be posted to the open PR?",
      header: "Publish",
      multiSelect: false,
      options: [
        {label: "Ask me after review", description: "Show findings first, then decide"},
        {label: "Auto-post if confident", description: "Post inline comments when confidence ≥ 85%"},
        {label: "Never — terminal only", description: "Always show in terminal, never post to PR"}
      ]
    }
  ]
})
```

## Step 2: Build Review Profile

After receiving answers, map them to a JSON profile:

```javascript
const profile = {
  target: <from answer or inference>,  // "staged" | "working-tree" | PR# | path
  focus: <multi-select answers as array>,
  provenance: <answer>,                // "human" | "ai-assisted" | "autonomous" | "unknown"
  autonomy: <detected mode>,           // "supervised" | "autonomous"
  publish: <answer>,                   // "ask" | "auto" | "never"
  debate: "auto"                       // always default to auto debate
}
```

## Step 3: Execute Review Pipeline

Run via Bash tool:

```bash
/path/to/orchestrate.sh code-review '<profile-json>'
```

Where `<profile-json>` is the JSON profile built in Step 2.

The pipeline runs 3 rounds (parallel fleet → verification → synthesis) and outputs findings. If a PR is open and publish is not "never", it offers to post inline comments.

## What `/octo:review` checks

- Correctness: logic bugs, edge cases, regressions, unreachable code
- Security: OWASP Top 10, injection, auth flaws, data exposure (Gemini specialist)
- Architecture: API contracts, integration issues, breaking changes (Claude specialist)
- CVE lookup: known vulnerabilities in dependencies (Perplexity → Gemini → Claude WebSearch)
- TDD compliance and test-first evidence (when provenance is AI-assisted/autonomous)
- Autonomous codegen risk: placeholder logic, unwired code, speculative abstractions

## REVIEW.md support

Add a `REVIEW.md` file to your repository root to guide what `/octo:review` flags.
Drop-in compatible with Claude Code's managed Code Review service.

```markdown
# Code Review Guidelines

## Always check
- New API endpoints have corresponding integration tests

## Style
- Prefer early returns over nested conditionals

## Skip
- Generated files under src/gen/
```
