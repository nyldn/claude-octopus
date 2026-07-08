---
name: provider-health
description: "Starter: one-screen provider health summary — availability, auth method, version drift, and cost posture for every seatable provider"
---

# Provider Health Check Summary (Starter Pack)

Produce a one-screen health summary of every provider Octopus can seat, so the user knows what a workflow will actually dispatch to before spending money.

## When to use

The user asks "what providers do I have?", a workflow banner showed `(unavailable - skipping)`, or a session is starting on a new machine.

## Steps

1. **Detect.** Run `${CLAUDE_PLUGIN_ROOT}/scripts/helpers/check-providers.sh` and `${CLAUDE_PLUGIN_ROOT}/scripts/helpers/check-versions.sh`.
2. **Summarize per provider.** For each seat report: available or not, auth method (env key, oauth session, subscription), and the model it would resolve to today. Include the claude-sdk seat when `CLAUDE_SDK_API_KEY` is set (Agent SDK, Opus 4.8, 1M context).
3. **Flag problems, ranked.** Expired auth first (breaks dispatch), then version drift (behavior skew), then missing optional providers (reduced diversity). One line each with the exact fix command (`grok login`, `opencode auth login`, key export).
4. **State the cost posture.** Split the roster into included (Claude, agy, copilot, ollama, cursor-agent) versus billed (codex, perplexity, grok, openrouter, atlascloud, claude-sdk) so the user can predict what a multi-provider workflow costs before running it.

## Output shape

A single table, one row per provider, columns: Provider, Status, Auth, Model, Cost. Below it, at most three ranked fix-it lines. No prose beyond that.

## Guardrails

- Report only what the detection scripts return this session. A provider that worked yesterday but fails detection now is DOWN; do not soften it.
