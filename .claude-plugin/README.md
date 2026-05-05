<!-- Plugin name MUST remain "octo" — see PLUGIN_NAME_LOCK.md -->

# Claude Octopus

**One prompt. Up to eight AI providers checking each other's work.** Claude Octopus turns Claude Code into a multi-LLM orchestration engine — Codex, Gemini, Copilot, Qwen, Ollama, Perplexity, and OpenRouter all contribute perspectives, then a 75% consensus gate catches disagreements before they ship.

**Claude-native first, Octopus for escalation.** Use Claude-native `/init`, `/review`, and `/security-review` when Claude is enough. Use Octopus when you want multiple model opinions, adversarial review, or stricter multi-LLM workflows.

## What Changes

Without Octopus, you ask one model and trust the answer. With it:

```
You:        /octo:auto should I use Redis or DynamoDB for sessions?

What runs:  🔴 Codex analyzes implementation trade-offs
            🟡 Gemini researches ecosystem patterns
            🔵 Claude synthesizes + applies consensus gate

You get:    A structured comparison with three independent viewpoints,
            scored for agreement. Disagreements are flagged, not hidden.
```

This works for research, escalated code review, debugging, TDD, escalated security audits, UI design, PRDs, and full build-to-ship workflows — 48 commands, 52 skills, 32 specialized personas.

## Install

```bash
claude plugin marketplace add https://github.com/nyldn/plugins.git
claude plugin install octo@nyldn-plugins
```

The `nyldn-plugins` marketplace is shared with Image Agency at
`https://github.com/nyldn/plugins.git`, so users can also install
`img@nyldn-plugins` without adding a second nyldn marketplace.

Then run `/octo:setup` — it detects your providers, shows what's available, and walks you through config. **Zero external providers required to start.** Claude is built in; add others one at a time.

## Common Jobs

| I want to... | Type this |
|---|---|
| Research a topic with multiple AI perspectives | `/octo:research htmx vs react` |
| Debate two approaches with structured scoring | `/octo:debate monorepo vs microservices` |
| Build a feature end-to-end (research → ship) | `/octo:embrace build stripe integration` |
| Review code with enhanced multi-model analysis | `/octo:review` |
| Run an escalated security audit (OWASP + adversarial) | `/octo:security` |
| Write tests first, then code | `/octo:tdd create user auth` |
| Go from spec to working software autonomously | `/octo:factory "CSV to JSON converter"` |
| Just do something quick | `/octo:quick fix the login bug` |

Don't know the command? Describe what you need — `/octo:auto <anything>` routes to the right workflow.

## Prerequisites

- Claude Code v2.1.83+
- Zero external providers needed (Claude is built in)
- Optional: Codex CLI, Gemini CLI, Copilot, Qwen, Ollama, Perplexity API key, OpenRouter API key
- Five of eight providers cost nothing extra (OAuth, free tiers, or local)

## One Limitation

Octopus orchestrates — it doesn't replace domain knowledge. If three models confidently agree on the wrong answer, the consensus gate won't catch it. Use it to surface disagreements and broaden perspectives, not as a substitute for understanding.

## Learn More

- [**Full README**](../README.md) — feature deep-dive, provider grid, architecture, star history
- [**Command Reference**](../docs/COMMAND-REFERENCE.md) — all 48 commands with triggers
- [**Persona Guide**](../docs/AGENTS.md) — 32 specialized agents
- [**Changelog**](../CHANGELOG.md) — release history
- [**Issues**](https://github.com/nyldn/claude-octopus/issues) — bugs and feature requests
