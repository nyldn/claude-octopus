---
description: "Quick execution mode for ad-hoc tasks without full workflow overhead"
---

# Quick Mode Command

**Your first output line MUST be:** `🐙 Octopus Quick Mode`

Execute ad-hoc tasks without multi-AI orchestration overhead.

## Usage

```
/octo:quick "<task description>"
```

## When to Use

**Perfect for:**
- Bug fixes with known solutions
- Configuration updates
- Small refactorings
- Documentation fixes
- Dependency updates
- Typo corrections

**NOT for:**
- New features
- Architecture changes
- Security-sensitive work
- Tasks requiring research

## Examples

```
/octo:quick "fix typo in README"
/octo:quick "update Next.js to v15"
/octo:quick "remove console.log statements"
/octo:quick "add error handling to login function"
```

## What It Does

1. Delegates the implementation to Codex CLI when available
2. Uses Claude only as the host/supervisor and fallback
3. Creates atomic commit
4. Updates state
5. Generates summary

**Skips:** Research, planning, multi-AI validation

## Execution Policy

Quick mode is Codex-first by default. For any non-meta implementation task, your first tool action after the banner MUST be a Bash call to Codex CLI. Do not implement directly in Claude unless Codex is unavailable, unauthenticated, or fails. Before editing directly, check that Codex is available (`command -v codex`) and authenticated (`~/.codex/auth.json` or `OPENAI_API_KEY`).

If Codex is available, delegate the task with `codex exec --skip-git-repo-check --full-auto --model gpt-5.4 -c model_reasoning_effort="medium" --sandbox workspace-write -`, passing the user request and relevant local repo instructions on stdin. Claude should only supervise, summarize the result, and perform small fallback edits if Codex fails.

If Codex is unavailable or unauthenticated, fall back to Claude Sonnet. Do not use Opus for quick mode unless the user explicitly requests it.

## Cost

Quick mode uses Codex CLI first.
Claude remains the host/supervisor and fallback only.
No Gemini, Opus, research, or multi-AI validation costs.

## When to Escalate

If the task becomes complex:
- Use `/octo:discover` for research
- Use `/octo:define` for planning
- Use `/octo:develop` for building
- Use `/octo:deliver` for validation
