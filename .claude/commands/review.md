---
command: review
description: Expert multi-LLM code review with inline PR comments — competes with CC Code Review
---

# /octo:review

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

### MODEL RESOLUTION — NON-NEGOTIABLE

**You MUST NEVER hardcode model names when dispatching providers.** Models change frequently and your training data is stale.

**Before ANY provider dispatch** (whether via orchestrate.sh or manual fallback), resolve the correct model:

```bash
# Resolve the configured model for a provider:
PLUGIN_DIR="$(find ~/.claude/plugins -name 'octo-dispatch.sh' -path '*/scripts/*' 2>/dev/null | head -1 | xargs dirname)"
CODEX_MODEL=$("$PLUGIN_DIR/octo-dispatch.sh" --resolve codex)
GEMINI_MODEL=$("$PLUGIN_DIR/octo-dispatch.sh" --resolve gemini)
QWEN_MODEL=$("$PLUGIN_DIR/octo-dispatch.sh" --resolve qwen)
```

**If you must dispatch manually** (e.g., the review target is not a code diff), use `octo-dispatch.sh`:
```bash
echo "your prompt" | "$PLUGIN_DIR/octo-dispatch.sh" codex
echo "your prompt" | "$PLUGIN_DIR/octo-dispatch.sh" gemini
echo "your prompt" | "$PLUGIN_DIR/octo-dispatch.sh" qwen
```

**PROHIBITED model names** (these are ALWAYS wrong — never type them manually):
- `o3`, `o3-mini`, `o4-mini`, `gpt-4o`, `gpt-4o-mini` — stale OpenAI names
- `gemini-2.5-pro`, `gemini-2.0-flash` — stale Google names
- Any model name from your training data that you "just know"

The config at `~/.claude-octopus/config/providers.json` is the ONLY source of truth.

---

## Step 1: Ask Clarifying Questions / Context Acquisition

**Determine mode based on session autonomy:**

If `AUTONOMY_MODE` env var is `autonomous`, or session is running headlessly, or `OCTOPUS_WORKFLOW_PHASE` is set (indicating a pipeline context like `/octo:develop` or `/octo:embrace`), skip Q&A and auto-infer with ALL focus areas:
1. Run `git diff --cached` — if non-empty, `target=staged`
2. Run `gh pr view --json number` — if open PR exists, set `target=<pr_number>`
3. Otherwise `target=working-tree`
4. Set `provenance=unknown`, `autonomy=autonomous`, `publish=ask`, `debate=auto`, `focus=["correctness","security","architecture","tdd"]`

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
