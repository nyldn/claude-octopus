---
name: sys-configure
description: "Configure Claude Octopus — redirects to /octo:setup interactive wizard"
disable-model-invocation: true
---

> **Host: Codex CLI** — This skill was designed for Claude Code and adapted for Codex.
> Cross-reference commands use installed skill names in Codex rather than `/octo:*` slash commands.
> Use the active Codex shell and subagent tools. Do not claim a provider, model, or host subagent is available until the current session exposes it.
> For host tool equivalents, see `skills/blocks/codex-host-adapter.md`.


# Configuration to setup redirect

This skill is an alias for `/octo:setup`. When triggered, invoke the setup command directly.

Setup uses a separate, private resume receipt. It rechecks readiness before
trusting a recorded stage, leaves interrupted human login incomplete, and marks
the receipt complete only after strict configuration persistence and readback.
The user runs browser-opening authentication in their own terminal. Remote
sessions never open it automatically.

**Action:** Run `/octo:setup` — the interactive setup wizard handles all configuration:
- Provider installation and auth
- RTK token optimization
- Work mode selection
- First-run onboarding

Do NOT duplicate setup logic here. Read
`${HOME}/.claude-octopus/plugin/commands/setup.md` and follow it only because
the user explicitly invoked this configuration skill.
