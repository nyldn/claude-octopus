---
description: "Find an installed Octopus command for your task without calling a provider"
disable-model-invocation: true
allowed-tools: Bash, Read
---

# Command guide

Read the installed catalog and show a suitable next command. Do not start a
workflow, probe providers, change settings, or install anything.

Resolve the plugin root from `CLAUDE_PLUGIN_ROOT`, then `CODEX_PLUGIN_ROOT`,
then the stable `~/.claude-octopus/plugin` link. Run:

```bash
OCTO_ROOT="${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}}"
bash "$OCTO_ROOT/scripts/orchestrate.sh" guide
```

For a topic, pass the user's topic as one quoted argument to `guide`. For the
full catalog, pass `list`. Do not interpolate untrusted text into shell code.
Recommend only commands present in the returned catalog. Show examples with a
task, such as `/octo:auto "review the changes in this branch"`.

If the installed catalog cannot be read, report that error and suggest
`/octo:setup`. Do not invent commands from memory.
