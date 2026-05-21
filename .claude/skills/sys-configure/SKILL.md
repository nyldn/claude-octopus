---
name: sys-configure
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

# Configuration → Setup Redirect

This skill is an alias for `/octo:setup`. When triggered, invoke the setup command directly.

**Action:** Run `/octo:setup` — the interactive setup wizard handles all configuration:
- Provider installation and auth
- RTK token optimization
- Work mode selection
- First-run onboarding

Do NOT duplicate setup logic here. Just invoke the setup skill.
