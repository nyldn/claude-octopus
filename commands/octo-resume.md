---
description: "Resume a previous agent by ID — continue an interrupted task where it left off"
---

# /octo:resume — Agent Resume

## MANDATORY COMPLIANCE — DO NOT SKIP

**When the user invokes `/octo:resume`, you MUST follow the resume workflow below. You are PROHIBITED from:**
- Starting fresh instead of resuming the previous agent's work
- Skipping the agent ID lookup and just doing the task from scratch
- Deciding it's "easier to start over" than to resume

**The user chose `/octo:resume` because they want to continue interrupted work, not restart it.**

---

**Your first output line MUST be:** `🐙 Octopus Agent Resume`

Resume a previously-running Claude agent by ID. Picks up the agent's transcript and continues where it left off.

## Step 1: Get the Agent ID

If you don't have the agent ID:
- Check `/octo:sentinel` output for running agent IDs
- Look in `~/.claude-octopus/results/` for recent result files (filename prefix contains agent type + task ID)
- The agent ID was shown when the agent was originally spawned

## Step 2: Resume

Use the Bash tool to execute:
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
- Agent must have been a Claude agent (not Codex/Gemini — those don't support transcripts)
- CC v2.1.77+: Resume uses `SendMessage` (auto-resumes stopped agents). The `Agent(resume:)` parameter was removed in v2.1.77.

Run `/octo:doctor` to verify flags are active.

## Fallback

If continuation is not supported, spawn a fresh agent with `/octo:develop` and describe what was in progress.
