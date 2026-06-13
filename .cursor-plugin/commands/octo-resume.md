---
description: "\"[advanced] Resume a previous agent by ID — continue an interrupted task where it left off\""
---

# /octo:resume — Agent Resume

**Your first output line MUST be:** `🐙 Octopus Agent Resume`

Resume a previously-running Claude agent by ID. Picks up the agent's transcript and continues where it left off.

## MANDATORY COMPLIANCE — DO NOT SKIP

**When the user explicitly invokes `/octo:resume`, you MUST call the `agent-resume` orchestrator path below.** You are PROHIBITED from pretending to resume an agent from memory or starting unrelated fresh work without telling the user.

## Step 1: Get the Agent ID

If you don't have the agent ID:
- Check `/octo:sentinel` output for running agent IDs
- Look in `~/.claude-octopus/results/` for recent result files (filename prefix contains agent type + task ID)
- The agent ID was shown when the agent was originally spawned

## Step 2: Resume

Use the Bash tool to execute:

**Preflight check — Ensure plugin root is resolvable (run via Bash tool FIRST):**

```bash
set -euo pipefail

OCTO_ROOT="${HOME}/.claude-octopus/plugin"
if [[ ! -x "$OCTO_ROOT/scripts/orchestrate.sh" ]]; then
  helper="$OCTO_ROOT/scripts/helpers/ensure-plugin-root.sh"
  if [[ ! -x "$helper" ]]; then
    helper="$(find "${HOME}/.claude/plugins/cache" "${HOME}/Library/Application Support/Claude" "${LOCALAPPDATA:-/dev/null}/Claude" "${XDG_DATA_HOME:-${HOME}/.local/share}/Claude" -maxdepth 8 -path "*/nyldn-plugins/octo/*/scripts/helpers/ensure-plugin-root.sh" -print -quit 2>/dev/null)"
  fi
  [[ -x "$helper" ]] && bash "$helper" >/dev/null 2>&1 || true
fi
test -x "$OCTO_ROOT/scripts/orchestrate.sh" && echo "plugin-root:ok" || echo "plugin-root:missing"
```

If the output is `plugin-root:missing`, stop and ask the user to run `/octo:setup`.


```bash
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh agent-resume "$ARGUMENTS"
```

Pass the agent ID as `$ARGUMENTS`. Optionally append a follow-up prompt:

```bash
# Just agent ID (resumes with "Continue where you left off.")
orchestrate.sh agent-resume abc123

# Agent ID + custom prompt
orchestrate.sh agent-resume abc123 "fix the failing test in auth.ts"
```

## Requirements

- Claude Code v2.1.34+ (`SUPPORTS_CONTINUATION=true`, `SUPPORTS_STABLE_AGENT_TEAMS=true`)
- Agent Teams enabled (required for agent transcript access)
- Agent must have been a Claude agent (not an external CLI agent — those don't support transcripts)
- CC v2.1.77+: Resume uses `SendMessage` (auto-resumes stopped agents). The `Agent(resume:)` parameter was removed in v2.1.77.

Run `/octo:doctor` to verify flags are active.

## Fallback

If continuation is not supported, spawn a fresh agent with `/octo:develop` and describe what was in progress.
