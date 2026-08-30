---
command: usage
disable-model-invocation: true
description: "[advanced] Per-provider, per-skill, and per-MCP-server cost and token breakdown (Claude Code /usage schema)"
allowed-tools: Bash, Read, Glob
---

# Usage Report (/octo:usage)

**Your first output line MUST be:** `🐙 Octopus Usage Report`

Produce a per-provider, per-skill, and per-MCP-server cost and token breakdown from recorded Octopus usage artifacts. Output schema matches Claude Code's native `/usage` report (`claude-code/usage-v1`), so results can be compared or merged with the host session's own usage pane.

## EXECUTION CONTRACT (Mandatory)

### STEP 1: Run the report helper

```bash
OCTO_ROOT="${CLAUDE_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}"
"$OCTO_ROOT/scripts/helpers/usage-report.sh" --view usage --format table
```

If the user asked for machine-readable output (or passed `--format json`):

```bash
OCTO_ROOT="${CLAUDE_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}"
"$OCTO_ROOT/scripts/helpers/usage-report.sh" --view usage --format json
```

The helper reads:
- `~/.claude-octopus/usage/*.jsonl` — JSONL records written by `hooks/subagent-stop-gate.sh` and provider adapters
- `~/.claude-octopus/results/**/summary.json` — council and workflow roster artifacts (query counts)

### STEP 2: Present the breakdown

Show the helper's table output directly. Then add a one-paragraph interpretation:
- Which provider drove the most estimated cost
- Whether any external CLI seat (🔴 Codex, 🧭 Antigravity) dominates and could be swapped for an included provider
- Whether MCP server usage is material

### STEP 3: Flag empty data honestly

If the helper prints `No usage records found`, say so and point the user at `OCTOPUS_SUBAGENT_GATE_STRICT` and the SubagentStop gate hook (`hooks/subagent-stop-gate.sh`), which populates the usage log as subagents complete. Do not fabricate numbers.

## Cost reference

Rates come from `config/model-pricing.tsv`. The helper is the only calculator.
Providers with subscription or local backends such as agy, Copilot, Ollama,
Cursor Agent, and native OpenCode report $0.00.
