---
command: review
description: Enhanced multi-LLM review with inline PR comments — escalation path beyond Claude-native /review
---

# /octo:review

## Positioning

Three review entry points coexist in Claude Code v2.1.111+ — pick the right one per context:

| Command | Scope | Providers | When |
|---|---|---|---|
| Claude-native `/review` | Single-turn, current diff | Claude only | Ordinary review, one perspective suffices |
| `/ultrareview` (CC v2.1.111+) | Cloud, parallel multi-agent | Claude parallelism | Pre-merge PR review without leaving CC |
| `/octo:review` (this) | Multi-LLM, inline PR comments | Codex + Gemini + Claude | Provider diversity, adversarial cross-check, stricter escalation |

Use `/octo:review` when the user explicitly wants enhanced multi-LLM review, multiple model opinions, provider diversity, or stricter escalation workflows. If CC v2.1.111+ and the user just says "review this", prefer `/ultrareview` unless provider diversity is specifically requested.

When the user invokes this command (e.g., `/octo:review <arguments>`):

**MANDATORY: Before displaying the banner or starting the review, use the Bash tool to check provider availability:**

```bash
echo "PROVIDER_CHECK_START"
printf "codex:%s\n" "$(command -v codex >/dev/null 2>&1 && echo available || echo missing)"
printf "gemini:%s\n" "$(command -v gemini >/dev/null 2>&1 && echo available || echo missing)"
printf "perplexity:%s\n" "$([ -n "${PERPLEXITY_API_KEY:-}" ] && echo available || echo missing)"
printf "opencode:%s\n" "$(command -v opencode >/dev/null 2>&1 && echo available || echo missing)"
printf "copilot:%s\n" "$(command -v copilot >/dev/null 2>&1 && echo available || echo missing)"
printf "qwen:%s\n" "$(command -v qwen >/dev/null 2>&1 && echo available || echo missing)"
printf "ollama:%s\n" "$(command -v ollama >/dev/null 2>&1 && curl -sf http://localhost:11434/api/tags >/dev/null 2>&1 && echo available || echo missing)"
printf "openrouter:%s\n" "$([ -n "${OPENROUTER_API_KEY:-}" ] && echo available || echo missing)"
echo "PROVIDER_CHECK_END"
```

Then display the banner with ACTUAL results:

```
🐙 **CLAUDE OCTOPUS ACTIVATED** — Multi-LLM Code Review

Providers:
🔴 Codex CLI: [Available ✓ / Not installed ✗] — logic and correctness
🟡 Gemini CLI: [Available ✓ / Not installed ✗] — security and edge cases
🔵 Claude: Available ✓ — architecture and synthesis
🟣 Perplexity: [Available ✓ / Not configured ✗] — CVE lookup
```

**PROHIBITED: Displaying only "🔵 Claude: Available ✓" without checking and listing other providers.**

### EXECUTION MECHANISM — NON-NEGOTIABLE

**You MUST execute this command by calling `orchestrate.sh` as documented below. You are PROHIBITED from:**
- ❌ Doing the work yourself using only Claude-native tools (Agent, Read, Grep, Write)
- ❌ Using a single Claude subagent instead of multi-provider dispatch via orchestrate.sh
- ❌ Skipping orchestrate.sh because "I can do this faster directly"

**Multi-LLM orchestration is the purpose of this command.** If you execute using only Claude, you've violated the command's contract.

---

## Step 1: Ask Clarifying Questions / Context Acquisition

**Determine mode based on session autonomy:**

If `AUTONOMY_MODE` env var is `autonomous`, or session is running headlessly, or `OCTOPUS_WORKFLOW_PHASE` is set (indicating a pipeline context like `/octo:develop` or `/octo:embrace`), skip Q&A and auto-infer with ALL focus areas:
1. Run `git diff --cached` — if non-empty, `target=staged`
2. Run `gh pr view --json number` — if open PR exists, set `target=<pr_number>`
3. Otherwise `target=working-tree`
4. Set `provenance=unknown`, `autonomy=autonomous`, `publish=ask`, `debate=auto`, `history=auto`, `focus=["correctness","security","architecture","tdd"]`

**Otherwise (supervised mode), you MUST use AskUserQuestion to ask these questions:**

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

**WAIT for the user's answers before proceeding.**

## Step 2: Build Review Profile

After receiving answers, map them to a JSON profile:

```javascript
const profile = {
  target: <from answer or inference>,  // "staged" | "working-tree" | PR# | path
  focus: <multi-select answers as array>,
  provenance: <answer>,                // "human" | "ai-assisted" | "autonomous" | "unknown"
  autonomy: <detected mode>,           // "supervised" | "autonomous"
  publish: <answer>,                   // "ask" | "auto" | "never"
  debate: "auto",                      // always default to auto debate
  history: "auto"                      // "auto" | "fresh"
}
```

If the user includes `fresh` in the command text, do not treat it as a file path. Keep the normal target inference and set `history: "fresh"` so this run ignores prior PR review rounds.

## Step 3: Execute Review Pipeline

Run via Bash tool:

```bash
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh code-review '<profile-json>'
```

Where `<profile-json>` is the JSON profile built in Step 2.

The pipeline runs 3 rounds (parallel fleet → verification → synthesis) and outputs findings. If a PR is open and publish is not "never", it offers to post inline comments.

Round-aware PR history is enabled automatically for open PR reviews. Local state is stored at `~/.claude-octopus/pr-state/<host>/<owner>/<repo>/<pr>.json` and is used to show addressed, persistent, new, and regressed finding counts across repeated `/octo:review` runs. Set `OCTOPUS_PR_HISTORY=0` before invoking the command to disable all history reads and writes.

Each review also writes a local proof packet under `~/.claude-octopus/runs/<run-id>/`. The packet includes `state.json`, `proof.jsonl`, `summary.md`, findings artifacts, and provider substitution records so review claims can be checked after the chat scroll is gone. Set `OCTOPUS_PROOF_PACKET=0` to disable proof packet writes.

If a project already has `graphify-out/GRAPH_REPORT.md`, `/octo:review` also passes a compact Graphify companion context into the reviewer prompt as an orientation map. This is passive: Octopus does not build or refresh the graph during review, and `OCTOPUS_GRAPHIFY=0` disables the injection.

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
