---
command: preflight
description: Check provider health before running multi-LLM workflows
allowed-tools: Bash
---

# Octopus Provider Health Check

Run a quick health check on all configured AI providers before starting a workflow.

```bash
OCTO_ROOT="${OCTO_ROOT:-${CLAUDE_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}}"
bash "${OCTO_ROOT}/scripts/helpers/preflight.sh"
```

Use this before `/octo:embrace`, `/octo:research`, or `/octo:council` to confirm your providers are available and avoid mid-workflow surprises.

**Common issues:**
- `Ollama` shows unavailable → start it with `ollama serve`
- `Codex CLI` unavailable → run `codex login` or `npm install -g @openai/codex`
- `Gemini CLI` unavailable → run `gemini auth login` or `npm install -g @google/gemini-cli`
- `Antigravity CLI` unavailable → verify `agy` is on PATH, then run `agy login` or reinstall Antigravity CLI

Run `/octo:setup` to install or configure any missing provider.
