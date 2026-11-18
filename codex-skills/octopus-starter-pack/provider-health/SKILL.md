---
name: provider-health
description: "Starter: one-screen provider health summary — availability, auth method, version drift, and cost posture for every seatable provider"
disable-model-invocation: true
---

> **Host: Codex CLI** — This skill was designed for Claude Code and adapted for Codex.
> Invoke installed skills by their `$skill-name`. Known Octopus commands are mapped below. A remaining `/octo:*` reference is a Claude Code command; do not execute it in Codex or invent an equivalent.
> Before the first helper call, derive the absolute plugin root from this loaded skill's path by finding its ancestor containing `.codex-plugin/plugin.json`. Verify that root, then bind `OCTO_ROOT` to it in each fresh shell or use the verified absolute helper path. Do not infer it from the user's project or assume exports survive tool calls. Stop and report a missing installation if the root cannot be verified.
> Use the active Codex shell and subagent tools. Do not claim a provider, model, or host subagent is available until the current session exposes it.
> Claude-native tool calls in examples are prompt templates to adapt, not Codex call signatures. If a mandatory verification agent or tool is unavailable or unauthorized, report that verification did not run and stop the affected completion step. Never claim a skipped check passed.
> Attribute commits only to actual contributors; do not copy fixed model attribution trailers from examples.
> For host tool equivalents, see `codex-skills/blocks/codex-host-adapter.md`.

> Invoke this entry as `$provider-health` in Codex. Code-fenced Claude command examples are reference text, not Codex shell commands.


# Provider Health Check Summary (Starter Pack)

Produce a one-screen health summary of every provider Octopus can seat, so the user knows what a workflow will actually dispatch to before spending money.

## When to use

The user asks "what providers do I have?", a workflow banner showed `(unavailable - skipping)`, or a session is starting on a new machine.

## Steps

1. **Detect.** Run `${OCTO_ROOT:?}/scripts/helpers/check-providers.sh` and `${OCTO_ROOT:?}/scripts/helpers/check-versions.sh`.
2. **Summarize per provider.** For each seat report: available or not, auth method (env key, oauth session, subscription), and the model it would resolve to today. Include the claude-sdk seat when `CLAUDE_SDK_API_KEY` is set (Agent SDK, Opus 5 by default, 1M context). Flag Claude Code older than v2.1.280 for Opus 5.5, older than v2.1.219 for Opus 5, and Codex CLI older than v0.144.0 for GPT-5.6.
3. **Flag problems, ranked.** Expired auth first (breaks dispatch), then version drift (behavior skew), then missing optional providers (reduced diversity). One line each with the exact fix command (`grok login`, `opencode auth login`, key export).
4. **State the cost posture.** Split the roster into included (Claude, agy, copilot, ollama, cursor-agent) versus billed (codex, perplexity, grok, openrouter, atlascloud, claude-sdk) so the user can predict what a multi-provider workflow costs before running it.

## Output shape

A single table, one row per provider, columns: Provider, Status, Auth, Model, Cost. Below it, at most three ranked fix-it lines. No prose beyond that.

## Guardrails

- Report only what the detection scripts return this session. A provider that worked yesterday but fails detection now is DOWN; do not soften it.
