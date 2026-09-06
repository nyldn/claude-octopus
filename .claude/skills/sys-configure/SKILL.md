---
name: sys-configure
disable-model-invocation: true
effort: low
user-invocable: true
aliases:
  - config
  - configure
description: Configure Claude Octopus — redirects to /octo:setup interactive wizard
trigger: |
  Use this skill when the user wants to "configure Claude Octopus", "setup octopus",
  "configure providers", "set up API keys for octopus", or mentions octopus configuration.
---

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
