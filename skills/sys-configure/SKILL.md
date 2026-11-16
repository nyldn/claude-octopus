---
name: sys-configure
description: "Configure Octopus providers, authentication, and workflow preferences"
disable-model-invocation: true
---

> **Host: Codex CLI** — This skill was designed for Claude Code and adapted for Codex.
> Cross-reference commands use installed skill names in Codex rather than `/octo:*` slash commands.
> Use the active Codex shell and subagent tools. Do not claim a provider, model, or host subagent is available until the current session exposes it.
> For host tool equivalents, see `skills/blocks/codex-host-adapter.md`.


# Configuration to setup redirect

On Claude Code, this skill opens `/octo:setup`. On Codex, read the setup instructions
from the verified plugin installation and follow the steps supported by the current
host. Do not execute a Claude slash command in a shell or claim setup succeeded
without checking the resulting configuration.

Setup uses a separate, private resume receipt. It rechecks readiness before
trusting a recorded stage, leaves interrupted human login incomplete, and marks
the receipt complete only after strict configuration persistence and readback.
The user runs browser-opening authentication in their own terminal. Remote
sessions never open it automatically.

**Action:** On Claude Code, run `/octo:setup`. On Codex, load the setup instructions
below in the current conversation. The setup flow covers:
- Provider installation and auth
- RTK token optimization
- Work mode selection
- First-run onboarding

Do NOT duplicate setup logic here. Read
`${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}}/commands/setup.md` and follow it only because
the user explicitly invoked this configuration skill.
